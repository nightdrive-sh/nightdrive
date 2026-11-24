#!/usr/bin/env python3
"""Network Drives without a network: `python3 plugins/netdrive/lib/offline_test.py`. No program may hang on the folder
once the server stops answering (mountcmd.py's docstring says how): every call must come back, done or failed, within
LIMIT seconds (READ_LIMIT for a file that has to be downloaded first), and what is in the cache must keep working.
The mount and its relay are mounttest.py's."""
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mounttest import LIMIT, NEEDS, NEEDS_FUSE, READ_LIMIT, Mounted, timed  # noqa: E402

WORKS_OFFLINE = ["df", "read cached", "save", "list", "stat"]


@NEEDS
@NEEDS_FUSE
class Offline(Mounted):
    def test_dark(self):
        """The network goes dark under a mounted drive: what is cached works, the rest fails in time"""
        self.online()
        self.relay.dark()
        self.check(self.calls(cap=READ_LIMIT * 2), WORKS_OFFLINE)
        time.sleep(4)                         # past DIR_CACHE: a listing now has to ask the server
        self.check({"list again": timed(f"ls '{self.mnt}'", LIMIT * 3)}, [])

    def test_refused(self):
        """No network at all: the same, and no worse"""
        self.online()
        self.relay.refuse()
        self.relay.cut()
        self.check(self.calls(cap=READ_LIMIT * 2), WORKS_OFFLINE)


if __name__ == "__main__":
    unittest.main()
