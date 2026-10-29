#!/usr/bin/env python3
"""When a card command's `"ask": false` lets a call past the card (#1832, #1865): `python3 config/mcp/confirm_test.py`.
Only for a tool that names its list in `unasked_by`, when that list isn't empty, and never for an act tool: a card
command that says so for another list of its area (files_trash under Normal's folders) still gets the card."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import confirm  # noqa: E402


class Tool:
    def __init__(self, cls="read", right="read", options=None, **spec):
        self.name, self.cls, self.right, self.area = "test_tool", cls, right, "screen"
        self.options = options or {}
        self.dir = Path(tempfile.gettempdir())
        self.spec = {"class": cls, "inputSchema": {"type": "object", "properties": {}},
                     "card": [sys.executable, "-c", 'print(\'{"App": "kitty", "ask": false}\')'], **spec}


class Unasked(unittest.TestCase):
    def ask(self, tool):
        rows, ask = confirm.facts(tool, {})
        self.assertEqual([r["label"] for r in rows], ["App"])
        return ask

    def test_named_list(self):
        self.assertFalse(self.ask(Tool(options={"apps": ["kitty"]}, unasked_by="apps")))

    def test_without_unasked_by(self):
        """files_trash's area has folders on Normal, but the trash never named a list: its card stays."""
        self.assertTrue(self.ask(Tool(options={"folders": ["Downloads"]})))

    def test_another_list_of_the_area(self):
        self.assertTrue(self.ask(Tool(options={"folders": ["Downloads"], "apps": []}, unasked_by="apps")))

    def test_empty_or_odd_list(self):
        for chosen in ([], None, "kitty", {"kitty": True}):
            with self.subTest(chosen=chosen):
                self.assertTrue(self.ask(Tool(options={"apps": chosen}, unasked_by="apps")))
        self.assertTrue(self.ask(Tool(options={"apps": ["kitty"]}, unasked_by=["apps"])))

    def test_never_for_act(self):
        self.assertTrue(self.ask(Tool(cls="act", options={"apps": ["kitty"]}, unasked_by="apps")))


if __name__ == "__main__":
    unittest.main()
