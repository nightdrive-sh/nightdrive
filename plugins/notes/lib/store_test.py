#!/usr/bin/env python3
"""What counts as a note for Claude (#1864): `python3 plugins/notes/lib/store_test.py`. A hard link in ~/Notes is the
file it shares with another name, which may be ~/.ssh/id_ed25519: Claude's tools don't list, search or read it. Your
own use (the window, the `notes` command) is as before. A dangling symlink with a new note's name isn't followed (#1930)."""

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


if __name__ == "__main__":
    unittest.main()
