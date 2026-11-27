"""File info (I, ⌘I in Files): who owns a file, who may read, write and run it, its size, times and type, and the one
permission change the panel offers, the executable switch.

Only the execute bit is offered as a switch: it is the one a user meets (a download that won't run, a script written
by hand), and turning it on as chmod +x does under a usual umask (x wherever r is) can't take access away from anyone.
Read and write for the group and others are shown, not changed: getting those wrong locks a user out of their own
files or opens them to others, and a terminal (T) is there for it. A folder's x means "may go into it", so a folder
has no switch, and neither has a link (chmod would change what it points to) nor a file the user doesn't own.

A folder's size walks it for at most SIZE_TIME seconds: a home folder would take minutes, so the panel then says
"more than" what it had counted.
"""
import grp, os, pwd, stat, time
from pathlib import Path

from fsops import Refused
from peek import content_type, iso

SIZE_TIME = 2.0    # s


def _name(getter, num):
    try:
        return getter(num)[0]
    except KeyError:
        return str(num)    # a uid with no account here (a USB stick's files from another machine)


def triplet(mode, shift):
    """{read, write, run} of one of owner (shift 6), group (3) and others (0)"""
    bits = (mode >> shift) & 7
    return {"read": bool(bits & 4), "write": bool(bits & 2), "run": bool(bits & 1)}


def folder_size(path, limit=SIZE_TIME):
    """(bytes, files, complete) under path, links not followed, walking for at most limit seconds"""
    total, files, end = 0, 0, time.monotonic() + limit
    for root, dirs, names in os.walk(path):
        for n in names:
            try:
                st = os.lstat(os.path.join(root, n))
            except OSError:
                continue
            if stat.S_ISREG(st.st_mode):
                total += st.st_size
                files += 1
        if time.monotonic() > end:
            return total, files, False
    return total, files, True


def info(path):
    p = Path(path)
    lst = p.lstat()
    link = os.readlink(p) if stat.S_ISLNK(lst.st_mode) else ""
    try:
        st = p.stat() if link else lst
    except OSError:
        st = lst    # a link to nothing: the link's own
    mode = stat.S_IMODE(st.st_mode)
    is_dir = stat.S_ISDIR(st.st_mode)
    mine = lst.st_uid == os.getuid() or os.getuid() == 0
    out = {
        "path": str(p), "name": p.name or str(p), "dir": is_dir, "link": link,
        "owner": _name(pwd.getpwuid, st.st_uid), "group": _name(grp.getgrgid, st.st_gid),
        "mode": f"{mode:03o}", "text": stat.filemode(st.st_mode),
        "perms": {"owner": triplet(mode, 6), "group": triplet(mode, 3), "others": triplet(mode, 0)},
        "modified": iso(st.st_mtime), "changed": iso(st.st_ctime), "accessed": iso(st.st_atime),
        "mine": mine, "executable": bool(mode & 0o111) and not is_dir,
        # The switch: a regular file of the user's own, not through a link
        "can_switch": mine and not link and stat.S_ISREG(st.st_mode),
    }
    out["type"], out["kind"] = ("inode/directory", "Folder") if is_dir else content_type(p)
    if is_dir:
        out["size"], out["files"], out["complete"] = folder_size(p)
    else:
        out["size"] = st.st_size
    return out


def set_executable(path, on):
    """The execute bit on (x wherever r is) or off (no x for anyone). Undo is set-mode with the mode it had."""
    p = Path(path)
    lst = p.lstat()
    if stat.S_ISLNK(lst.st_mode) or not stat.S_ISREG(lst.st_mode):
        raise Refused(f"{p.name} isn't a file: only a file can be made executable.")
    if lst.st_uid != os.getuid() and os.getuid() != 0:
        raise Refused(f"{p.name} is {_name(pwd.getpwuid, lst.st_uid)}'s: only they can change it.")
    was = stat.S_IMODE(lst.st_mode)
    new = (was | ((was & 0o444) >> 2)) if on else (was & ~0o111)
    if not new & 0o111 and on:
        new = was | 0o100    # read by no one (rare): the owner may run it
    os.chmod(p, new)
    return {"path": str(p), "mode": f"{new:03o}", "executable": bool(new & 0o111),
            "undo": ["set-mode", str(p), f"{was:03o}"]}


def set_mode(path, mode):
    """Undo's: the mode as it was. Only a file of the user's own, as set_executable."""
    p = Path(path)
    lst = p.lstat()
    if stat.S_ISLNK(lst.st_mode) or not stat.S_ISREG(lst.st_mode) or (lst.st_uid != os.getuid() and os.getuid() != 0):
        raise Refused(f"{p.name} can't be changed back.")
    m = int(mode, 8)
    if m & ~0o7777:
        raise Refused(f"{mode} isn't a mode.")
    os.chmod(p, m)
    return {"path": str(p), "mode": f"{m:03o}", "executable": bool(m & 0o111)}
