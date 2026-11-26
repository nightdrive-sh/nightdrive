#!/usr/bin/env python3
"""walk.py: sizes as du counts them (blocks, a hard link once, never through a link), folding and pruning."""

import os
import sys
import tempfile
import unittest

# CI runs the tests with python3 -I, which leaves the script's own folder off the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import walk  # noqa: E402


def write(path, n):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(os.urandom(n))     # random, so a compressing file system can't make it smaller


def blocks(path):
    return os.lstat(path).st_blocks * 512


class Walk(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = self.dir.name

    def tearDown(self):
        self.dir.cleanup()

    def scan(self, keep=0):
        return walk.Scan(self.root, keep).run()

    def kid(self, node, name):
        return next(k for k in node.get("c", []) if k["n"] == name)

    def test_sizes_add_up_as_blocks(self):
        write(f"{self.root}/a/big", 200_000)
        write(f"{self.root}/a/small", 5_000)
        write(f"{self.root}/top", 50_000)
        tree = self.scan()
        files = [f"{self.root}/a/big", f"{self.root}/a/small", f"{self.root}/top"]
        folders = [self.root, f"{self.root}/a"]
        self.assertEqual(tree["s"], sum(map(blocks, files + folders)))
        self.assertEqual(tree["i"], 3)
        self.assertEqual([k["n"] for k in tree["c"]], ["a", "top"])   # biggest first
        self.assertEqual(self.kid(tree, "a")["k"], "d")

    def test_hard_link_counts_once(self):
        write(f"{self.root}/one", 100_000)
        os.link(f"{self.root}/one", f"{self.root}/two")
        s = walk.Scan(self.root, 0)
        s.run()
        self.assertEqual(s.bytes, blocks(f"{self.root}/one"))
        self.assertEqual(s.files, 2)

    def test_symlink_not_followed(self):
        with tempfile.TemporaryDirectory() as outside:
            write(f"{outside}/huge", 500_000)
            os.symlink(outside, f"{self.root}/link")
            tree = self.scan()
            self.assertLess(tree["s"], 100_000)
            self.assertEqual(walk.du(f"{self.root}/link"), blocks(f"{self.root}/link"))

    def test_small_entries_fold(self):
        write(f"{self.root}/big", 300_000)
        for i in range(5):
            write(f"{self.root}/s{i}", 1_000)
        tree = self.scan(keep=100_000)
        fold = [k for k in tree["c"] if k["k"] == walk.FOLD_KIND]
        self.assertEqual(len(fold), 1)
        self.assertEqual(fold[0]["i"], 5)
        self.assertEqual(self.kid(tree, "big")["k"], "f")

    def test_unreadable_folder_marked(self):
        if os.geteuid() == 0:
            self.skipTest("root reads every folder")
        os.makedirs(f"{self.root}/locked")
        os.chmod(f"{self.root}/locked", 0)
        try:
            s = walk.Scan(self.root, 0)
            tree = s.run()
            self.assertEqual(s.unreadable, 1)
            self.assertEqual(tree.get("u"), 1)
        finally:
            os.chmod(f"{self.root}/locked", 0o700)

    def test_du_matches_scan(self):
        write(f"{self.root}/x/y/z", 70_000)
        self.assertEqual(walk.du(self.root), self.scan()["s"])
        self.assertEqual(walk.du(f"{self.root}/missing"), 0)


class Prune(unittest.TestCase):
    def test_small_and_past_max_rows_fold(self):
        kids = [{"n": f"f{i}", "k": "f", "s": 1000 - i} for i in range(walk.MAX_ROWS + 10)]
        kids.append({"n": "tiny", "k": "f", "s": 5})
        kids.append({"n": "", "k": walk.FOLD_KIND, "s": 7, "i": 3})
        node = walk.prune({"n": "r", "k": "d", "s": 0, "c": kids}, least=10)
        folds = [k for k in node["c"] if k["k"] == walk.FOLD_KIND]
        self.assertEqual(len(folds), 1)
        fold = folds[0]
        self.assertEqual(fold["i"], 10 + 1 + 3)              # past MAX_ROWS, the tiny one, the old fold's
        self.assertEqual(len(node["c"]), walk.MAX_ROWS + 1)
        self.assertEqual(sum(k["s"] for k in node["c"]), sum(k["s"] for k in kids))


class Mounts(unittest.TestCase):
    def test_unescape(self):
        self.assertEqual(walk.unescape(r"/run/media/me/My\040Disk"), "/run/media/me/My Disk")

    def test_mount_of(self):
        table = {"/": ("a", "btrfs"), "/home": ("a", "btrfs"), "/mnt/usb": ("b", "vfat")}
        self.assertEqual(walk.mount_of("/mnt/usb/photos/2026", table), "/mnt/usb")
        self.assertEqual(walk.mount_of("/etc", table), "/")

    def test_other_disk(self):
        s = walk.Scan("/", 0)
        s.table, s.source = {"/": ("a", "btrfs"), "/home": ("a", "btrfs"), "/proc": ("proc", "proc")}, "a"
        self.assertFalse(s.other_disk("/home"))     # a subvolume of the same disk stays in
        self.assertTrue(s.other_disk("/proc"))
        self.assertFalse(s.other_disk("/usr"))


if __name__ == "__main__":
    unittest.main()
