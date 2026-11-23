#!/usr/bin/env python3
"""Settings › Claude › Access › Web (#2241): `python3 config/mcp/web_access_test.py`. Its Read is Claude Code's own
WebSearch and WebFetch, which Ask Claude turns on (hypr/scripts/ask-claude, tested in ask_claude_test.py): the window
shows them as the right's tools, and as nothing could ask about them in the background, the right is Allow or No only,
on every level and in the file. Runs against a file of its own."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import access  # noqa: E402
import levels  # noqa: E402


class Web(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.file = root / "claude-access.json"
        self.patches = [mock.patch.object(access, "FILE", self.file),
                        mock.patch.object(access, "INSTALL_STATE", root / "mcp-install.json")]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def row(self, now=None):
        rows = (now or access.load(self.file)).summary()["areas"]
        return next(r for r in rows if r["id"] == "web")

    def test_levels(self):
        # Log 4035: Strict No/No, Normal and Open Allow/Allow
        got = {lv: (levels.preset(lv, "web", "read"), levels.preset(lv, "web", "modify")) for lv in levels.LEVELS}
        self.assertEqual(got, {"strict": ("no", "no"), "normal": ("allow", "allow"), "open": ("allow", "allow")})

    def test_row_without_tools_of_ours(self):
        # No Nightdrive tool reads the web, yet the row is there with Claude Code's own; Modify is web_download's
        read = self.row()["rights"]["read"]
        self.assertEqual([t["name"] for t in read["tools"]], ["WebSearch", "WebFetch"])
        self.assertEqual(read["choices"], ["allow", "no"])
        self.assertEqual((read["value"], read["own"]), ("allow", False))
        self.assertFalse(any(t["asks"] or t["undo"] for t in read["tools"]))
        self.assertNotIn("modify", self.row()["rights"])

    def test_modify_is_web_download(self):
        # #2242: its Modify can ask (the card works in Ask Claude's panel), unlike Read
        rows = access.load(self.file).summary(access.installed_tools())["areas"]
        modify = next(r for r in rows if r["id"] == "web")["rights"]["modify"]
        self.assertEqual([t["name"] for t in modify["tools"]], ["web_download"])
        self.assertEqual(modify["choices"], ["allow", "ask", "no"])
        self.assertTrue(modify["tools"][0]["undo"])
        access.set_value("web", "modify", "ask", path=self.file)
        self.assertEqual(access.load(self.file).value("web", "modify"), "ask")

    def test_ask_is_refused(self):
        with self.assertRaises(ValueError):
            access.set_value("web", "read", "ask", path=self.file)
        self.assertFalse(self.file.exists())

    def test_no_is_own_and_back(self):
        access.set_value("web", "read", "no", path=self.file)
        read = self.row()["rights"]["read"]
        self.assertEqual((read["value"], read["preset"], read["own"]), ("no", "allow", True))
        access.set_value("web", "read", "allow", path=self.file)
        self.assertNotIn("areas", json.loads(self.file.read_text()))

    def test_ask_written_by_hand_is_no(self):
        self.file.write_text('{"version": 2, "level": "open", "areas": {"web": {"read": "ask"}}}')
        self.assertEqual(access.load(self.file).value("web", "read"), "no")
        self.assertEqual(self.row()["rights"]["read"]["value"], "no")

    def test_value_command(self):
        home = Path(self.tmp.name) / "home"
        path = home / ".config/nightdrive/claude-access.json"
        path.parent.mkdir(parents=True)

        def value(*args):
            run = subprocess.run([sys.executable, str(HERE / "access.py"), "value", *args], capture_output=True,
                                 text=True, env={"HOME": str(home)})
            return run.returncode, run.stdout.strip()

        self.assertEqual(value("web", "read"), (0, "allow"))     # no file, no install: Normal
        path.write_text('{"version": 2, "level": "strict"}')
        self.assertEqual(value("web", "read"), (0, "no"))
        path.write_text("{ broken")
        self.assertEqual(value("web", "read"), (0, "no"))        # Strict until it's fixed
        self.assertEqual(value("web", "write")[0], 2)


if __name__ == "__main__":
    unittest.main()
