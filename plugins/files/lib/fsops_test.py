#!/usr/bin/env python3
"""Files' changes and their undo: `python3 plugins/files/lib/fsops_test.py`. A copy or move never writes over a name
(" (2)" instead), a folder can't go into itself, a rename to a taken name is refused, each change's undo (cli.py's
"undo") takes it back, and a copy stopped midway leaves no half-written file."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import fsops  # noqa: E402


class Names(unittest.TestCase):
    def test_numbered(self):
        self.assertEqual(fsops.numbered("photo.jpg", 2), "photo (2).jpg")
        self.assertEqual(fsops.numbered("backup.tar.gz", 3), "backup (3).tar.gz")
        self.assertEqual(fsops.numbered("my.folder", 2, is_dir=True), "my.folder (2)")
        self.assertEqual(fsops.numbered(".bashrc", 2), ".bashrc (2)")
        self.assertEqual(fsops.numbered("a.txt", 1), "a.txt")

    def test_valid_name(self):
        for bad in ("", " ", ".", "..", "a/b"):
            with self.assertRaises(fsops.Refused):
                fsops.valid_name(bad)
        self.assertEqual(fsops.valid_name(" x.txt "), "x.txt")


class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("XDG_")}
        self.env["HOME"] = str(self.home)
        self.a, self.b = self.home / "a", self.home / "b"
        self.a.mkdir(); self.b.mkdir()
        (self.a / "note.txt").write_text("hello")
        (self.a / "sub").mkdir()
        (self.a / "sub" / "deep.txt").write_text("deep")

    def tearDown(self):
        self.tmp.cleanup()

    def cli(self, *argv, ok=True):
        r = subprocess.run([sys.executable, "-I", str(HERE / "cli.py"), *map(str, argv)], capture_output=True,
                           text=True, env=self.env)
        if ok:
            self.assertEqual(r.returncode, 0, r.stderr)
            return json.loads(r.stdout.strip().splitlines()[-1])
        self.assertNotEqual(r.returncode, 0)
        return r.stderr.strip()

    def test_copy_numbers_a_taken_name_and_undo_trashes_the_copies(self):
        d = self.cli("copy", "--into", self.a, self.a / "note.txt", self.a / "sub")
        self.assertEqual(d["made"], [str(self.a / "note (2).txt"), str(self.a / "sub (2)")])
        self.assertEqual((self.a / "sub (2)" / "deep.txt").read_text(), "deep")
        self.assertEqual(d["undo"][:2], ["trash", "--"])
        self.cli(*d["undo"])
        self.assertFalse((self.a / "note (2).txt").exists())
        self.assertTrue((self.a / "note.txt").exists())

    def test_move_and_move_back(self):
        d = self.cli("move", "--into", self.b, self.a / "note.txt", self.a / "sub")
        self.assertTrue((self.b / "sub" / "deep.txt").exists())
        self.assertFalse((self.a / "note.txt").exists())
        self.cli(*d["undo"])
        self.assertEqual((self.a / "note.txt").read_text(), "hello")
        self.assertTrue((self.a / "sub" / "deep.txt").exists())
        self.assertEqual(list(self.b.iterdir()), [])

    def test_move_where_it_is_does_nothing(self):
        d = self.cli("move", "--into", self.a, self.a / "note.txt")
        self.assertEqual(d["moved"], [])
        self.assertTrue((self.a / "note.txt").exists())

    def test_folder_into_itself_is_refused(self):
        why = self.cli("move", "--into", self.a / "sub", self.a, ok=False)
        self.assertIn("into itself", why)
        why = self.cli("copy", "--into", self.a, self.a, ok=False)
        self.assertIn("into itself", why)

    def test_rename_refuses_a_taken_name_and_undoes(self):
        (self.a / "other.txt").write_text("x")
        self.assertIn("already", self.cli("rename", self.a / "note.txt", "other.txt", ok=False))
        d = self.cli("rename", self.a / "note.txt", "renamed.txt")
        self.assertTrue((self.a / "renamed.txt").exists())
        self.cli(*d["undo"])
        self.assertTrue((self.a / "note.txt").exists())
        self.assertFalse((self.a / "renamed.txt").exists())

    def test_move_back_leaves_what_has_moved_on(self):
        d = self.cli("rename", self.a / "note.txt", "renamed.txt")
        (self.a / "note.txt").write_text("new one in its place")
        back = self.cli(*d["undo"])
        self.assertEqual(back["left"], ["renamed.txt"])
        self.assertEqual((self.a / "note.txt").read_text(), "new one in its place")

    def test_new_file_and_folder(self):
        d = self.cli("new", self.b, "empty.txt")
        self.assertEqual((self.b / "empty.txt").read_text(), "")
        self.cli("new", self.b, "Folder", "--dir")
        self.assertTrue((self.b / "Folder").is_dir())
        self.assertIn("already", self.cli("new", self.b, "Folder", "--dir", ok=False))
        self.cli(*d["undo"])
        self.assertFalse((self.b / "empty.txt").exists())

    def test_links_are_copied_as_links(self):
        os.symlink("note.txt", self.a / "link")
        self.cli("copy", "--into", self.b, self.a / "link")
        self.assertEqual(os.readlink(self.b / "link"), "note.txt")


class Stop(unittest.TestCase):
    def test_a_stopped_copy_leaves_no_part(self):
        with tempfile.TemporaryDirectory() as t:
            t = Path(t)
            (t / "src").mkdir(); (t / "dst").mkdir()
            (t / "src" / "big").write_bytes(b"x" * (3 * fsops.CHUNK))
            (t / "src" / "small").write_bytes(b"y")
            # Stopped as the first chunk is written: the file under way goes, nothing is reported made
            fsops._stop = False
            calls = []

            def report(done, total, name):
                calls.append(done)
                fsops._stop = True
            old = fsops.TICK
            fsops.TICK = 0
            try:
                d = fsops.copy([t / "src" / "big"], t / "dst", report)
            finally:
                fsops.TICK, fsops._stop = old, False
            self.assertTrue(d["stopped"])
            self.assertEqual(d["made"], [])
            self.assertEqual(list((t / "dst").iterdir()), [])


if __name__ == "__main__":
    unittest.main()
