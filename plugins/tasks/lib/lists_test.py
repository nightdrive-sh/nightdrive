#!/usr/bin/env python3
"""The lists' changes and their undo (#2022): `python3 plugins/tasks/lib/lists_test.py`. A new list, a rename and a
removal each come undone with `tasks restore`; a removal takes the tasks only when asked to and gives them back from
the trash; an undo that would write over a list changed since is refused."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


class Lists(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        home = Path(self.tmp.name).resolve()
        self.data = home / "tasks"
        self.trash = home / "state/nightdrive/tasks/trash"
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("XDG_", "NIGHTDRIVE_"))}
        self.env.update(HOME=str(home), NIGHTDRIVE_TASKS_DIR=str(self.data), XDG_STATE_HOME=str(home / "state"))

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *argv):
        return subprocess.run([sys.executable, str(HERE / "cli.py"), *argv], capture_output=True, text=True,
                              env=self.env, timeout=30)

    def ok(self, *argv):
        p = self.run_cli(argv[0], "--json", *argv[1:])
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(p.stdout)

    def refused(self, *argv):
        p = self.run_cli(*argv)
        self.assertEqual(p.returncode, 1, p.stdout)
        return p.stderr

    def names(self):
        return [l["name"] for l in self.ok("lists")]

    def test_new_and_undo(self):
        r = self.ok("list-new", "--", "  Home   chores ")
        self.assertEqual((r["name"], r["tasks"]), ("Home chores", 0))
        self.assertIn("already", self.refused("list-new", "home CHORES"))
        self.assertIn("needs a name", self.refused("list-new", "  "))
        self.ok("restore", r["undo"])
        self.assertEqual(self.names(), [])

    def test_rename_keeps_folder_and_undo(self):
        self.ok("add", "--list", "Shopping", "--", "Milk")
        self.ok("list-new", "Work")
        r = self.ok("list-rename", "shopping", "Groceries")
        self.assertEqual((r["id"], r["old"], r["open"]), ("shopping", "Shopping", 1))
        self.assertIn("already", self.refused("list-rename", "groceries", "work"))
        self.ok("list-rename", "groceries", "groceries")         # its own name in another case is fine
        self.assertIn("changed since", self.refused("restore", r["undo"]))
        self.assertEqual(self.names(), ["groceries", "Work"])

    def test_remove_with_tasks_and_undo(self):
        self.ok("add", "--list", "Trip", "--", "Passport")
        done = self.ok("add", "--list", "Trip", "--", "Tickets")
        self.ok("done", done["id"])
        (self.data / "trip/color").write_text("#ff0000\n")    # a sync's own file comes back too
        self.assertIn("2 tasks (1 open)", self.refused("list-remove", "trip"))
        r = self.ok("list-remove", "--with-tasks", "Trip")
        self.assertEqual((r["tasks"], r["open"]), (2, 1))
        self.assertFalse((self.data / "trip").exists())
        self.assertEqual(len(list(self.trash.glob("trip/*.ics"))), 2)
        self.ok("restore", r["undo"])
        self.assertEqual(self.names(), ["Trip"])
        self.assertEqual((self.data / "trip/color").read_text(), "#ff0000\n")
        self.assertEqual(len(self.ok("list", "--list", "trip", "--view", "all")["tasks"]), 2)
        self.assertEqual(list(self.trash.glob("trip/*.ics")), [])

    def test_remove_undo_refused_over_a_new_list(self):
        self.ok("list-new", "Trip")
        r = self.ok("list-remove", "trip")
        self.ok("list-new", "Trip")                            # the same folder again, made since
        self.assertIn("changed since", self.refused("restore", r["undo"]))
        self.assertEqual(self.names(), ["Trip"])

    def test_unknown_list(self):
        self.assertIn("No list called", self.refused("list-remove", "Nope"))


if __name__ == "__main__":
    unittest.main()
