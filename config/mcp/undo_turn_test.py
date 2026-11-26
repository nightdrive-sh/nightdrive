#!/usr/bin/env python3
"""Ask Claude's card Undo (#3157): `python3 config/mcp/undo_turn_test.py`. A turn's changes are those of its
conversation made since it started; they are undone newest first, those already undone are left alone, the rows of
their batches are shown again as they now stand, and a failure stops it with those before it undone. The change tool's
entry is marked with the conversation from the server's env. The log is a file of its own; undo.perform and the rows
are stand-ins (undo_test.py tests perform itself)."""

import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True

import changes  # noqa: E402
import undo  # noqa: E402
import undo_turn  # noqa: E402
from run import ToolError  # noqa: E402

CONV = "5396a169-98e0-4be8-9d92-1aa03c41bc70"
OTHER = "a64f5bf9-8f7a-4b41-b346-de296fe27066"


class Turn(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.performed, self.rows, self.fail = [], [], None
        for p in (mock.patch.object(changes, "FILE", Path(self.tmp.name) / "claude-changes.jsonl"),
                  mock.patch.object(undo, "perform", side_effect=self.perform),
                  mock.patch.object(undo, "show", side_effect=lambda lead, action: self.rows.append((lead, action)))):
            p.start()
            self.addCleanup(p.stop)
        self.start = int(time.time() * 1000)

    def perform(self, entry_id, action, claude=False):
        self.assertFalse(claude)   # the user's own button, as the notification's
        if entry_id == self.fail:
            raise ToolError(f"Undo of change {entry_id} failed")
        self.performed.append(entry_id)
        changes.mark(entry_id, "undone")

    def add(self, notice, area="tasks", ask=CONV, server="s1", ago=0):
        e = changes.add({"tool": "tasks_add", "notice": notice, "server": server, "area": area, "ask": ask}, batch=True)
        if ago:   # made before the turn: its time moved back
            with changes.editing() as entries:
                for x in entries:
                    if x["id"] == e["id"]:
                        x["time"] = time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(time.time() - ago))
        return e["id"]

    def test_only_this_turn(self):
        self.add("Earlier turn", ago=120)
        self.add("Another conversation", ask=OTHER, server="s2")
        self.add("A terminal session", ask=None, server="s3")
        a = self.add("Added A")
        self.assertEqual([c["id"] for c in undo_turn.listing(CONV, self.start)["changes"]], [a])

    def test_newest_first_and_rows_again(self):
        a, b = self.add("Added A"), self.add("Added B")
        c = self.add("Set the volume", area="sound")
        self.assertEqual(undo_turn.undo_turn(CONV, self.start), {"undone": ["Set the volume", "Added B", "Added A"]})
        self.assertEqual(self.performed, [c, b, a])
        # Two batches (tasks, sound), each row shown again, now offering Redo
        self.assertEqual(sorted(self.rows), sorted([(a, "redo"), (c, "redo")]))
        self.assertEqual({c["state"] for c in undo_turn.listing(CONV, self.start)["changes"]}, {"undone"})

    def test_already_undone_left_alone(self):
        a, b = self.add("Added A"), self.add("Added B")
        changes.mark(b, "undone")
        self.assertEqual(undo_turn.undo_turn(CONV, self.start), {"undone": ["Added A"]})
        self.assertEqual(self.performed, [a])

    def test_nothing_left(self):
        changes.mark(self.add("Added A"), "undone")
        self.assertEqual(undo_turn.undo_turn(CONV, self.start), {"undone": []})
        self.assertEqual(self.rows, [])

    def test_failure_stops_and_still_shows_the_rows(self):
        a, b = self.add("Added A"), self.add("Added B")
        self.fail = a
        with self.assertRaises(ToolError):
            undo_turn.undo_turn(CONV, self.start)
        self.assertEqual(self.performed, [b])
        self.assertEqual(changes.get(a)["state"], "done")
        self.assertEqual(self.rows, [(a, "undo")])   # the batch's row: one of two left, so Undo still

    def test_parse(self):
        self.assertEqual(undo_turn.parse(["undo", CONV, "123"]), ("undo", CONV, 123))
        for bad in ([], ["undo", CONV], ["redo", CONV, "1"], ["list", "../x", "1"], ["list", CONV, "-1"]):
            with self.assertRaises(ValueError, msg=bad):
                undo_turn.parse(bad)


class Marked(unittest.TestCase):
    """undo.offer writes the conversation from the server's env, and nothing without it"""

    def entry(self, env):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        tool = SimpleNamespace(name="tasks_add", dir=HERE / "elsewhere", spec={"undo": ["true"], "notify": False},
                               area="tasks")
        with mock.patch.object(changes, "FILE", Path(tmp.name) / "log.jsonl"), \
                mock.patch.dict(os.environ, env, clear=False), \
                mock.patch.object(undo.run, "prepare", return_value=(["true"], None)), \
                mock.patch.object(undo.run, "undo_argv", return_value=["true"]), \
                mock.patch.object(undo.run, "timeout_of", return_value=5):
            undo.offer(tool, {}, {"content": [], "structuredContent": {}})
            return changes.read()[-1]

    def test_ask_id(self):
        self.assertEqual(self.entry({"NIGHTDRIVE_ASK_ID": CONV})["ask"], CONV)
        os.environ.pop("NIGHTDRIVE_ASK_ID", None)
        self.assertNotIn("ask", self.entry({}))


if __name__ == "__main__":
    unittest.main()
