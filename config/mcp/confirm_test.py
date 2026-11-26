#!/usr/bin/env python3
"""When a card command's `"ask": false` lets a call past the card (#1832, #1865): `python3 config/mcp/confirm_test.py`.
Only for a tool that names its list in `unasked_by`, when that list isn't empty, and never for an act tool: a card
command that says so for another list of its area (files_trash under Normal's folders) still gets the card.
And what the card spells out as ⟨U+…⟩: every invisible or format character it would send (#1922), and a tool's
card_note under the card's note (#1913). And how qs's answer to the card is read (#1877), and what a card the pace
asked says and offers (#3224)."""

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


class Note(unittest.TestCase):
    """A tool's card_note goes under its kind's note: windows_view's caveat about a browser's password popup (#1913)."""

    def test_card_note(self):
        base = confirm.KINDS["read"][1]
        note = confirm.card(Tool(card_note="Mind the popup."), {})["note"]
        self.assertEqual(note, base + " Mind the popup.")
        self.assertEqual(confirm.card(Tool(), {})["note"], base)


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


class Show(unittest.TestCase):
    """What qs answers decides what Claude tells the user (#1877): no card is "couldn't be shown", not "showed wrong"."""

    def show(self, said):
        real, confirm.qs = confirm.qs, lambda *args: said if args[0] == "open" else ""
        try:
            with self.assertRaises(confirm.ToolError) as caught:
                confirm.show({"tool": "test_tool", "id": "c1"})
            return str(caught.exception)
        finally:
            confirm.qs = real

    def test_no_card(self):
        for said in (None, "Target not found.", "", "Function not found."):
            with self.subTest(said=said):
                self.assertIn("couldn't be shown", self.show(said))

    def test_wrong_digest(self):
        self.assertIn("didn't show the request", self.show("shown 0123"))


class Paced(unittest.TestCase):
    """A card shown only because of the pace (pace.py) says why, and is the only one that offers Allow all."""

    def tool(self, paced):
        tool = Tool(cls="change", right="modify", title="Add a task", card=None)
        tool.area, tool.paced = "tasks", paced
        return tool

    def ask(self, tool, said):
        real = confirm.show, confirm.wait
        confirm.show, confirm.wait = (lambda request: request["id"]), (lambda cid, name, timeout: said)
        try:
            return confirm.ask(tool, {})
        finally:
            confirm.show, confirm.wait = real

    def test_card_says_why(self):
        card = confirm.card(self.tool({"count": 20, "pace": 20, "burst": 100}), {})
        self.assertEqual(card["heading"], "Claude has made 20 changes in Tasks within a minute")
        self.assertIn("Past 20 a minute each change asks", card["note"])
        self.assertIn("up to 100 changes", card["note"])
        self.assertTrue(card["note"].endswith(confirm.KINDS["modify"][1]))
        self.assertEqual(card["title"], "Add a task")
        self.assertTrue(card["rest"])
        plain = confirm.card(self.tool(None), {})
        self.assertEqual(plain["heading"], confirm.KINDS["modify"][0])
        self.assertNotIn("rest", plain)

    def test_rest_only_where_offered(self):
        self.assertEqual(self.ask(self.tool({"count": 20, "pace": 20, "burst": 100}), "rest"), "rest")
        self.assertIs(self.ask(self.tool(None), "rest"), True)   # this call's Allow alone
        self.assertIs(self.ask(self.tool(None), False), False)


if __name__ == "__main__":
    unittest.main()
