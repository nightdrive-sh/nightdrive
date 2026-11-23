#!/usr/bin/python3 -I
"""Opening a file from Files (⏎, a double click, ⌘O): in its default app, or, when it is a program, only after asking.

  launch.py open PATH           opens PATH in its default app and prints nothing; a program prints
                                {"program": {...}} for the window to ask about, a file no app opens {"noapp": {...}}
  launch.py run PATH [--terminal] [--chmod]
                                runs the program in its own folder, apart from Files (--chmod: made executable first)

What a program is, is decided here and only here (program()): an ELF executable (an AppImage is one), or a script that
starts with #! and may run (x bit). A downloaded file never runs from a double click: open never runs anything, and the
window's confirm is the only way to run. A script without its x bit is text and opens as such (an editor), but an ELF
without it is still a program: the window offers to make it executable.
"""
import json, os, stat, subprocess, sys

TERMINAL = os.path.expanduser("~/.config/hypr/scripts/terminal")   # the desktop's default terminal (Default apps)
ELF_MAGIC = b"\x7fELF"
ET_EXEC, ET_DYN = 2, 3
PT_INTERP = 3
# Library endings: an ELF of type ET_DYN is a PIE program or a shared library, and a library has no interpreter as a
# rule, but some (libc) do, so the name settles it first
LIBRARY_ENDINGS = (".so", ".ko", ".o", ".a")


def _elf(head):
    """'program', 'library' or None from an ELF's first bytes (its header and program headers)."""
    if len(head) < 20 or not head.startswith(ELF_MAGIC):
        return None
    wide = head[4] == 2                       # EI_CLASS: 64-bit
    order = "little" if head[5] == 1 else "big"
    u16 = lambda at: int.from_bytes(head[at:at + 2], order)
    word = lambda at: int.from_bytes(head[at:at + (8 if wide else 4)], order)
    etype = u16(16)
    if etype == ET_EXEC:
        return "program"
    if etype != ET_DYN:
        return None                           # an object or a core dump
    # A PIE program asks for an interpreter (ld-linux) in its program headers; a library doesn't
    phoff = word(32 if wide else 28)
    entsize, count = (u16(54), u16(56)) if wide else (u16(42), u16(44))
    for i in range(min(count, 64)):
        at = phoff + i * entsize
        if at + 4 > len(head):
            break
        if int.from_bytes(head[at:at + 4], order) == PT_INTERP:
            return "program"
    return "library"


def program(path):
    """What runs PATH, or None when it isn't a program: {"kind": "elf"|"appimage"|"script", "executable": bool}."""
    try:
        st = os.stat(path)
        if not stat.S_ISREG(st.st_mode):
            return None
        with open(path, "rb") as f:
            head = f.read(4096)
    except OSError:
        return None
    executable = os.access(path, os.X_OK)
    name = os.path.basename(path).lower()
    if head.startswith(b"#!"):
        # Only with its x bit: a script without it is a text to read, as every file manager has it
        return {"kind": "script", "executable": True} if executable else None
    if _elf(head) != "program" or name.endswith(LIBRARY_ENDINGS) or ".so." in name:
        return None
    appimage = name.endswith(".appimage") or head[8:11] == b"AI\x02"   # the AppImage type 2 magic in EI_PAD
    return {"kind": "appimage" if appimage else "elf", "executable": executable}


def _default_app(path):
    """The default app's name for the file's type and the type's description; GIO as `gio open` reads it."""
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from apps import content_type
    ctype = content_type(path)
    app = Gio.AppInfo.get_default_for_type(ctype, False)
    return (app.get_display_name() if app else ""), Gio.content_type_get_description(ctype)


def open_file(path):
    """Opens PATH in its app (exec: nothing printed), or says why the window must ask (a program) or can't (no app)."""
    p = program(path)
    if p:
        return {"program": dict(p, name=os.path.basename(path), path=path)}
    app, kind = _default_app(path)
    if not app:
        return {"noapp": {"name": os.path.basename(path), "type": kind}}
    os.execvp("gio", ["gio", "open", path])


def run(path, terminal=False, make_executable=False):
    """Runs the program in its own folder, in a session of its own: it stays when Files closes. Returns at once."""
    path = os.path.abspath(path)
    p = program(path)
    if not p:
        raise RuntimeError(f"{os.path.basename(path)} isn't a program.")
    if not p["executable"]:
        if not make_executable:
            raise RuntimeError(f"{os.path.basename(path)} isn't executable.")
        mode = os.stat(path).st_mode
        os.chmod(path, mode | ((mode & 0o444) >> 2))     # x wherever r is, as chmod +x leaves it under a usual umask
    folder = os.path.dirname(path)
    argv = [TERMINAL, "--dir", folder, "--hold", "--", path] if terminal else [path]
    # start_new_session: out of Files' process group and session, so closing Files (or its supervisor stopping it)
    # doesn't take the program with it; this helper exits at once and leaves it to init. Its output goes nowhere:
    # Run in terminal is the way to see it.
    subprocess.Popen(argv, cwd=folder, start_new_session=True, close_fds=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ran": path, "terminal": terminal}


def main(args):
    try:
        if len(args) == 2 and args[0] == "open":
            print(json.dumps(open_file(args[1]), ensure_ascii=False))
        elif len(args) >= 2 and args[0] == "run":
            flags = set(args[2:])
            if flags - {"--terminal", "--chmod"}:
                sys.exit(__doc__)
            print(json.dumps(run(args[1], "--terminal" in flags, "--chmod" in flags), ensure_ascii=False))
        else:
            sys.exit(__doc__)
    except (OSError, RuntimeError) as e:
        print(getattr(e, "strerror", None) and f"{os.path.basename(args[1])}: {e.strerror}" or str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
