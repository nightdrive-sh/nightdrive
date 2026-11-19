"""Files' changes to the file system: copying and moving into a folder, a new name, a new file or folder, and moving
back (the undo of a move or a rename). Plain Python, no Gio, so it runs and is tested anywhere; cli.py gives it its
commands and the window runs those (Ops.qml).

- Nothing is overwritten. A name already taken where a copy or move lands gets " (2)", " (3)"… before its suffix, as a
  copy pasted into its own folder does; a rename to a taken name is refused.
- A move is a rename where it can be (same disk): exact, and its undo too. Across disks it is a copy, then the
  original goes.
- A copy or move reports its progress (progress()), so a big one shows how far it is, and stops cleanly on SIGTERM
  (the toast's Stop): the file it was writing is removed, what was done stays done and is in the result for Undo.
- Unlike `nightdrive files` (Claude's rules), this is the user's own hand: hidden files and folders outside home are
  theirs to move too. What the user can't write, the system refuses, and the error says so.
"""
import os, shutil, signal, stat, time
from pathlib import Path

CHUNK = 1 << 20              # bytes read and written at a time: a progress line between chunks at most every TICK
TICK = 0.1                   # seconds between progress lines


class Refused(Exception):
    """A change that isn't made, in words for the toast."""


class Stopped(Exception):
    """SIGTERM came: what was done so far is in done."""


_stop = False


def _on_term(*_):
    global _stop
    _stop = True


def watch_stop():
    """From here on SIGTERM stops a copy between chunks instead of killing it mid-write."""
    signal.signal(signal.SIGTERM, _on_term)


def valid_name(name):
    name = (name or "").strip()
    if not name or name in (".", "..") or "/" in name or "\0" in name:
        raise Refused(f"“{name}” can't be a file's name.")
    return name


def numbered(name, n, is_dir=False):
    """name with " (n)" before its suffix: "photo (2).jpg", "backup (2).tar.gz"; a folder's at its end."""
    if n < 2:
        return name
    p = Path(name)
    stem, suffix = (name, "") if is_dir else (p.stem, p.suffix)
    if not is_dir and p.stem.endswith(".tar") and len(p.stem) > 4:     # ".tar.gz" stays together
        stem, suffix = p.stem[:-4], ".tar" + p.suffix
    return f"{stem} ({n}){suffix}"


def free_name(folder, name, is_dir=None):
    """name in folder, or the first numbered() one that isn't taken there."""
    folder = Path(folder)
    if is_dir is None:
        is_dir = (folder / name).is_dir() and not (folder / name).is_symlink()
    for n in range(1, 10000):
        candidate = numbered(name, n, is_dir)
        if not os.path.lexists(folder / candidate):
            return candidate
    raise Refused(f"Too many named {name} in {folder}.")


def size_of(path):
    """Bytes under path, links not followed: what a copy has to write."""
    path = Path(path)
    if path.is_symlink() or not path.is_dir():
        try:
            return path.lstat().st_size if not path.is_symlink() else 0
        except OSError:
            return 0
    total = 0
    for root, dirs, files in os.walk(path):
        for f in files:
            try:
                st = os.lstat(os.path.join(root, f))
                if stat.S_ISREG(st.st_mode):
                    total += st.st_size
            except OSError:
                pass
    return total


class Progress:
    """Counts bytes written and calls report(done, total, name) at most every TICK seconds."""

    def __init__(self, total, report):
        self.total, self.done, self.report, self.last = total, 0, report, 0.0

    def add(self, n, name):
        self.done += n
        now = time.monotonic()
        if self.report and now - self.last >= TICK:
            self.last = now
            self.report(self.done, self.total, name)


def _copy_file(src, dst, prog):
    """One regular file, in chunks, its mode and times kept. Stopped midway, the part written is removed."""
    try:
        with open(src, "rb") as fi, open(dst, "xb") as fo:
            while True:
                if _stop:
                    raise Stopped()
                buf = fi.read(CHUNK)
                if not buf:
                    break
                fo.write(buf)
                prog.add(len(buf), src.name)
        shutil.copystat(src, dst)
    except BaseException:
        try:
            os.unlink(dst)
        except OSError:
            pass
        raise


def _copy_tree(src, dst, prog):
    """src (a file, a link or a folder) to dst, which doesn't exist yet. A link is copied as a link."""
    if src.is_symlink():
        os.symlink(os.readlink(src), dst)
    elif src.is_dir():
        os.mkdir(dst)
        for child in sorted(src.iterdir()):
            _copy_tree(child, dst / child.name, prog)
        shutil.copystat(src, dst)
    elif src.is_file():
        _copy_file(src, dst, prog)
    else:
        raise Refused(f"{src.name} isn't a file or a folder: it isn't copied.")


