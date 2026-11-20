#!/usr/bin/env python3
"""Files' trash: `python3 plugins/files/lib/trash_test.py`. A trashed file is where the freedesktop.org spec puts it
(Trash/files and an info file with its path and date), two of one name don't collide, restore puts each back (beside
a newcomer in its place, as " (2)"), the listing says where each came from, and emptying removes it for good."""

import os
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import trash  # noqa: E402


class Trash(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve()
        os.environ["XDG_DATA_HOME"] = str(self.home / "data")
        self.docs = self.home / "Documents"
        self.docs.mkdir()

    def tearDown(self):
        del os.environ["XDG_DATA_HOME"]
        self.tmp.cleanup()

    def test_spec_layout_and_restore(self):
        f = self.docs / "plan b.txt"
        f.write_text("x")
        d = trash.trash([f])
        info = Path(d["trashed"][0])
        self.assertEqual(info, self.home / "data/Trash/info/plan b.txt.trashinfo")
        text = info.read_text()
        self.assertIn(f"Path={self.docs}/plan%20b.txt", text)
        self.assertIn("DeletionDate=", text)
        self.assertTrue((self.home / "data/Trash/files/plan b.txt").exists())
        self.assertFalse(f.exists())
        r = trash.restore(d["trashed"])
        self.assertEqual(r["restored"], [str(f)])
        self.assertTrue(f.exists())
        self.assertFalse(info.exists())

    def test_same_name_twice(self):
        ids = []
        for text in ("one", "two"):
            f = self.docs / "a.txt"
            f.write_text(text)
            ids += trash.trash([f])["trashed"]
        self.assertEqual([Path(i).name for i in ids], ["a.txt.trashinfo", "a (2).txt.trashinfo"])
        rows = trash.listing()
        self.assertEqual(sorted(r["name"] for r in rows), ["a.txt", "a.txt"])
        self.assertEqual({r["origin"] for r in rows}, {str(self.docs / "a.txt")})

    def test_restore_beside_a_newcomer(self):
        f = self.docs / "a.txt"
        f.write_text("old")
        d = trash.trash([f])
        f.write_text("new")
        r = trash.restore(d["trashed"])
        self.assertEqual(r["restored"], [str(self.docs / "a (2).txt")])
        self.assertEqual(f.read_text(), "new")

    def test_folder_and_delete_and_empty(self):
        (self.docs / "sub").mkdir()
        (self.docs / "sub" / "x").write_text("x")
        (self.docs / "b").write_text("b")
        d = trash.trash([self.docs / "sub", self.docs / "b"])
        self.assertEqual(trash.count(), 2)
        self.assertTrue(next(r for r in trash.listing() if r["name"] == "sub")["dir"])
        trash.delete(d["trashed"][:1])
        self.assertEqual(trash.count(), 1)
        trash.empty()
        self.assertEqual(trash.count(), 0)
        self.assertEqual(list((self.home / "data/Trash/files").iterdir()), [])

    def test_relative_path_of_a_disks_trash(self):
        top = self.home / "stick"
        (top / ".Trash-1000/info").mkdir(parents=True)
        info = top / ".Trash-1000/info/x.trashinfo"
        info.write_text("[Trash Info]\nPath=photos/x\nDeletionDate=2026-11-20T10:00:00\n")
        self.assertEqual(trash.read_info(info), (str(top / "photos/x"), "2026-11-20T10:00:00"))


if __name__ == "__main__":
    unittest.main()
