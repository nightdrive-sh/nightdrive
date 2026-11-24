#!/usr/bin/env python3
"""Network Drives, saving offline: `python3 plugins/netdrive/lib/upload_test.py`. A file saved while the server doesn't
answer goes to the cache at once and is uploaded by itself once it answers again. The mount and its relay are
mounttest.py's."""
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mounttest import LIMIT, NEEDS, NEEDS_FUSE, Mounted, timed  # noqa: E402

UPLOAD_AGAIN = 60  # s: rclone tries a failed upload again on its own, waiting 2, 4, 8 … s between tries


@NEEDS
@NEEDS_FUSE
class Upload(Mounted):
    def test_back(self):
        """Saved while dark, uploaded once the network is back, without anyone doing anything"""
        self.online()
        self.relay.dark()
        self.check({"save": timed(f"echo offline > '{self.mnt}/later.txt'", LIMIT * 3)}, ["save"])
        time.sleep(2)
        self.assertFalse((self.served / "later.txt").exists())
        self.relay.is_dark = False
        self.wait(lambda: (self.served / "later.txt").exists(), UPLOAD_AGAIN, "the file saved offline wasn't uploaded")
        self.assertEqual((self.served / "later.txt").read_text(), "offline\n")


if __name__ == "__main__":
    unittest.main()
