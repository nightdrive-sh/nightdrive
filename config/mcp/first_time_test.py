#!/usr/bin/env python3
"""A card that asks the first time (#1929): `python3 config/mcp/first_time_test.py`.

An asks_if that prints `first KEY` asks until the user allows a call for KEY once; allowed.py remembers that beside
Access, and later calls for KEY run without the card. A refusal or a timeout remembers nothing, another KEY asks again,
and forget makes it ask again. calendar_add's `calendar shared` gives a calendar's own key, and a shared one still asks
every time. Nothing here shows a real card: the card and the commands are stand-ins, the memory a file of its own."""

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True

import access  # noqa: E402
import allowed  # noqa: E402
import confirm  # noqa: E402
import registry  # noqa: E402
import run  # noqa: E402
import undo  # noqa: E402
from run import ToolError  # noqa: E402

KEY = "Family (acct/fam)"


def stub(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class Memory(unittest.TestCase):
    """A tool and its keys, beside Access: what can't be read is nothing allowed"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.file = Path(self.tmp.name) / "claude-allowed.json"
        p = mock.patch.object(allowed, "FILE", self.file)
        p.start()
        self.addCleanup(p.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def test_remember_and_forget(self):
        self.assertFalse(allowed.has("calendar_add", KEY))
        allowed.remember("calendar_add", KEY)
        allowed.remember("calendar_add", KEY)          # once is enough
        allowed.remember("calendar_add", "Work (acct/work)")
        self.assertTrue(allowed.has("calendar_add", KEY))
        self.assertFalse(allowed.has("other_tool", KEY))   # a key is the tool's own
        self.assertEqual(allowed.lines(), ["calendar_add\tFamily (acct/fam)", "calendar_add\tWork (acct/work)"])
        self.assertEqual(allowed.forget("calendar_add", KEY), 1)
        self.assertEqual(allowed.lines(), ["calendar_add\tWork (acct/work)"])
        self.assertEqual(allowed.forget("calendar_add"), 1)
        self.assertEqual(allowed.forget("calendar_add"), 0)
        self.assertEqual(allowed.load(), {})

    def test_broken_file_is_nothing_allowed(self):
        for text in ("{", "[]", '{"allowed": []}', '{"allowed": {"calendar_add": "Family (acct/fam)"}}'):
            with self.subTest(text=text):
                self.file.write_text(text)
                self.assertFalse(allowed.has("calendar_add", KEY))

    def test_a_key_is_one_line(self):
        for bad in ("", "a\nb", "x" * 201, "a\x00b"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                allowed.remember("calendar_add", bad)
        self.assertFalse(self.file.exists())

    def test_the_command(self):
        with mock.patch("sys.stdout") as out:
            self.assertEqual(access.main(["allowed"]), 0)
            allowed.remember("calendar_add", KEY)
            self.assertEqual(access.main(["forget", "calendar_add", "Work (acct/work)"]), 0)
            self.assertTrue(allowed.has("calendar_add", KEY))
            self.assertEqual(access.main(["forget", "calendar_add"]), 0)
        self.assertFalse(allowed.has("calendar_add", KEY))
        self.assertIn("Nothing to forget", "".join(c.args[0] for c in out.write.call_args_list))


class Call(unittest.TestCase):
    """registry.call with an asks_if that says first KEY"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        p = mock.patch.object(allowed, "FILE", self.dir / "claude-allowed.json")
        p.start()
        self.addCleanup(p.stop)
        self.says = self.dir / "says"
        stub(self.dir / "asks", f"#!/bin/sh\ncat {self.says}\n")
        stub(self.dir / "act", f"#!/bin/sh\necho done >> {self.dir}/ran\necho '{{}}'\n")
        spec = {"name": "t_add", "title": "Add", "description": "x", "class": "change", "area": "calendar",
                "inputSchema": {"type": "object", "properties": {"calendar": {"type": "string"}},
                                "additionalProperties": False},
                "command": ["./act"], "undo": ["./act"], "asks_if": ["./asks", "{calendar}"]}
        self.tool = registry.Tool(spec, self.dir, "test")
        self.reg = registry.Registry(core=self.dir / "none", active=self.dir / "none", access_file=self.dir / "a.json")
        self.reg.visible = lambda: {"t_add": self.tool}
        self.reg.rules = access.Access("open")
        self.reg.undo = None
        self.cards, self.answer = [], True
        self.reg.confirm = SimpleNamespace(ask=self.card)

    def tearDown(self):
        self.tmp.cleanup()

    def card(self, tool, arguments):
        self.cards.append(confirm.card(tool, arguments)["note"])
        if isinstance(self.answer, Exception):
            raise self.answer
        return self.answer

    def call(self, said, calendar="Family"):
        self.says.write_text(said)
        return self.reg.call("t_add", {"calendar": calendar})

    def ran(self):
        path = self.dir / "ran"
        return len(path.read_text().splitlines()) if path.exists() else 0

    def test_asks_once_then_not(self):
        self.call(f"first {KEY}\n")
        self.assertEqual(len(self.cards), 1)
        self.assertIn(f"Claude does this for {KEY} without asking from now on", self.cards[0])
        self.assertNotIn("card_note", self.tool.spec)       # the note was this card's alone
        self.call(f"first {KEY}\n")
        self.assertEqual((len(self.cards), self.ran()), (1, 2))
        self.call("first Work (acct/work)")                 # another calendar asks
        self.assertEqual(len(self.cards), 2)

    def test_a_refusal_remembers_nothing(self):
        self.answer = False
        with self.assertRaises(ToolError):
            self.call(f"first {KEY}")
        self.assertEqual((self.ran(), allowed.load()), (0, {}))
        self.reg.pace.refusals.clear()                      # the same call isn't shown again at once otherwise
        self.answer = True
        self.call(f"first {KEY}")
        self.assertEqual((len(self.cards), self.ran()), (2, 1))

    def test_a_timeout_remembers_nothing(self):
        self.answer = ToolError("The card timed out")
        with self.assertRaises(ToolError):
            self.call(f"first {KEY}")
        self.assertEqual((self.ran(), allowed.load()), (0, {}))

    def test_yes_asks_every_time_and_remembers_nothing(self):
        self.call("yes")
        self.call("yes")
        self.assertEqual((len(self.cards), allowed.load()), (2, {}))
        self.assertNotIn("from now on", self.cards[0])

    def test_access_ask_asks_and_remembers_nothing(self):
        self.reg.rules = access.Access("open", {"calendar": {"modify": "ask"}})
        self.call(f"first {KEY}")
        self.assertEqual((len(self.cards), allowed.load()), (1, {}))

    def test_forget_asks_again(self):
        self.call(f"first {KEY}")
        allowed.forget("t_add", KEY)
        self.call(f"first {KEY}")
        self.assertEqual(len(self.cards), 2)

    def test_a_bad_first_stops_the_call(self):
        for said in ("first", "first ", "first\tx", "FIRST x", "first " + "x" * 201):
            with self.subTest(said=said), self.assertRaises(ToolError) as e:
                self.call(said)
            self.assertIn("didn't say yes, no or first KEY", str(e.exception))
        self.assertEqual((self.ran(), self.cards), (0, []))

    def test_the_note_shows_what_hides(self):
        self.call("first Fam‮ily (acct/fam)")
        self.assertIn("⟨U+202E⟩", self.cards[0])


class Redo(unittest.TestCase):
    """A redo is the tool's call again: a calendar not yet allowed asks, and allowing it remembers"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.answer, self.cards, self.says = True, [], f"first {KEY}"
        for p in (mock.patch.object(allowed, "FILE", Path(self.tmp.name) / "claude-allowed.json"),
                  mock.patch.object(run, "execute", side_effect=lambda *a: (self.says + "\n", "", 0)),
                  mock.patch.object(confirm, "ask", side_effect=lambda t, a: self.cards.append(
                      t.spec.get("card_note")) or self.answer),
                  mock.patch.object(undo.access, "load", side_effect=lambda *a: access.Access("normal"))):
            p.start()
            self.addCleanup(p.stop)
        tools, _ = registry.read_file(REPO / "plugins/calendar/mcp.json", REPO / "plugins/calendar", "calendar")
        self.tool = next(t for t in tools if t.name == "calendar_add")
        self.entry = {"id": 7, "notice": "Added to Family: Dinner", "arguments": {"calendar": "Family"}}

    def tearDown(self):
        self.tmp.cleanup()

    def test_redo_asks_first_and_remembers(self):
        self.answer = False
        with self.assertRaises(ToolError):
            undo.ask_call(self.entry, self.tool, self.entry["arguments"], "allow", "redoing")
        self.assertFalse(allowed.has("calendar_add", KEY))
        self.answer = True
        undo.ask_call(self.entry, self.tool, self.entry["arguments"], "allow", "redoing")
        self.assertIn("from now on", self.cards[-1])
        self.assertTrue(allowed.has("calendar_add", KEY))
        undo.ask_call(self.entry, self.tool, self.entry["arguments"], "allow", "redoing")
        self.assertEqual(len(self.cards), 2)


class CalendarKey(unittest.TestCase):
    """`calendar shared`: yes for a shared calendar, else first NAME (ID), the id telling apart two of one name"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.conf = self.home / ".config/calendar/calendars.conf"
        self.conf.parent.mkdir(parents=True)
        for cal, name in (("fam", "Family"), ("other", "Family"), ("me", "  My\tlong   name ")):
            d = self.home / f".local/share/calendar/acct/{cal}"
            d.mkdir(parents=True)
            (d / "displayname").write_text(name)

    def tearDown(self):
        self.tmp.cleanup()

    def shared(self, calendar, conf=""):
        self.conf.write_text("[account acct]\ntype = carddav\naddress = a@b.c\npassword-cmd = true\n"
                             f"caldav-url = https://dav.example/\n{conf}")
        env = {**os.environ, "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.home / ".config"),
               "XDG_DATA_HOME": str(self.home / ".local/share")}
        p = subprocess.run([sys.executable, str(REPO / "plugins/calendar/lib/write.py"), "shared", "--calendar",
                            calendar], env=env, capture_output=True, text=True, timeout=20)
        return p.returncode, p.stdout.strip()

    def test_keys(self):
        self.assertEqual(self.shared("acct/fam"), (0, "first Family (acct/fam)"))
        self.assertEqual(self.shared("acct/other"), (0, "first Family (acct/other)"))
        self.assertEqual(self.shared("acct/me"), (0, "first My long name (acct/me)"))   # one line
        self.assertEqual(self.shared("acct/fam", "shared = Family\n"), (0, "yes"))
        status, said = self.shared("acct/me")
        self.assertTrue(allowed.KEY.fullmatch(said.partition(" ")[2]), said)


if __name__ == "__main__":
    unittest.main()
