#!/usr/bin/env python3
"""Claude's remind tools (#3280): `python3 config/hypr/scripts/remind_mcp_test.py`. remind_add's argv, as the MCP
server builds it from the tool's template, is one `remind` reads as meant (an event, a place, --from, a message that
looks like an option), and remind_cancel's undo gives back the same row, an event's too, which has no @UNIX to be added
again from. The tool's own templates run through remind's real argv parsing (main). places.json is in a throwaway home;
systemd and the banner are stubbed: nothing here starts a timer or shows anything."""

import importlib.machinery
import importlib.util
import io
import json
import os
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
MCP = os.path.join(HERE, "..", "..", "mcp")
sys.path.insert(0, MCP)
sys.dont_write_bytecode = True
import registry  # noqa: E402
import run  # noqa: E402

loader = importlib.machinery.SourceFileLoader("remind", os.path.join(HERE, "remind"))
remind = importlib.util.module_from_spec(importlib.util.spec_from_loader("remind", loader))
loader.exec_module(remind)


def tools():
    found, problems = registry.read_file(os.path.join(MCP, "tools", "remind.json"), MCP, None)
    assert not problems, problems
    return {t.name: t for t in found}


class Tools(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.armed = []
        home = os.path.join(self.dir.name, "home")
        os.makedirs(os.path.join(home, ".config", "nightdrive"))
        with open(os.path.join(home, ".config", "nightdrive", "places.json"), "w") as f:
            json.dump({"places": [{"name": "work", "wifi": ["Office"]}]}, f)
        patches = [mock.patch.dict(os.environ, {"HOME": home})]
        for name, stub in [("STATE", os.path.join(self.dir.name, "reminders.json")),
                           ("CANCELLED", os.path.join(self.dir.name, "reminders-cancelled.json")),
                           ("arm", lambda r: (self.armed.append(r["id"]), (True, ""))[1]),
                           ("disarm", lambda rid: None),
                           ("tell", lambda *a, **k: None)]:
            patches.append(mock.patch.object(remind, name, stub))
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.spec = {name: t.spec for name, t in tools().items()}

    def remind(self, template, values):
        """The template expanded as the server does, then run through remind's own main()."""
        words = run.expand(template, values)
        self.assertEqual(words[:2], ["nightdrive", "remind"])
        out = io.StringIO()
        with mock.patch.object(sys, "argv", ["remind", *words[2:]]), redirect_stdout(out):
            remind.main()
        return json.loads(out.getvalue())

    def test_all_three_load(self):
        self.assertEqual(sorted(self.spec), ["remind_add", "remind_cancel", "remind_list"])

    def test_the_morning_arrival_read_as_meant(self):
        """Jari's sentence: "remind me when I get to work in the morning…", said in the evening."""
        r = self.remind(self.spec["remind_add"]["command"],
                        {"when": "arrive work", "from": "05:00", "message": "--finish the Cold State portraits"})
        self.assertEqual((r["when"], r["place"], r["label"]), ("arrive", "work", "arrive work"))
        self.assertIsNotNone(r["from"])
        self.assertEqual(r["message"], "--finish the Cold State portraits")
        self.assertEqual(self.armed, [r["id"]])   # its week's timer

    def test_plain_ones_still(self):
        for values in [{"when": "15", "message": "Tea"}, {"when": "wake"}, {"when": "login", "message": "Hi"}]:
            r = self.remind(self.spec["remind_add"]["command"], values)
            self.assertEqual(r["message"], values.get("message", remind.DEFAULT_MESSAGE))

    def test_schema_takes_events(self):
        props = self.spec["remind_add"]["inputSchema"]["properties"]
        pattern = re.compile(props["when"]["pattern"])
        for ok in ["15", "1h30m", "22:45", "wake", "login", "arrive work", "leave the cottage"]:
            self.assertTrue(pattern.fullmatch(ok), ok)
        for bad in ["arrive", "arrive -x", "soon", "wake work"]:
            self.assertFalse(pattern.fullmatch(bad), bad)

    def test_cancel_undone_gives_the_event_back(self):
        add, cancel = self.spec["remind_add"], self.spec["remind_cancel"]
        r = self.remind(add["command"], {"when": "arrive work", "from": "05:00", "message": "Portraits"})
        before = self.remind(cancel["before"], {"id": r["id"]})
        answer = self.remind(cancel["command"], {"id": r["id"]})
        self.assertEqual([x["id"] for x in answer["cancelled"]], [r["id"]])
        undo = run.undo_argv(tools()["remind_cancel"], {"id": r["id"]}, {"structuredContent": answer}, before)
        back = self.remind(undo, {})
        self.assertEqual({k: back[k] for k in ("id", "when", "place", "from", "message")},
                         {k: r[k] for k in ("id", "when", "place", "from", "message")})
        listed = self.remind(self.spec["remind_list"]["command"], {})
        self.assertEqual([x["id"] for x in listed["reminders"]], [r["id"]])


if __name__ == "__main__":
    unittest.main()
