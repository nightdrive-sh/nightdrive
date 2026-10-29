#!/usr/bin/env python3
"""Notes and Tasks as Claude's tools run them (#1863): `python3 config/mcp/notes_tasks_test.py`. In a home of its own:
notes_trash (and notes_create's undo) with the MCP server's environment, a title that would make a hidden file, and
notify-send getting a title that looks like its options (a stand-in in PATH keeps its argv)."""

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
NOTES = REPO / "plugins/notes/lib/notes.py"
HOSTILE = ["--app-name=Mail", "--urgency=critical", "--icon=/etc/passwd", "-a", "--version", "--help-all"]


class Home(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve()
        self.notes = self.home / "Notes"
        self.notes.mkdir()
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("XDG_DATA", "NIGHTDRIVE_"))}
        self.env.update(HOME=str(self.home), NOTES_DIR=str(self.notes), PATH=f"{self.bin}:{os.environ['PATH']}")

    def tearDown(self):
        self.tmp.cleanup()

    def mcp(self, options='{"secrets": false}'):
        """As run.environment gives a Notes tool: Notes' own choices, none from another area"""
        return {**self.env, "NIGHTDRIVE_MCP": "1", "NIGHTDRIVE_MCP_TOOL": "notes_trash",
                "NIGHTDRIVE_MCP_OPTIONS": options, "NIGHTDRIVE_MCP_OPTIONS_FROM": "{}"}

    def notes_py(self, *argv, env=None, stdin=""):
        return subprocess.run([sys.executable, str(NOTES), *argv], capture_output=True, text=True,
                              env=env or self.env, input=stdin)


class Notes(Home):
    def test_trash_from_claude(self):
        (self.notes / "Shopping.md").write_text("# Shopping\n")
        p = self.notes_py("trash", "--json", "Shopping.md", env=self.mcp())
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertFalse((self.notes / "Shopping.md").exists())
        self.assertTrue((self.home / ".local/share/Trash/files/Shopping.md").exists())

    def test_create_then_its_undo(self):
        p = self.notes_py("create", "--json", "Plan", env=self.mcp(), stdin="text")
        self.assertEqual(p.returncode, 0, p.stderr)
        made = json.loads(p.stdout)["id"]
        p = self.notes_py("trash", "--json", made, env=self.mcp('{}'))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(list(self.notes.iterdir()), [])

    def test_trash_still_keeps_to_notes(self):
        outside = self.home / "Documents"
        outside.mkdir()
        (outside / "secret.md").write_text("x")
        (self.notes / "link.md").symlink_to(outside / "secret.md")
        for who in ("../Documents/secret.md", "/etc/passwd", "link.md", ".hidden.md"):
            p = self.notes_py("trash", "--json", who, env=self.mcp())
            self.assertEqual(p.returncode, 1, who)
        self.assertTrue((outside / "secret.md").exists())

    def test_no_hidden_note_from_a_title(self):
        for title, name in (("../.bashrc", "bashrc.md"), (". .profile", "profile.md"), ("  ...", "Note.md"),
                            ("/.ssh/config", "ssh config.md"), ("\x1f.x", "x.md")):
            p = self.notes_py("create", "--json", title, env=self.mcp(), stdin="t")
            self.assertEqual(p.returncode, 0, p.stderr)
            made = json.loads(p.stdout)["id"]
            self.assertEqual(made, name, title)
            self.assertEqual(self.notes_py("trash", "--json", made, env=self.mcp()).returncode, 0, made)
        self.assertEqual([f for f in self.home.rglob(".*") if f.parent == self.notes], [])


class NotifySend(Home):
    """notify-send's argv, from a stand-in: a title is never one of its options"""

    def setUp(self):
        super().setUp()
        self.argv = self.home / "argv.json"
        f = self.bin / "notify-send"
        f.write_text(f"#!{sys.executable}\nimport json, sys\n"
                     f"open({str(self.argv)!r}, 'a').write(json.dumps(sys.argv[1:]) + '\\n')\n")
        f.chmod(f.stat().st_mode | stat.S_IEXEC)
        self.saved = os.environ.copy()
        os.environ.update(self.env)

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.saved)
        super().tearDown()

    def calls(self):
        return [json.loads(line) for line in self.argv.read_text().splitlines()]

    def assert_text_after_dashes(self, argv, *texts):
        self.assertIn("--", argv)
        cut = argv.index("--")
        self.assertEqual(argv[cut + 1:], list(texts))

    def test_tasks_due(self):
        sys.path.insert(0, str(REPO / "plugins/tasks/lib"))
        import due
        for title in HOSTILE:
            due.notify("t", title, title, [("done", "Done")])
        for title, argv in zip(HOSTILE, self.calls()):
            self.assert_text_after_dashes(argv, title, title)

    def test_undo_notice(self):
        sys.path.insert(0, str(HERE))
        import undo
        for title in HOSTILE:
            undo.notify(1, title, title)
        for title, argv in zip(HOSTILE, self.calls()):
            self.assert_text_after_dashes(argv, title, title)


if __name__ == "__main__":
    unittest.main()
