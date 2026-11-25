"""Disk Usage's walk over a folder (scan.py, clean.py): the space each entry takes on the disk (its blocks, as du
counts them, so a sparse file or a hard link isn't counted twice), staying on the disk the folder is on.

A tree of a whole home folder would hold millions of files, so it keeps only what is worth showing: an entry smaller
than `keep` bytes is folded into its folder's "smaller items" while the walk goes on, and prune() cuts the finished
tree down to what a few thousand rows can show. A folder whose detail was folded away is scanned again on its own when
the window opens it (shell.qml's closer look)."""

import os
import re
import stat
import time

FOLD_KIND = "o"        # a folder's smaller items, folded into one entry
MAX_ROWS = 80          # entries a folder keeps after prune(), the rest folded


def unescape(s):
    """mountinfo writes a space as \\040"""
    return re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), s)


def mounts():
    """{mount point: (source, fstype)} from /proc/self/mountinfo"""
    found = {}
    try:
        with open("/proc/self/mountinfo") as f:
            for line in f:
                left, _, right = line.partition(" - ")
                fields, rest = left.split(), right.split()
                if len(fields) >= 5 and len(rest) >= 2:
                    found[unescape(fields[4])] = (rest[1], rest[0])
    except OSError:
        pass
    return found


def mount_of(path, table):
    """The mount point path is under"""
    p = path
    while p not in table and p != "/":
        p = os.path.dirname(p)
    return p


def disk(path):
    """The size and free space of the disk path is on, in bytes"""
    try:
        v = os.statvfs(path)
    except OSError:
        return {"size": 0, "free": 0, "used": 0}
    size, free = v.f_blocks * v.f_frsize, v.f_bavail * v.f_frsize
    return {"size": size, "free": free, "used": (v.f_blocks - v.f_bfree) * v.f_frsize}


def du_self(path):
    """The blocks of a folder itself, without what it holds"""
    try:
        return os.lstat(path).st_blocks * 512
    except OSError:
        return 0


def du(path):
    """The space a file or folder takes (no tree), 0 if it isn't there; never through a link"""
    try:
        st = os.lstat(path)
    except OSError:
        return 0
    total = st.st_blocks * 512
    if not stat.S_ISDIR(st.st_mode):
        return total
    stack = [path]
    while stack:
        try:
            it = os.scandir(stack.pop())
        except OSError:
            continue
        with it:
            for e in it:
                try:
                    s = e.stat(follow_symlinks=False)
                except OSError:
                    continue
                total += s.st_blocks * 512
                if stat.S_ISDIR(s.st_mode) and s.st_dev == st.st_dev:
                    stack.append(e.path)
    return total


class Scan:
    """One walk: run() gives the tree, {n name, s bytes, k kind (d folder, f file, o smaller items), i files inside,
    c entries (biggest first), u 1 if some of it couldn't be read}. progress(files, bytes, folder) is called about ten
    times a second."""

    def __init__(self, root, keep, progress=None):
        self.root = os.path.realpath(root)
        self.keep = keep
        self.progress = progress
        self.table = mounts()
        self.source = self.table.get(mount_of(self.root, self.table), (None, None))[0]
        self.seen = set()          # (dev, inode) of hard-linked files counted already
        self.files = 0
        self.bytes = 0
        self.unreadable = 0        # folders that couldn't be read (another user's, the system's)
        self.others = []           # other disks mounted inside, left out
        self.next_report = 0.0

    def other_disk(self, path):
        """A mount point inside, of another disk or of a virtual one (/proc, /run): left out. Btrfs's subvolumes have a
        device number of their own but the same source (Fedora's /home under /), so they stay in."""
        m = self.table.get(path)
        return m is not None and m[0] != self.source

    def report(self, path):
        now = time.monotonic()
        if now >= self.next_report:
            self.next_report = now + 0.1
            self.progress(self.files, self.bytes, path)

    def run(self):
        st = os.stat(self.root)
        node = self.walk(self.root, os.path.basename(self.root) or "/", st)
        return node

    def walk(self, path, name, st):
        node = {"n": name, "k": "d", "s": st.st_blocks * 512, "i": 0}
        kids, small_s, small_n = [], 0, 0
        try:
            it = os.scandir(path)
        except OSError:
            self.unreadable += 1
            node["u"] = 1
            return node
        with it:
            for e in it:
                try:
                    s = e.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISDIR(s.st_mode):
                    if s.st_dev != st.st_dev and self.other_disk(e.path):
                        self.others.append(e.path)
                        continue
                    child = self.walk(e.path, e.name, s)
                    if child.get("u"):
                        node["u"] = 1
                    node["i"] += child["i"]
                    size = child["s"]
                else:
                    size = s.st_blocks * 512
                    if s.st_nlink > 1 and not stat.S_ISLNK(s.st_mode):
                        key = (s.st_dev, s.st_ino)
                        if key in self.seen:
                            size = 0
                        else:
                            self.seen.add(key)
                    node["i"] += 1
                    self.files += 1
                    self.bytes += size
                    child = None
                    if self.progress and not self.files & 511:
                        self.report(path)
                node["s"] += size
                if size >= self.keep:
                    kids.append(child or {"n": e.name, "k": "f", "s": size})
                else:
                    small_s += size
                    small_n += 1
        if small_n:
            kids.append({"n": "", "k": FOLD_KIND, "s": small_s, "i": small_n})
        if kids:
            kids.sort(key=lambda k: -k["s"])
            node["c"] = kids
        return node


def prune(node, least):
    """Entries smaller than least bytes, and those past MAX_ROWS, fold into their folder's smaller items"""
    kids = node.get("c")
    if not kids:
        return node
    keep, fold = [], None
    for k in kids:
        if k["k"] == FOLD_KIND:
            fold = fold or {"n": "", "k": FOLD_KIND, "s": 0, "i": 0}
            fold["s"] += k["s"]
            fold["i"] += k["i"]
        elif k["s"] >= least and len(keep) < MAX_ROWS:
            keep.append(prune(k, least))
        else:
            fold = fold or {"n": "", "k": FOLD_KIND, "s": 0, "i": 0}
            fold["s"] += k["s"]
            fold["i"] += 1
    if fold:
        keep.append(fold)
    keep.sort(key=lambda k: -k["s"])
    node["c"] = keep
    return node
