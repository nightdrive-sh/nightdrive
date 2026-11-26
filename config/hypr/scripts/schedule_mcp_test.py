#!/usr/bin/env python3
"""Claude's schedule tools (#3151): `python3 config/hypr/scripts/schedule_mcp_test.py`. schedule_add's argv is one
`schedule` reads as meant, it always asks on the card, and the card says how the text was read; a row Claude's tool
adds is by Claude in the list and in its notifications, and the user's own aren't; a cancel's undo gives back the same
row, by and session kept, but not one whose time has passed. systemd and notifications are stubbed, as in
schedule_test.py."""

import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile
import time
import types
import unittest
from contextlib import redirect_stdout
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
MCP = os.path.join(HERE, "..", "..", "mcp")
sys.path.insert(0, MCP)
sys.dont_write_bytecode = True
import registry  # noqa: E402
import run  # noqa: E402

loader = importlib.machinery.SourceFileLoader("schedule", os.path.join(HERE, "schedule"))
schedule = importlib.util.module_from_spec(importlib.util.spec_from_loader("schedule", loader))
loader.exec_module(schedule)


def tools():
    found, problems = registry.read_file(os.path.join(MCP, "tools", "schedule.json"), MCP, None)
    assert not problems, problems
    return {t.name: t for t in found}


class Tools(unittest.TestCase):
    def test_all_three_load(self):
        self.assertEqual(sorted(tools()), ["schedule_add", "schedule_cancel", "schedule_list"])

    def test_add_always_asks(self):
        """Jari 19.11.: Claude's row is allowed on the card as it is added, whatever Access allows."""
        add = tools()["schedule_add"]
        self.assertEqual(add.cls, "change")
        self.assertEqual(add.spec["asks_if"], ["echo", "yes"])
        self.assertIn("card", add.spec)

    def argv(self, template, **values):
        words = run.expand(template, values)
        self.assertEqual(words[:2], ["nightdrive", "schedule"])
        return schedule.parse_add(words[2:])

    def test_argv_read_as_meant(self):
        add = tools()["schedule_add"].spec
        a = self.argv(add["command"], when="wake", text="--go on with #3151", to="Nightdrive Project Manager")
        self.assertEqual((a.when, a.command, a.to, a.json, a.run), ("wake", ["--go on with #3151"],
                                                                  "Nightdrive Project Manager", True, False))
        a = self.argv(add["command"], when="07:30", text="make && notify-send done", **{"as": "run"})
        self.assertEqual((a.when, a.command, a.run, a.claude), ("07:30", ["make && notify-send done"], True, False))
        a = self.argv(add["card"], when="15", text="check CI", **{"as": "claude"})
        self.assertEqual((a.card, a.claude, a.json), (True, True, False))
        # #3280: an arrival, not before the morning (the place is one word of WHEN's, its own argument)
        a = self.argv(add["command"], when="arrive the office", text="go on with the portraits", **{"from": "05:00"})
        self.assertEqual((a.when, a.from_, a.command), ("arrive the office", "05:00", ["go on with the portraits"]))
        a = self.argv(add["card"], when="leave home", text="make", **{"from": "2026-11-23 05:00", "as": "run"})
        self.assertEqual((a.when, a.from_, a.run, a.card), ("leave home", "2026-11-23 05:00", True, True))


class Rows(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.armed, self.notes = [], []
        for name, stub in [("STATE", os.path.join(self.dir.name, "schedule.json")),
                           ("CANCELLED", os.path.join(self.dir.name, "schedule-cancelled.json")),
                           ("arm", lambda r: (self.armed.append(r["id"]), (True, ""))[1]),
                           ("disarm", lambda rid: None),
                           ("notify", lambda rid, summary, body="", pinned=False, actions=():
                               self.notes.append((summary, body))),
                           ("run_command", lambda rid, line: (0, ""))]:
            patcher = mock.patch.object(schedule, name, stub)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = mock.patch.object(schedule.claude, "is_command", lambda word: word == "make")
        patcher.start()
        self.addCleanup(patcher.stop)

    def add(self, *argv, mcp=False):
        env = {k: v for k, v in os.environ.items() if k != "NIGHTDRIVE_MCP"}
        if mcp:
            env["NIGHTDRIVE_MCP"] = "1"
        out = io.StringIO()
        with mock.patch.dict(os.environ, env, clear=True), redirect_stdout(out):
            schedule.cmd_add(schedule.parse_add(["--json", *argv]))
        return json.loads(out.getvalue())

    def call(self, fn, **kw):
        out = io.StringIO()
        with redirect_stdout(out):
            fn(types.SimpleNamespace(**kw))
        return out.getvalue()

    def test_by_claude_only_from_the_tool(self):
        mine = self.add("15", "make")
        claudes = self.add("wake", "--", "go on with the release notes", mcp=True)
        self.assertEqual((mine["by"], claudes["by"]), ("user", "claude"))
        self.assertEqual((claudes["kind"], claudes["label"]), ("claude", "wake"))
        listed = self.call(schedule.cmd_list, json=False)
        self.assertEqual([("by Claude" in line) for line in listed.splitlines()], [False, True])

    def test_its_notifications_say_by_claude(self):
        r = self.add("15", "make", mcp=True)
        with schedule.state() as rows:
            row = next(x for x in rows if x["id"] == r["id"])
        schedule.execute(row)
        self.assertTrue(self.notes[0][1].endswith("by Claude"), self.notes)

    def test_card_adds_nothing(self):
        out = io.StringIO()
        with redirect_stdout(out):
            schedule.cmd_add(schedule.parse_add(["--card", "07:30", "--", "go on with #3151"]))
        said = json.loads(out.getvalue())
        self.assertIn("07:30", said["When"])
        self.assertIn("new Claude Code session", said["What happens"])
        self.assertEqual(self.armed, [])
        self.assertFalse(os.path.exists(schedule.STATE))

    def test_cancel_undone_gives_the_same_row(self):
        r = self.add("90m", "--", "check CI", mcp=True)
        self.call(schedule.cmd_cancel, id=r["id"], json=True)
        self.assertEqual(json.loads(self.call(schedule.cmd_list, json=True))["commands"], [])
        back = json.loads(self.call(schedule.cmd_uncancel, id=r["id"], json=True))
        self.assertEqual({k: back[k] for k in ("id", "by", "kind", "command", "at_unix")},
                         {k: r[k] for k in ("id", "by", "kind", "command", "at_unix")})
        self.assertEqual(self.armed, [r["id"], r["id"]])   # armed again
        with self.assertRaises(SystemExit):   # once only
            self.call(schedule.cmd_uncancel, id=r["id"], json=True)

    def test_no_uncancel_once_its_time_passed(self):
        r = self.add("15", "make")
        self.call(schedule.cmd_cancel, id=r["id"], json=True)
        with mock.patch.object(schedule.time, "time", return_value=time.time() + 3600), \
                self.assertRaises(SystemExit):
            self.call(schedule.cmd_uncancel, id=r["id"], json=True)


if __name__ == "__main__":
    unittest.main()
