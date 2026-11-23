#!/usr/bin/env python3
"""Changes in a row as one notification (#3223): `python3 config/mcp/batch_test.py`. One conversation's changes in one
area close together share a row that counts them, its Undo undoes them all (newest first) and Redo puts them back,
while the log keeps each one, which undo_change still undoes alone. Nothing here runs a real command or shows a row:
the log is a file of its own, and the commands and notify-send are stand-ins."""

import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True

import batch  # noqa: E402
import changes  # noqa: E402
import registry  # noqa: E402
import run  # noqa: E402
import undo  # noqa: E402
from run import ToolError  # noqa: E402

ME, OTHER = "100:1", "200:1"   # two conversations' servers
# The Tasks plugin as installed and on, from this checkout's plugins/tasks/mcp.json: a test's home has no plugins of
# its own (CI's is empty), so undo.registered is given the same list, written here, instead of the home's (#3392)
with tempfile.TemporaryDirectory() as _tmp:
    (Path(_tmp) / "active").write_text("tasks\t\n")
    TOOLS = registry.all_tools(registry.CORE, Path(_tmp) / "active")[0]


class Batches(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        patches = [mock.patch.object(changes, "FILE", Path(self.tmp.name) / "claude-changes.jsonl"),
                   mock.patch.object(run, "execute", side_effect=self.execute),
                   mock.patch.object(undo, "notify", side_effect=self.notify),
                   mock.patch.object(undo.access, "load", side_effect=lambda *a: undo.access.Access("normal")),
                   mock.patch.object(registry.Registry, "load", lambda reg: (TOOLS, []))]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.ran, self.rows, self.pressed, self.fail = [], [], [], set()

    def execute(self, where, argv, stdin, timeout):
        self.ran.append(argv[-1])   # the task's undo id, or a redo's title
        return ("", "the list is gone", 1) if argv[-1] in self.fail else ("", "", 0)

    def notify(self, entry_id, summary, body="", button=None):
        self.rows.append((entry_id, summary, body, button))
        return self.pressed.pop(0) if self.pressed else None

    def add(self, title, server=ME, area="tasks", tool="tasks_add"):
        # tasks_add's own undo template, so undo.registered takes it as the installed tool's
        # and its command with the arguments, so a redo is one it would run too
        undo_argv = ["tasks", "restore", f"id-{title}"] if tool == "tasks_add" else ["true", title]
        do, stdin = run.prepare(TOOLS["tasks_add"], {"title": title}) if tool == "tasks_add" else (["true"], None)
        return changes.add({"tool": tool, "notice": f"Added the task {title}", "arguments": {"title": title},
                            "before": {}, "do": do, "stdin": stdin, "undo": undo_argv, "remake": undo_argv,
                            "dir": str(HERE), "timeout": 5, "area": area, "options_from": [], "server": server,
                            "many": "Added {count} tasks"}, batch=True)

    def older(self, entry_id, seconds):
        """The entry made seconds earlier than it was"""
        with changes.editing() as entries:
            for e in entries:
                if e["id"] == entry_id:
                    e["time"] = time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(time.time() - seconds))

    def test_seven_adds_are_one_row(self):
        added = [self.add(f"T{n}") for n in range(1, 8)]
        self.assertEqual({e["batch"] for e in added}, {added[0]["id"]})
        self.assertEqual(len(changes.read()), 7)   # the log keeps each one
        text, body, action = batch.row(changes.batch(added[0]["id"]))
        self.assertEqual((text, action), ("Added 7 tasks", "undo"))
        self.assertEqual(body.splitlines(), ["…and 3 more", "Added the task T4", "Added the task T5",
                                             "Added the task T6", "Added the task T7"])

    def test_one_change_reads_as_before(self):
        e = self.add("Milk")
        self.assertEqual(batch.row(changes.batch(e["id"])), ("Added the task Milk", "", "undo"))

    def test_what_starts_a_new_batch(self):
        first = self.add("A")
        self.assertNotEqual(self.add("B", server=OTHER)["batch"], first["id"])     # another conversation
        self.assertNotEqual(self.add("C", area="notes")["batch"], first["id"])     # another area
        self.assertEqual(self.add("D")["batch"], first["id"])                      # theirs between: still one
        self.older(4, changes.BATCH_GAP + 5)
        self.assertNotEqual(self.add("E")["batch"], first["id"])                   # after a pause
        lone = changes.add({"tool": "x", "notice": "x", "area": "tasks", "server": None}, batch=True)
        self.assertEqual(lone["batch"], lone["id"])                                # no server to tell apart

    def test_a_batch_has_an_end(self):
        first = self.add("A")
        self.older(first["id"], changes.BATCH_SPAN + 5)
        self.assertNotEqual(self.add("B")["batch"], first["id"])

    def test_mixed_tools_count_changes(self):
        first = self.add("A")
        self.add("B", tool="tasks_done")
        self.assertEqual(batch.row(changes.batch(first["id"]))[0], "2 changes in Tasks")

    def test_undo_takes_them_all_newest_first_and_redo_puts_them_back(self):
        first = self.add("A")
        self.add("B")
        self.add("C")
        self.pressed = ["undo", "redo", None]
        undo.notice(first["id"], "undo")
        self.assertEqual(self.ran, ["id-C", "id-B", "id-A", "A", "B", "C"])   # redo: oldest first
        self.assertTrue(all(e["state"] == "done" for e in changes.batch(first["id"])))   # redone
        self.assertEqual([r[1] for r in self.rows], ["Added 3 tasks", "Undid: Added 3 tasks", "Added 3 tasks"])
        self.assertEqual([r[3] for r in self.rows], [("undo", "Undo"), ("redo", "Redo"), ("undo", "Undo")])

    def test_after_an_undo_a_new_change_is_a_new_row(self):
        first = self.add("A")
        self.pressed = ["undo", None]
        undo.notice(first["id"], "undo")
        self.assertNotEqual(self.add("B")["batch"], first["id"])

    def test_a_failure_stops_and_try_again_runs_the_rest(self):
        first = self.add("A")
        self.add("B")
        self.fail = {"id-A"}
        self.pressed = ["undo", "undo", None]
        undo.notice(first["id"], "undo")
        states = [e["state"] for e in changes.batch(first["id"])]
        self.assertEqual(states, ["done", "undone"])        # B undone, A refused twice
        self.assertEqual(self.ran, ["id-B", "id-A", "id-A"])
        self.assertEqual(self.rows[1][3], ("undo", "Try again"))

    def test_claude_undoes_one_and_the_row_keeps_the_rest(self):
        first = self.add("A")
        second = self.add("B")
        undo.perform(second["id"], "undo", claude=True)
        text, body, action = batch.row(changes.batch(first["id"]))
        self.assertEqual((text, action), ("Added the task A", "undo"))
        self.assertIn("1 undone already", body)
        self.assertEqual(undo.recent_changes({})["changes"][0]["batch"], first["id"])
        with self.assertRaises(ToolError):   # undone already, as before
            undo.perform(second["id"], "undo")

    def test_retired_row_names_the_changes(self):
        first = self.add("A")
        self.add("B")
        undo.retire(first["id"])
        lead, text, body, button = self.rows[-1]
        self.assertEqual((lead, text, button), (first["id"], "Added 2 tasks", None))
        self.assertIn(f"changes {first['id']}–{first['id'] + 1}", body)


class Spec(unittest.TestCase):
    def test_notice_many_is_checked(self):
        tool = {"name": "x_add", "title": "X", "description": "x", "class": "change", "area": "tasks",
                "inputSchema": {"type": "object", "properties": {}}, "command": ["x"], "undo": ["x", "undo"]}
        self.assertIsNone(registry.problem({**tool, "notice_many": "Added {count} things"}, None))
        for bad in ("Added things", "Added {count} {title}", 3):
            self.assertIn("notice_many", registry.problem({**tool, "notice_many": bad}, None) or "")


if __name__ == "__main__":
    unittest.main()
