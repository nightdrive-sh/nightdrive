#!/usr/bin/env python3
"""A list's own order (order.py, #3507): `python3 plugins/tasks/lib/order_test.py`. A move writes the moved task
alone, a list with no room is renumbered, `tasks move` keeps an undo, and two computers that reordered the same list
merge (merge.py) without a mess or a line in the notes."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import order  # noqa: E402
from ics import Task  # noqa: E402
from merge import merge  # noqa: E402


def vtodo(uid, sort=None, created="20261120T100000Z", modified="20261123T080000Z"):
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Test//EN", "BEGIN:VTODO", f"UID:{uid}",
             "DTSTAMP:20261123T080000Z", f"LAST-MODIFIED:{modified}", f"CREATED:{created}", f"SUMMARY:{uid}",
             "STATUS:NEEDS-ACTION"]
    if sort is not None:
        lines.append(f"X-APPLE-SORT-ORDER:{sort}")
    return "\r\n".join(lines + ["END:VTODO", "END:VCALENDAR"]) + "\r\n"


def tasks(*pairs):
    return [Task(vtodo(u, s)) for u, s in pairs]


class Key(unittest.TestCase):
    def test_without_a_value_by_when_it_was_made_in_utc(self):
        # 2001-01-02 00:00 UTC is a day after Apple's epoch, whatever this computer's zone
        self.assertEqual(order.key(Task(vtodo("a", created="20010102T000000Z"))), 86400)

    def test_its_own_value_first(self):
        self.assertEqual(order.key(Task(vtodo("a", sort=-7))), -7)

    def test_a_new_task_comes_last(self):
        old = Task(vtodo("old", sort=100))
        new = Task(vtodo("new", created="20261124T090000Z"))
        self.assertEqual([t.get("UID") for t in order.ordered([new, old])], ["old", "new"])


class Place(unittest.TestCase):
    def test_between_two_writes_the_moved_one_only(self):
        self.assertEqual(order.place(tasks(("a", 0), ("b", 10)), 1), {None: 5})

    def test_ends(self):
        others = tasks(("a", 0), ("b", 10))
        self.assertEqual(order.place(others, 0), {None: -order.STEP})
        self.assertEqual(order.place(others, 2), {None: 10 + order.STEP})

    def test_no_room_renumbers_what_has_to_change(self):
        others = tasks(("a", 0), ("b", 1), ("c", 2))
        out = order.place(others, 1)
        got = {(t.get("UID") if t else None): v for t, v in out.items()}
        self.assertEqual(got, {None: order.STEP, "b": 2 * order.STEP, "c": 3 * order.STEP})   # a stays at 0

    def test_target(self):
        rows = tasks(("a", 0), ("b", 10), ("c", 20))
        self.assertEqual(order.target(rows, "b", up=True), 0)
        self.assertEqual(order.target(rows, "b", down=True), 2)
        self.assertIsNone(order.target(rows, "a", up=True))
        self.assertIsNone(order.target(rows, "c", bottom=True))
        self.assertIsNone(order.target(rows, "a", before="b"))        # already just before it
        self.assertEqual(order.target(rows, "c", before="a"), 0)
        self.assertEqual(order.target(rows, "a", after="c"), 2)


class Command(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        home = Path(self.tmp.name)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("XDG_", "NIGHTDRIVE_"))}
        self.env.update(HOME=str(home), NIGHTDRIVE_TASKS_DIR=str(home / "tasks"), XDG_STATE_HOME=str(home / "state"))
        self.ids = [self.run_cli("add", "--list", "Home", "--", t)["id"] for t in ("one", "two", "three")]
        # Made within a second: give them their own places, as a list someone has used for a while has
        for i, uid in enumerate(self.ids):
            p = next((home / "tasks").glob(f"*/{uid}.ics"))
            p.write_text(p.read_text().replace("END:VTODO", f"X-APPLE-SORT-ORDER:{i * 10}\r\nEND:VTODO"))
        self.home = home

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *argv, ok=True):
        p = subprocess.run([sys.executable, str(HERE / "cli.py"), argv[0], "--json", *argv[1:]], capture_output=True,
                           text=True, env=self.env, timeout=30)
        if ok:
            self.assertEqual(p.returncode, 0, p.stderr)
            return json.loads(p.stdout)
        return p

    def titles(self):
        return [t["title"] for t in self.run_cli("list", "--list", "Home")["tasks"]]

    def test_move_and_undo(self):
        one, two, three = self.ids
        before = {p: p.read_text() for p in self.home.glob("tasks/*/*.ics")}
        moved = self.run_cli("move", "--before", one, three)
        self.assertEqual(self.titles(), ["three", "one", "two"])
        changed = [p for p in before if p.read_text() != before[p]]
        self.assertEqual([p.stem for p in changed], [three])          # the moved one's file alone
        self.run_cli("restore", moved["undo"])
        self.assertEqual(self.titles(), ["one", "two", "three"])

    def test_up_down_and_the_ends(self):
        one, two, three = self.ids
        self.run_cli("move", "--to", "down", one)
        self.assertEqual(self.titles(), ["two", "one", "three"])
        self.run_cli("move", "--to", "top", three)
        self.assertEqual(self.titles(), ["three", "two", "one"])
        self.assertEqual(self.run_cli("move", "--to", "up", three)["order"], 10 - order.STEP)   # stays: no write
        self.assertEqual(self.titles(), ["three", "two", "one"])

    def test_a_done_task_has_no_place(self):
        self.run_cli("done", self.ids[0])
        p = self.run_cli("move", "--to", "down", self.ids[0], ok=False)
        self.assertEqual(p.returncode, 1)
        self.assertIn("is done", p.stderr)


class TwoComputers(unittest.TestCase):
    """Each side moved a task of the same list before they synced: per file, as Hub merges them"""

    def test_different_tasks_both_moves_stay(self):
        base = {"a": vtodo("a", 0), "b": vtodo("b", 10)}
        mine = {"a": vtodo("a", 20, modified="20261124T100000Z"), "b": base["b"]}      # a to the end here
        theirs = {"a": base["a"], "b": vtodo("b", -10, modified="20261124T110000Z")}   # b to the top there
        out = {u: Task(merge(base[u], mine[u], theirs[u]).text) for u in base}
        self.assertEqual(order.key(out["a"]), 20)
        self.assertEqual(order.key(out["b"]), -10)

    def test_same_task_newer_wins_without_a_note(self):
        base = vtodo("a", 0)
        m = merge(base, vtodo("a", 5, modified="20261124T120000Z"), vtodo("a", -5, modified="20261124T110000Z"))
        t = Task(m.text)
        self.assertEqual(order.key(t), 5)
        self.assertEqual(m.lost, [])
        self.assertEqual(t.get("DESCRIPTION"), "")


if __name__ == "__main__":
    unittest.main()