def _remove(path):
    path = Path(path)
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()


def _sources(paths, into):
    """The paths to copy or move into a folder, checked: each exists, none is the folder or holds it."""
    into = Path(into)
    if not into.is_dir():
        raise Refused(f"{into} isn't a folder.")
    real_into = into.resolve()
    out = []
    for p in paths:
        p = Path(p)
        if not os.path.lexists(p):
            raise Refused(f"{p.name} isn't there any more.")
        if p.is_dir() and not p.is_symlink():
            real = p.resolve()
            if real_into == real or real in real_into.parents:
                raise Refused(f"{p.name} can't go into itself.")
        out.append(p)
    return out


def copy(paths, into, report=None):
    """Copies paths into the folder into; {made: [new paths]}. A name taken there gets " (2)"."""
    srcs = _sources(paths, into)
    prog = Progress(sum(size_of(p) for p in srcs), report)
    made = []
    try:
        for p in srcs:
            dst = Path(into) / free_name(into, p.name)
            try:
                _copy_tree(p, dst, prog)
            except Stopped:
                if os.path.lexists(dst):     # a folder half copied goes too: it isn't what was asked for
                    _remove(dst)
                raise
            made.append(str(dst))
    except Stopped:
        return {"made": made, "stopped": True}
    return {"made": made}


def move(paths, into, report=None):
    """Moves paths into the folder into; {moved: [[new, old], …]}. One already there stays where it is."""
    srcs = _sources(paths, into)
    into = Path(into)
    moved, slow = [], []
    for p in srcs:
        if p.parent.resolve() == into.resolve():
            continue                          # cut and pasted where it is: nothing to do
        dst = into / free_name(into, p.name)
        try:
            os.rename(p, dst)
            moved.append([str(dst), str(p)])
        except OSError as e:
            if e.errno != 18:                 # EXDEV: another disk, copied below
                raise Refused(f"{p.name} couldn't be moved ({e.strerror}).")
            slow.append(p)
    if slow:
        prog = Progress(sum(size_of(p) for p in slow), report)
        for p in slow:
            dst = into / free_name(into, p.name)
            try:
                _copy_tree(p, dst, prog)
            except Stopped:
                if os.path.lexists(dst):
                    _remove(dst)
                return {"moved": moved, "stopped": True}
            _remove(p)
            moved.append([str(dst), str(p)])
    return {"moved": moved}


def rename(path, name):
    """A new name in the same folder; {moved: [[new, old]]}. A taken name is refused."""
    path = Path(path)
    name = valid_name(name)
    if not os.path.lexists(path):
        raise Refused(f"{path.name} isn't there any more.")
    if name == path.name:
        return {"moved": []}
    dst = path.parent / name
    # A change of case alone on a case-blind disk is the same file: let it through
    if os.path.lexists(dst) and not (dst.exists() and path.exists() and os.path.samefile(dst, path)):
        raise Refused(f"There is already a {name} here.")
    try:
        os.rename(path, dst)
    except OSError as e:
        raise Refused(f"{path.name} couldn't be renamed ({e.strerror}).")
    return {"moved": [[str(dst), str(path)]]}


def new(folder, name, is_dir):
    """A new empty file, or a folder; {made: [path]}. A taken name is refused."""
    folder = Path(folder)
    name = valid_name(name)
    dst = folder / name
    try:
        if is_dir:
            os.mkdir(dst)
        else:
            os.close(os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666))
    except FileExistsError:
        raise Refused(f"There is already a {name} here.")
    except OSError as e:
        raise Refused(f"{name} couldn't be made ({e.strerror}).")
    return {"made": [str(dst)]}


def move_back(pairs):
    """The undo of a move or rename: each [new, old] back to old, if it is still at new and old is free.
    {moved: [[old, new], …], left: [names not moved back]}."""
    moved, left = [], []
    for new_path, old in reversed(pairs):
        new_path, old = Path(new_path), Path(old)
        if not os.path.lexists(new_path) or os.path.lexists(old) or not old.parent.is_dir():
            left.append(new_path.name)
            continue
        try:
            os.rename(new_path, old)
        except OSError as e:
            if e.errno != 18:
                left.append(new_path.name)
                continue
            _copy_tree(new_path, old, Progress(0, None))
            _remove(new_path)
        moved.append([str(old), str(new_path)])
    return {"moved": moved, "left": left}
