#!/usr/bin/env python3
"""Files' sidebar: `python3 plugins/files/lib/places_test.py`. Home's folders come from user-dirs.dirs (one set to home
is left out), GTK's bookmarks are read with their names, and adding or removing one keeps the other lines as they are;
Files' own first group (pinned.py) starts with home, and folders move within and between the groups."""

import os
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import places  # noqa: E402


class Places(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve()
        self.old = {k: os.environ.get(k) for k in ("HOME", "XDG_CONFIG_HOME")}
        os.environ["HOME"] = str(self.home)
        os.environ.pop("XDG_CONFIG_HOME", None)
        (self.home / ".config/gtk-3.0").mkdir(parents=True)
        for d in ("Lataukset", "Pictures", "Work dir"):
            (self.home / d).mkdir()

    def tearDown(self):
        for k, v in self.old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def test_user_dirs(self):
        (self.home / ".config/user-dirs.dirs").write_text(
            'XDG_DOWNLOAD_DIR="$HOME/Lataukset"\nXDG_DESKTOP_DIR="$HOME/"\n')
        rows = places.standard()
        self.assertEqual(rows[0], {"name": "Home", "path": str(self.home), "glyph": "house"})
        self.assertEqual([r["name"] for r in rows[1:]], ["Lataukset", "Pictures"])

    def test_bookmarks_read_and_written(self):
        f = self.home / ".config/gtk-3.0/bookmarks"
        f.write_text(f"file://{self.home}/Work%20dir Work\nsftp://server/x Server\nfile:///gone\n")
        rows = places.bookmarks()
        self.assertEqual(rows[0], {"name": "Work", "path": str(self.home / "Work dir"), "missing": False})
        self.assertTrue(rows[1]["missing"])
        self.assertEqual(len(rows), 2)
        places.bookmark(self.home / "Pictures", True)
        self.assertTrue(f.read_text().endswith(f"file://{self.home}/Pictures\n"))
        places.bookmark(self.home / "Work dir", False)
        self.assertEqual(f.read_text(), f"sftp://server/x Server\nfile:///gone\nfile://{self.home}/Pictures\n")

    def test_own_group_starts_with_home_and_moves(self):
        import pinned
        f = self.home / ".config/gtk-3.0/bookmarks"
        f.write_text(f"file://{self.home}/Work%20dir Work\nsftp://server/x Server\n")
        home, pics, work = str(self.home), str(self.home / "Pictures"), str(self.home / "Work dir")
        self.assertEqual(pinned.paths()[0], home)
        self.assertEqual(pinned.rows()[0]["name"], "Home")
        # A bookmark up into the first group, before Pictures: out of GTK's file, the other lines kept
        pinned.move(work, "places", pics)
        self.assertEqual(pinned.paths()[pinned.paths().index(pics) - 1], work)
        self.assertEqual(f.read_text(), "sftp://server/x Server\n")
        # And back down, before nothing: at the end of the bookmarks
        pinned.move(work, "bookmarks")
        self.assertNotIn(work, pinned.paths())
        self.assertTrue(f.read_text().endswith(f"file://{self.home}/Work%20dir\n"))
        # Home out of the group, and a bookmark ahead of another, its name kept
        pinned.remove(home)
        self.assertNotIn(home, pinned.paths())
        f.write_text(f"file://{pics}\nfile://{self.home}/Work%20dir Work\n")
        places.bookmark_at(work, pics)
        self.assertEqual(f.read_text(), f"file://{self.home}/Work%20dir Work\nfile://{pics}\n")


if __name__ == "__main__":
    unittest.main()
