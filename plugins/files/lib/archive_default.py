#!/usr/bin/python3 -I
"""Archives from other apps unpack the way Files does it: a hidden entry, the default of the archive types unpack.py
reads, so xdg-open, a browser's Open or a terminal's gio open unpacks a .zip beside itself in a Files window (#3719).

  archive_default.py on      write the entry; make it the default of each type the user hasn't chosen an app for
  archive_default.py off     take the entry and its lines in mimeapps.list away again (files disable)
  archive_default.py sync    on while Files is among the desktop's apps, else off (setup-user.sh, at every update)
  [--json]                   what changed, as {"added": [types], "dropped": [types]}

Without it GIO hands a .zip to Nautilus, which only registers the type. A default the user chose (Open with's Set as
default, Settings › Apps) stays theirs: only a type with no line of its own is written. The documents that are zips
underneath (.xlsx, .epub) are other types, and fitting_app.py never lets an archive's app carry over to them.
"""
import json, os, sys
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
DATA = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
ID = "nightdrive-files-extract.desktop"
FILES_ID = "nightdrive-files.desktop"                  # `files enable`'s: Files is among the apps while it is there
FILES = os.path.expanduser("~/.local/bin/files")       # full path: the compositor's PATH has no ~/.local/bin
# What unpack.py reads (zip, and tar plain or with gzip, bzip2, xz), by GIO's names for them. 7z, rar and a lone .gz
# keep their own apps
TYPES = ["application/zip", "application/x-zip-compressed", "application/x-tar", "application/x-compressed-tar",
         "application/x-bzip-compressed-tar", "application/x-bzip2-compressed-tar", "application/x-xz-compressed-tar"]

# default-apps: mimeapps.list's reading and writing (no .py: loaded by its path, no __pycache__ in the repo)
sys.dont_write_bytecode = True
_loader = SourceFileLoader("default_apps", os.path.join(REPO, "config", "hypr", "scripts", "default-apps"))
defaults = module_from_spec(spec_from_loader("default_apps", _loader))
_loader.exec_module(defaults)


def entry_path():
    return os.path.join(DATA, "applications", ID)


def write_entry():
    """The hidden entry. It lists the types, so GIO counts it among their apps; NoDisplay keeps it out of the launcher
    and Open with's lists."""
    exe = FILES
    if any(c in exe for c in ' "\\`$'):
        exe = '"' + exe.replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`").replace("$", "\\$") + '"'
    text = ("[Desktop Entry]\n"
            "# Written by plugins/files/lib/archive_default.py: archives from other apps unpack as in Files (#3719)\n"
            "Type=Application\nName=Extract in Files\nIcon=nightdrive-files\n"
            f"Exec={exe} extract %F\nMimeType={';'.join(TYPES)};\nNoDisplay=true\nTerminal=false\n")
    path = entry_path()
    try:
        if open(path, encoding="utf-8").read() == text:
            return
    except FileNotFoundError:
        pass
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def without(lines):
    """mimeapps.list's lines with the entry gone from every type's default and associations."""
    out, section = [], ""
    for line in lines:
        if line.startswith("["):
            section = line.strip()
        elif "=" in line and section in ("[Default Applications]", "[Added Associations]"):
            t, v = (s.strip() for s in line.split("=", 1))
            if ID in v.split(";"):
                rest = [a for a in v.split(";") if a and a != ID]
                if section == "[Default Applications]" or not rest:
                    continue
                line = f"{t}={';'.join(rest)};"
        out.append(line)
    return out


def on():
    write_entry()
    lines = defaults.read_mimeapps()
    own = defaults.defaults(lines)
    add = [t for t in TYPES if t not in own]
    if add:
        defaults.write_mimeapps(lines, {t: ID for t in add})
    return {"added": add, "dropped": []}


def off():
    try:
        os.remove(entry_path())
    except FileNotFoundError:
        pass
    lines = defaults.read_mimeapps()
    drop = [t for t, a in defaults.defaults(lines).items() if a == ID]
    new = without(lines)
    if new != lines:
        tmp = defaults.MIMEAPPS + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(new) + "\n")
        os.replace(tmp, defaults.MIMEAPPS)
    return {"added": [], "dropped": drop}


def main(args):
    verb = args[0] if args else ""
    if verb == "sync":
        verb = "on" if os.path.exists(os.path.join(DATA, "applications", FILES_ID)) else "off"
    if verb not in ("on", "off"):
        sys.exit(__doc__)
    r = on() if verb == "on" else off()
    if "--json" in args:
        print(json.dumps(r))
    elif r["added"]:
        print(f"Archives from other apps unpack in Files now ({len(r['added'])} types)")


if __name__ == "__main__":
    main(sys.argv[1:])
