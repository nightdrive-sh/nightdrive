#!/usr/bin/env python3
"""clean.py: Clean up empties only its named folders' contents, never the folders themselves, never through a link,
never anything beside them in ~/.cache, and never a folder that holds home."""

import os
import sys
import tempfile
import unittest

# A home of its own before clean.py reads it (CI gives one too; by hand the real one must stay out of reach)
TMP = tempfile.TemporaryDirectory()
HOME = os.path.realpath(TMP.name)
os.environ.update(HOME=HOME, XDG_CACHE_HOME=HOME + "/.cache", XDG_DATA_HOME=HOME + "/.local/share")

# CI runs the tests with python3 -I, which leaves the script's own folder off the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import clean  # noqa: E402

CACHE = HOME + "/.cache"


def write(path, n=4096):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"x" * n)


def kinds(**globs):
    """The KINDS with only these globs: the real ones reach other disks' trash (/run/media, /mnt)"""
    return [(i, i.title(), "x", "x", g) for i, g in globs.items()]


class Clean(unittest.TestCase):
    def setUp(self):
        self.saved = clean.KINDS
        self.which = clean.shutil.which
        clean.shutil.which = lambda name: None      # never the real `gio trash --empty`
        for root in (CACHE, HOME + "/.local", HOME + "/Documents"):
            clean.shutil.rmtree(root, ignore_errors=True)

    def tearDown(self):
        clean.KINDS = self.saved
        clean.shutil.which = self.which

    def test_named_kinds_only(self):
        """Every kind's every glob is in home's caches, its trash or another disk's trash: none is home or ~/.cache"""
        for kind in self.saved:
            for g in kind[4]:
                self.assertNotIn(g.rstrip("/"), (HOME, CACHE, HOME + "/.local/share"), kind[0])
                self.assertTrue(g.startswith((CACHE + "/", HOME + "/.local/share/Trash/", HOME + "/.var/app/",
                                              HOME + "/.npm/", HOME + "/.cargo/", "/run/media/", "/media/", "/mnt/")),
                                g)

    def test_empties_contents_keeps_folder_and_neighbours(self):
        write(f"{CACHE}/thumbnails/large/a.png")
        write(f"{CACHE}/thumbnails/normal/b.png")
        write(f"{CACHE}/spotify/offline.bnk")              # beside it: not a kind's
        write(f"{CACHE}/nightdrive/theme.json")
        clean.KINDS = kinds(thumbnails=[CACHE + "/thumbnails"])
        r = clean.run({"thumbnails"})
        self.assertEqual(os.listdir(CACHE + "/thumbnails"), [])
        self.assertTrue(os.path.isfile(f"{CACHE}/spotify/offline.bnk"))
        self.assertTrue(os.path.isfile(f"{CACHE}/nightdrive/theme.json"))
        self.assertGreater(r["freed"], 0)
        self.assertEqual(r["failed"], [])

    def test_link_inside_goes_as_link(self):
        write(f"{HOME}/Documents/keep.txt")
        os.makedirs(CACHE + "/pip")
        os.symlink(HOME + "/Documents", CACHE + "/pip/docs")
        os.symlink(HOME + "/Documents/keep.txt", CACHE + "/pip/file")
        clean.KINDS = kinds(packages=[CACHE + "/pip"])
        clean.run({"packages"})
        self.assertEqual(os.listdir(CACHE + "/pip"), [])
        self.assertTrue(os.path.isfile(f"{HOME}/Documents/keep.txt"))

    def test_folder_that_is_a_link_left_alone(self):
        write(f"{HOME}/Documents/mine.bin")
        os.makedirs(CACHE)
        os.symlink(HOME + "/Documents", CACHE + "/pip")
        clean.KINDS = kinds(packages=[CACHE + "/pip"])
        self.assertEqual(clean.size(clean.KINDS[0]), 0)
        clean.run({"packages"})
        self.assertTrue(os.path.isfile(f"{HOME}/Documents/mine.bin"))

    def test_too_wide_never_emptied(self):
        """XDG_CACHE_HOME set to ~ or / would make a kind's folder home or what holds it"""
        write(f"{HOME}/Documents/mine.txt")
        clean.KINDS = kinds(wide=[HOME, HOME + "/", os.path.dirname(HOME), "/"])
        self.assertEqual(clean.folders(clean.KINDS[0][4]), [])
        clean.run({"wide"})
        self.assertTrue(os.path.isfile(f"{HOME}/Documents/mine.txt"))
        self.assertTrue(clean.too_wide(HOME))
        self.assertFalse(clean.too_wide(CACHE))

    def test_only_the_ids_asked(self):
        write(f"{CACHE}/thumbnails/a.png")
        write(f"{CACHE}/pip/wheel.whl")
        clean.KINDS = kinds(thumbnails=[CACHE + "/thumbnails"], packages=[CACHE + "/pip"])
        clean.run({"packages"})
        self.assertTrue(os.path.isfile(f"{CACHE}/thumbnails/a.png"))
        self.assertEqual(os.listdir(CACHE + "/pip"), [])

    def test_unknown_id_refused(self):
        clean.KINDS = kinds(thumbnails=[CACHE + "/thumbnails"])
        with open(os.devnull, "w") as null:
            err, sys.stderr = sys.stderr, null
            try:
                self.assertEqual(clean.main(["clean.py", "run", "thumbnails", "home"]), 2)
            finally:
                sys.stderr = err

    def test_glob_reaches_only_matches(self):
        write(f"{HOME}/.var/app/org.mozilla.firefox/cache/x")
        write(f"{HOME}/.var/app/org.mozilla.firefox/data/profile")     # the Flatpak's data, not its cache
        clean.KINDS = kinds(browsers=[f"{HOME}/.var/app/*/cache"])
        clean.run({"browsers"})
        self.assertEqual(os.listdir(f"{HOME}/.var/app/org.mozilla.firefox/cache"), [])
        self.assertTrue(os.path.isfile(f"{HOME}/.var/app/org.mozilla.firefox/data/profile"))


if __name__ == "__main__":
    try:
        unittest.main()
    finally:
        TMP.cleanup()
