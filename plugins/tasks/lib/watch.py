#!/usr/bin/env python3
"""Prints a line each time the tasks' folder changes, for the Tasks window to read its lists again (app/shell.qml).

A sync (`nightdrive hub sync`), Claude's tools and `tasks` in a terminal all write the vdir behind the window's back;
before this, the window saw their changes only on its once-a-minute read. inotify through ctypes, as Fedora has no
inotify-tools by default and the window shouldn't need a package for this.

- The whole tree: the folder itself (lists made or removed) and each list's folder (tasks written, which store.write
  does as a rename of a hidden temporary). A list made later is watched from then on.
- A burst (a sync writing fifty tasks) is one line, printed once the folder has been quiet for QUIET seconds.
- The folder not there yet (no task ever added): its parent is watched until it is made.
- It ends with the window: the kernel sends it SIGTERM when its parent dies (PR_SET_PDEATHSIG), and a closed stdout
  ends it on the next print.
"""
import ctypes
import ctypes.util
import os
import select
import signal
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))     # also under python3 -I, which leaves it out
import store  # noqa: E402

QUIET = 0.3     # seconds without events before a burst is reported
# IN_CLOSE_WRITE, IN_ATTRIB, IN_MOVED_FROM, IN_MOVED_TO, IN_CREATE, IN_DELETE, IN_DELETE_SELF, IN_MOVE_SELF
MASK = 0x8 | 0x4 | 0x40 | 0x80 | 0x100 | 0x200 | 0x400 | 0x800
IN_ISDIR = 0x40000000
IN_IGNORED = 0x8000
EVENT = struct.Struct("iIII")       # wd, mask, cookie, len; then the name, len bytes
PR_SET_PDEATHSIG = 1

libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)


class Watcher:
    def __init__(self, root):
        self.root = str(root)
        self.fd = libc.inotify_init1(os.O_CLOEXEC)
        if self.fd < 0:
            raise OSError(ctypes.get_errno(), "inotify_init1")
        self.dirs = {}      # wd: path
        self.toward = None  # while there is no root: the name in the watched folder that leads to it

    def add(self, path):
        wd = libc.inotify_add_watch(self.fd, os.fsencode(path), MASK)
        if wd >= 0:
            self.dirs[wd] = path
        return wd >= 0

    def setup(self):
        """Watches the root and its lists, or, while there is no root, the nearest folder above it that exists.
        Watches are only added: one on a folder already watched stays as it is, and the kernel takes one away itself
        when its folder goes (IN_IGNORED). Taking them all away and adding them again would queue an IN_IGNORED for
        each, which would come back here as a change, and again, without end."""
        if os.path.isdir(self.root):
            for wd, path in list(self.dirs.items()):
                if path != self.root and not path.startswith(self.root + os.sep):
                    libc.inotify_rm_watch(self.fd, wd)      # the folder above, watched while there was no root
                    del self.dirs[wd]
            self.add(self.root)
            for name in os.listdir(self.root):
                p = os.path.join(self.root, name)
                if os.path.isdir(p) and not name.startswith("."):
                    self.add(p)
            return True
        up = os.path.dirname(self.root)
        while up != "/" and not os.path.isdir(up):
            up = os.path.dirname(up)
        self.add(up)
        self.toward = os.path.relpath(self.root, up).split(os.sep)[0]
        return False

    def events(self, timeout):
        """[(path, name, mask)] read within timeout seconds; [] when none came."""
        r, _, _ = select.select([self.fd], [], [], timeout)
        if not r:
            return []
        data = os.read(self.fd, 64 * 1024)
        out, i = [], 0
        while i < len(data):
            wd, mask, _, n = EVENT.unpack_from(data, i)
            name = data[i + EVENT.size:i + EVENT.size + n].rstrip(b"\0").decode("utf-8", "replace")
            i += EVENT.size + n
            out.append((self.dirs.get(wd), name, mask))
            if mask & IN_IGNORED:
                self.dirs.pop(wd, None)     # its folder is gone, or the watch was taken away
        return out


def relevant(name):
    """A change the window would show: not Tasks' own hidden temporary (`.x.ics.tmp`) or a sync's (`.x.hub-tmp`),
    whose rename into place is the event that counts."""
    return not name.startswith(".")


def main():
    libc.prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    w = Watcher(store.DATA)
    whole = w.setup()
    pending = False
    while True:
        evs = w.events(QUIET if pending else None)
        if not evs:
            if pending:
                print("changed", flush=True)    # BrokenPipeError when the window has gone: the end
                pending = False
            continue
        rescan = False
        for path, name, mask in evs:
            if not whole:
                # Only the folder on the way to the root counts: ~/.local/share sees plenty of other writes
                rescan = rescan or name == w.toward
                continue
            if mask & IN_IGNORED:
                continue
            if mask & IN_ISDIR or path == w.root and not name:
                rescan = True       # a list made or removed, the root moved: watch the tree as it is now
            if relevant(name):
                pending = True
        if rescan:
            was = whole
            whole = w.setup()
            pending = pending or (whole and not was)


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        sys.exit(0)
