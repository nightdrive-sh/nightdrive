#!/usr/bin/env python3
"""What counts as a note for Claude (#1864): `python3 plugins/notes/lib/store_test.py`. A hard link in ~/Notes is the
file it shares with another name, which may be ~/.ssh/id_ed25519: Claude's tools don't list, search or read it. Your
own use (the window, the `notes` command) is as before. A dangling symlink with a new note's name isn't followed (#1930).
The window's editor saves through `notes write`: whole, never over a save made elsewhere, never a text cut short (#2012)."""

import hashlib
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


class HardLink(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        home = Path(self.tmp.name)
        (home / ".ssh").mkdir()
        (home / ".ssh/id_ed25519").write_text("-----BEGIN OPENSSH PRIVATE KEY-----\n")
        self.notes = home / "Notes"
        self.notes.mkdir()
        (self.notes / "Shopping.md").write_text("milk\n")
        os.link(home / ".ssh/id_ed25519", self.notes / "key.md")

    def tearDown(self):
        self.tmp.cleanup()

    def notes_cmd(self, *args, claude=True):
        env = {k: v for k, v in os.environ.items() if not k.startswith("NIGHTDRIVE_MCP")}
        env["NOTES_DIR"] = str(self.notes)
        if claude:
            env["NIGHTDRIVE_MCP"] = "1"
        return subprocess.run([sys.executable, str(HERE / "notes.py"), *args], env=env, capture_output=True,
                              text=True, timeout=30)

    def test_claude_doesnt_get_it(self):
        for args in (("list", "--json"), ("search", "OPENSSH", "--json"), ("read", "key.md", "--json")):
            with self.subTest(args=args):
                out = self.notes_cmd(*args)
                self.assertNotIn("PRIVATE KEY", out.stdout)
                self.assertNotIn("key.md", out.stdout)
        self.assertIn("Shopping.md", self.notes_cmd("list", "--json").stdout)
        self.assertNotEqual(self.notes_cmd("read", "key.md").returncode, 0)

    def test_your_own_use(self):
        self.assertIn("key.md", self.notes_cmd("list", "--json", claude=False).stdout)


class DanglingLink(unittest.TestCase):
    """A new note's name taken by a symlink to a file not there yet: create writes beside it, not through it."""

    def test_create_doesnt_follow_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            notes = home / "Notes"
            notes.mkdir()
            target = home / ".bashrc"
            (notes / "Plan.md").symlink_to(target)
            env = dict(os.environ, NOTES_DIR=str(notes))
            out = subprocess.run([sys.executable, str(HERE / "notes.py"), "create", "Plan"], input="echo hi\n",
                                 env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(out.returncode, 0, out.stderr)
            self.assertFalse(target.exists())
            self.assertTrue((notes / "Plan.md").is_symlink())
            self.assertEqual((notes / "Plan 2.md").read_text(), "# Plan\n\necho hi\n")


class Write(unittest.TestCase):
    """The window's editor saves through notes write: whole, in one step, and never over a save made elsewhere."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.notes = Path(self.tmp.name) / "Notes"
        self.notes.mkdir()
        self.note = self.notes / "Plan.md"
        self.note.write_bytes(b"# Plan\r\n\r\nfirst\r\n")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, text, *args):
        env = dict(os.environ, NOTES_DIR=str(self.notes))
        return subprocess.run([sys.executable, str(HERE / "notes.py"), "write", "--json", *args, "Plan.md"],
                              input=text.encode(), env=env, capture_output=True, timeout=30)

    def md5(self, data):
        return hashlib.md5(data).hexdigest()

    def test_writes_it_as_sent(self):
        out = self.write("# Plan\r\n\r\nsecond\r\n", "--expect", self.md5(self.note.read_bytes()))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(self.note.read_bytes(), b"# Plan\r\n\r\nsecond\r\n")
        self.assertEqual([p.name for p in self.notes.iterdir()], ["Plan.md"])   # no temporary file left

    def test_not_over_a_save_elsewhere(self):
        expect = self.md5(self.note.read_bytes())
        self.note.write_text("# Plan\n\nApostrophe's\n")
        out = self.write("mine\n", "--expect", expect)
        self.assertEqual(out.returncode, 3)
        self.assertEqual(self.note.read_text(), "# Plan\n\nApostrophe's\n")

    def test_not_a_cut_text(self):
        # The window quit before its text reached stdin: an empty stdin must not empty the note
        out = self.write("", "--md5", self.md5(b"# Plan\r\n\r\nsecond\r\n"))
        self.assertEqual(out.returncode, 1)
        self.assertEqual(self.note.read_bytes(), b"# Plan\r\n\r\nfirst\r\n")

    def test_keeps_the_mode(self):
        self.note.chmod(0o600)
        self.write("x\n")
        self.assertEqual(self.note.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
