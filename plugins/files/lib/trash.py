"""The trash, freedesktop.org's way, so Files, Nautilus and `gio trash` share it: a file goes to Trash/files and a
NAME.trashinfo beside it in Trash/info says where it was and when it went. Home's disk uses ~/.local/share/Trash;
another disk (a USB stick) its own .Trash-UID at its top, where the info's path is relative to that top, so the
stick's trash goes with it.

A trashed thing is named by its info file's full path (an id), which tells the trash and the name apart: restore and
delete take those, and Undo keeps them. Nothing here follows a link: a link is trashed as the link.
"""
import datetime, os, shutil
from pathlib import Path
from urllib.parse import quote, unquote

from fsops import Refused, free_name, numbered


def home_trash():
    return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "Trash"


def mount_point(path):
    """The top of the disk path is on: the last folder up from it on the same device."""
    path = Path(os.path.abspath(path))
    dev = path.lstat().st_dev
    while path.parent != path:
        try:
            if path.parent.lstat().st_dev != dev:
                return path
        except OSError:
            return path
        path = path.parent
    return path


def trash_for(path):
    """(trash folder, topdir or None) for path: home's trash when it is on home's disk, else its disk's own."""
    home = home_trash()
    home.mkdir(parents=True, exist_ok=True, mode=0o700)
    if Path(path).lstat().st_dev == home.stat().st_dev:
        return home, None
    top = mount_point(path)
    uid = os.getuid()
    shared = top / ".Trash"
    # The spec's shared .Trash/UID: only when .Trash is a real folder with the sticky bit, else .Trash-UID
    if shared.is_dir() and not shared.is_symlink() and shared.stat().st_mode & 0o1000:
        return shared / str(uid), top
    return top / f".Trash-{uid}", top


def _write_info(info_dir, name, origin):
    """Claims name in the trash with its info file (O_EXCL, so two at once never take the same); False if taken."""
    when = datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    try:
        fd = os.open(info_dir / f"{name}.trashinfo", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        return False
    with os.fdopen(fd, "w") as f:
        f.write(f"[Trash Info]\nPath={quote(origin, safe='/')}\nDeletionDate={when}\n")
    return True


def trash_one(path):
    """Moves one path to its trash; the id (info file) it has there."""
    path = Path(os.path.abspath(path))
    if not os.path.lexists(path):
        raise Refused(f"{path.name} isn't there any more.")
    trash, top = trash_for(path)
    files, info = trash / "files", trash / "info"
    try:
        files.mkdir(parents=True, exist_ok=True, mode=0o700)
        info.mkdir(parents=True, exist_ok=True, mode=0o700)
    except OSError as e:
        raise Refused(f"{path.name} can't go to the trash on that disk ({e.strerror}).")
    origin = str(path) if top is None else str(path.relative_to(top))
    is_dir = path.is_dir() and not path.is_symlink()
    for n in range(1, 1000):
        name = numbered(path.name, n, is_dir)
        if not os.path.lexists(files / name) and _write_info(info, name, origin):
            break
    else:
        raise Refused(f"The trash has too many named {path.name}.")
    try:
        os.rename(path, files / name)
    except OSError as e:
        (info / f"{name}.trashinfo").unlink()
        raise Refused(f"{path.name} couldn't go to the trash ({e.strerror}).")
    return str(info / f"{name}.trashinfo")


def trash(paths):
    """{trashed: [ids], names: [their names]}: stops at the first that can't go, keeping those that went."""
    ids = []
    try:
        for p in paths:
            ids.append(trash_one(p))
    except Refused as e:
        if not ids:
            raise
        return {"trashed": ids, "names": [Path(p).name for p in paths[:len(ids)]], "error": str(e)}
    return {"trashed": ids, "names": [Path(p).name for p in paths]}


def read_info(info_file):
    """(where it was, when it went: "YYYY-MM-DDTHH:MM:SS") from an info file; a relative path is the disk's."""
    origin, when = None, ""
    for line in Path(info_file).read_text(errors="replace").splitlines():
        if line.startswith("Path="):
            origin = unquote(line[5:])
        elif line.startswith("DeletionDate="):
            when = line[13:]
    if origin is None:
        raise Refused(f"{Path(info_file).name} says nothing of where it was.")
    if not origin.startswith("/"):
        trash = Path(info_file).parent.parent
        top = trash.parent.parent if trash.parent.name == ".Trash" else trash.parent
        origin = str(top / origin)
    return origin, when


def _parts(item_id):
    info = Path(item_id)
    if info.suffix != ".trashinfo" or info.parent.name != "info":
        raise Refused(f"{info.name} isn't in a trash.")
    return info, info.parent.parent / "files" / info.name[:-len(".trashinfo")]


def restore(ids):
    """Each back where it was; {restored: [paths], left: [names that couldn't]}. One whose place is taken now goes back
    beside it with " (2)", as Nautilus does, rather than staying away."""
    restored, left = [], []
    for item_id in ids:
        try:
            info, files = _parts(item_id)
            origin, _ = read_info(info)
            target = Path(origin)
            target.parent.mkdir(parents=True, exist_ok=True)
            if os.path.lexists(target):
                target = target.parent / free_name(target.parent, target.name)
            os.rename(files, target)
            info.unlink()
            restored.append(str(target))
        except (OSError, Refused):
            left.append(Path(item_id).name[:-len(".trashinfo")])
    return {"restored": restored, "left": left}


def trashes():
    """Home's trash and those of the disks mounted now that have one of this user's."""
    out = [home_trash()]
    uid = os.getuid()
    try:
        with open("/proc/self/mounts") as f:
            mounts = [line.split()[1] for line in f]
    except OSError:
        mounts = []
    for m in mounts:
        m = m.replace("\\040", " ")
        if not m.startswith(("/run/media/", "/media/", "/mnt/")):
            continue
        for t in (Path(m) / f".Trash-{uid}", Path(m) / ".Trash" / str(uid)):
            if t.is_dir():
                out.append(t)
    return out


def listing():
    """Every trashed thing, newest first: [{id, name, origin, deleted, size, dir, path}]."""
    rows = []
    for t in trashes():
        info = t / "info"
        if not info.is_dir():
            continue
        for f in info.glob("*.trashinfo"):
            files = t / "files" / f.name[:-len(".trashinfo")]
            if not os.path.lexists(files):
                continue
            try:
                origin, when = read_info(f)
                st = files.lstat()
            except (OSError, Refused):
                continue
            is_dir = files.is_dir() and not files.is_symlink()
            rows.append({"id": str(f), "name": Path(origin).name, "origin": origin, "deleted": when,
                         "size": 0 if is_dir else st.st_size, "dir": is_dir, "path": str(files)})
    rows.sort(key=lambda r: r["deleted"], reverse=True)
    return rows


def count():
    return len(listing())


def delete(ids):
    """For good, from the trash: {deleted: n}."""
    n = 0
    for item_id in ids:
        info, files = _parts(item_id)
        if os.path.lexists(files):
            if files.is_dir() and not files.is_symlink():
                shutil.rmtree(files)
            else:
                files.unlink()
        info.unlink(missing_ok=True)
        n += 1
    return {"deleted": n}


def empty():
    """Every trash emptied for good: {deleted: n}."""
    return delete([r["id"] for r in listing()])
