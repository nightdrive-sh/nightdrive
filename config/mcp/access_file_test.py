#!/usr/bin/env python3
"""Settings › Claude › Access's file once the server is installed (#1885): `python3 config/mcp/access_file_test.py`.
`nightdrive mcp install` writes the file at Normal when there is none, so afterwards a missing file is one taken away
(a sync, a clean-up, a command) and gives Strict, as a broken one does; before any install it is still Normal. Runs
against files of its own, with Claude Code's `claude mcp` left out."""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import access  # noqa: E402
import register  # noqa: E402


class Missing(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.file, self.state = root / "claude-access.json", root / "mcp-install.json"
        self.patches = [mock.patch.object(access, "FILE", self.file),
                        mock.patch.object(access, "INSTALL_STATE", self.state)]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def installed(self, text):
        self.state.write_text(text)

    def test_before_any_install_normal(self):
        now = access.load()
        self.assertEqual((now.level, now.problem), ("normal", None))

    def test_after_install_strict_and_why(self):
        for note in ('{"server": {"command": "/x/nightdrive", "args": ["mcp"]}}', '{"rule": true}'):
            self.installed(note)
            now = access.load()
            self.assertEqual(now.level, "strict")
            self.assertIn("is missing: Strict until you choose a level", now.problem)
            self.assertEqual(access.load().summary()["level"], "strict")

    def test_a_note_that_cant_be_read_counts_as_installed(self):
        for note in ("{", "[]", '"x"'):
            self.installed(note)
            self.assertEqual(access.load().level, "strict", note)

    def test_removed_again_is_normal(self):
        self.installed("{}")   # remove leaves the note without what it took away
        self.assertEqual(access.load().level, "normal")

    def test_another_path_isnt_the_installs(self):
        self.installed('{"server": {}, "rule": true}')
        self.assertEqual(access.load(self.file.with_name("other.json")).level, "normal")

    def test_a_file_that_is_there_wins(self):
        self.installed('{"rule": true}')
        self.file.write_text(json.dumps({"version": 2, "level": "open"}))
        self.assertEqual(access.load().level, "open")
        for bad in ("", "null", "{", '{"level": "everything"}'):
            self.file.write_text(bad)
            self.assertEqual(access.load().level, "strict", bad)
        self.file.unlink()
        self.file.mkdir()   # a folder in its place can't be read either
        self.assertEqual(access.load().level, "strict")


class Install(unittest.TestCase):
    """install writes the file at Normal when there is none, and leaves one that is there as it is."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / ".claude").mkdir()
        self.file = root / "claude-access.json"
        self.calls = []
        self.patches = [
            mock.patch.object(access, "FILE", self.file),
            mock.patch.object(access, "INSTALL_STATE", root / "mcp-install.json"),
            mock.patch.object(register, "STATE", root / "mcp-install.json"),
            mock.patch.object(register, "SETTINGS", root / ".claude/settings.json"),
            mock.patch.object(register, "claude", lambda: "/x/claude"),
            mock.patch.object(register, "registered", lambda: None),
            mock.patch.object(register, "run_claude", lambda *a: self.calls.append(a)),
            mock.patch.object(register.changes, "private", lambda: None),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def install(self):
        with mock.patch("builtins.print"):
            return register.install(SimpleNamespace(yes=True, dry_run=False))

    def test_writes_normal_when_none(self):
        self.assertEqual(self.install(), 0)
        self.assertEqual(json.loads(self.file.read_text()), {"version": 2, "level": "normal"})
        self.assertEqual(access.load().level, "normal")   # installed, and the file is there
        self.file.unlink()
        self.assertEqual(access.load().level, "strict")   # taken away afterwards

    def test_keeps_a_chosen_level(self):
        self.file.write_text(json.dumps({"version": 2, "level": "strict", "areas": {"mail": {"read": "no"}}}))
        before = self.file.read_text()
        self.assertEqual(self.install(), 0)
        self.assertEqual(self.file.read_text(), before)

    def test_dry_run_writes_nothing(self):
        with mock.patch("builtins.print"):
            register.install(SimpleNamespace(yes=False, dry_run=True))
        self.assertFalse(self.file.exists())
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
