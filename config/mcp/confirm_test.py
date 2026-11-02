#!/usr/bin/env python3
"""When a card command's `"ask": false` lets a call past the card (#1832, #1865): `python3 config/mcp/confirm_test.py`.
Only for a tool that names its list in `unasked_by`, when that list isn't empty, and never for an act tool: a card
command that says so for another list of its area (files_trash under Normal's folders) still gets the card.
And what the card spells out as ⟨U+…⟩: every invisible or format character it would send (#1922)."""

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


class Hidden(unittest.TestCase):
    """The card spells out every character that would be sent unseen (#1887, #1922): Allow sends nothing hidden."""

    SHOWN = {
        "tag letters (ASCII smuggling)": "Hi\U000e0041\U000e0042\U000e007f",
        "language tag, unassigned tag": "\U000e0001\U000e0002",
        "variation selectors": "a︀b️c\U000e0100\U000e01ef",
        "a run of emoji selectors": "❤️️",
        "selector after a space": "❤ ️",
        "invisible operators": "x⁡⁢⁣⁤y",
        "soft hyphen, CGJ, Mongolian vowel separator": "pass­word͏᠎",
        "Hangul fillers": "ᅟᅠㅤﾠ",
        "zero-width, bidi, BOM": "​‎‮⁦﻿؜",
        "controls and separators": "a\x00\x1b\x7f\x85  \rb",
        "joiners between ASCII": "ab‍cd‌",
        "interlinear, shorthand, music format": "￹\U0001bca0\U0001d173",
    }

    def test_hidden_spelled_out(self):
        for name, text in self.SHOWN.items():
            with self.subTest(name):
                shown = confirm.visible(text)
                for c in text:
                    if not c.isascii() or not c.isprintable():
                        if c not in "❤ ":
                            self.assertIn(f"⟨U+{ord(c):04X}⟩", shown)
                self.assertTrue(all(c.isprintable() or c == "\n" for c in shown), ascii(shown))

    def test_example(self):
        self.assertEqual(confirm.visible("Hi\U000e0041­!"), "Hi⟨U+E0041⟩⟨U+00AD⟩!")

    def test_kept(self):
        """Text people write stays as it is: line ends, tabs, emoji, keycaps, scripts that need a joiner."""
        for text in ("Hei\n\tmaailma", "❤️", "☺︎", "1️⃣ #️⃣",
                     "\U0001f468‍❤️‍\U0001f468", "می‌خواهم",
                     "क्‍ष", "naïve café åäö", "一 　"):
            with self.subTest(text=ascii(text)):
                self.assertEqual(confirm.visible(text), text)
        self.assertEqual(confirm.visible("a\r\nb"), "a\nb")

    def test_field_and_list(self):
        self.assertIn("⟨U+E0041⟩", confirm.field("body", {}, "x\U000e0041")["text"])
        self.assertIn("⟨U+FE0F⟩", confirm.field("to", {}, ["a@x️.fi"])["text"])


if __name__ == "__main__":
    unittest.main()
