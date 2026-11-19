#!/usr/bin/env python3
"""schedule's rules (#3121): `python3 config/hypr/scripts/schedule_test.py`. The command line as typed, options only
before the command, a broken line refused at once, the state file kept under its lock, a cancelled command never run,
and a run that runs once and says what it ran and how it went. systemd and notifications are stubbed: nothing here
starts a timer; the run itself goes through sh for real, without systemd-run."""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import types
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("schedule", os.path.join(HERE, "schedule"))
schedule = importlib.util.module_from_spec(importlib.util.spec_from_loader("schedule", loader))
loader.exec_module(schedule)


class CommandLine(unittest.TestCase):
    def test_one_word_is_a_line(self):
        self.assertEqual(schedule.command_line(["make && notify-send done"]), "make && notify-send done")

    def test_words_keep_their_spaces(self):
        self.assertEqual(schedule.command_line(["notify-send", "Tea is ready"]), "notify-send 'Tea is ready'")

    def test_empty(self):
        self.assertEqual(schedule.command_line([]), "")
        self.assertEqual(schedule.command_line(["  "]), "")

    def test_syntax(self):
        self.assertEqual(schedule.syntax_error("echo hi | tr a-z A-Z"), "")
        self.assertNotEqual(schedule.syntax_error('echo "unclosed'), "")


class ParseAdd(unittest.TestCase):
    def test_command_options_stay_its_own(self):
        a = schedule.parse_add(["15", "ls", "-la", "--json"])
        self.assertEqual((a.when, a.command, a.json), ("15", ["ls", "-la", "--json"], False))

    def test_options_before_the_command(self):
        a = schedule.parse_add(["--json", "14:45", "--", "--weird", "x"])
        self.assertEqual((a.when, a.command, a.json), ("14:45", ["--weird", "x"], True))
        a = schedule.parse_add(["14:45", "--json", "make"])
        self.assertEqual((a.when, a.command, a.json), ("14:45", ["make"], True))

    def test_refused(self):
        self.assertIsNone(schedule.parse_add([]))
        self.assertIsNone(schedule.parse_add(["--json"]))
        self.assertIsNone(schedule.parse_add(["--nope", "15", "make"]))


class Rows(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.armed, self.disarmed, self.notes, self.ran = [], [], [], []
        self.result = (0, "")
        # Each stub undone after the test: RunCommand below needs the real run_command
        for name, stub in [("STATE", os.path.join(self.dir.name, "schedule.json")),
                           ("arm", lambda r: (self.armed.append(r["id"]), (True, ""))[1]),
                           ("disarm", self.disarmed.append),
                           ("notify", lambda rid, summary, body="", pinned=False: self.notes.append((summary, body, pinned))),
                           ("run_command", lambda rid, line: (self.ran.append(line), self.result)[1]),
                           ("screen_locked", lambda: False)]:   # the desktop's own lock mustn't hold a run back
            patcher = mock.patch.object(schedule, name, stub)
            patcher.start()
            self.addCleanup(patcher.stop)

    def tearDown(self):
        self.dir.cleanup()

    def add(self, when, *command):
        schedule.cmd_add(types.SimpleNamespace(json=True, when=when, command=list(command)))

    def rows(self):
        with open(schedule.STATE) as f:
            return json.load(f)["commands"]

    def test_add_list_cancel(self):
        self.add("10", "notify-send", "Tea is ready")
        self.add("5", "make")
        rows = self.rows()
        self.assertEqual([r["command"] for r in rows], ["notify-send 'Tea is ready'", "make"])
        self.assertEqual(self.armed, [r["id"] for r in rows])
        schedule.cmd_cancel(types.SimpleNamespace(json=True, id=rows[0]["id"]))
        self.assertEqual(self.disarmed, [rows[0]["id"]])
        self.assertEqual([r["id"] for r in self.rows()], [rows[1]["id"]])
        schedule.cmd_cancel(types.SimpleNamespace(json=True, id="all"))
        self.assertEqual(self.rows(), [])

    def test_refused_adds_nothing(self):
        for when, command in [("soon", ["make"]), ("15", []), ("15", ['echo "x']), ("10081", ["make"])]:
            with self.assertRaises(SystemExit):
                self.add(when, *command)
        self.assertEqual(self.armed, [])
        self.assertFalse(os.path.exists(schedule.STATE))

    def test_put_back_at_its_time(self):
        """A cancel undone: the same moment and command again (schedule add @UNIX)."""
        at = int(time.time()) + 600
        self.add(f"@{at}", "make")
        self.assertEqual([(r["at"], r["command"]) for r in self.rows()], [(at, "make")])

    def test_fire_runs_once_and_says_so(self):
        self.add("1", "make")
        rid = self.rows()[0]["id"]
        schedule.cmd_fire(types.SimpleNamespace(id=rid))
        schedule.cmd_fire(types.SimpleNamespace(id=rid))      # a second run (a restart) runs nothing again
        self.assertEqual(self.ran, ["make"])
        self.assertEqual([n[0] for n in self.notes], ["Running: make", "Done: make"])
        self.assertEqual(self.rows(), [])

    def test_failure_is_pinned_with_its_output(self):
        self.result = (2, "one\ntwo\nthree\nfour\n")
        self.add("1", "make")
        schedule.cmd_fire(types.SimpleNamespace(id=self.rows()[0]["id"]))
        summary, body, pinned = self.notes[-1]
        self.assertEqual(summary, "Failed (exit 2): make")
        self.assertTrue(pinned)
        self.assertIn("two\nthree\nfour", body)
        self.assertNotIn("one", body)
        self.assertIn("journalctl", body)

    def test_cancelled_never_runs(self):
        self.add("1", "make")
        rid = self.rows()[0]["id"]
        schedule.cmd_cancel(types.SimpleNamespace(json=True, id="all"))
        schedule.cmd_fire(types.SimpleNamespace(id=rid))
        self.assertEqual((self.ran, self.notes), ([], []))

    def test_broken_state_file(self):
        with open(schedule.STATE, "w") as f:
            f.write("{not json")
        self.add("3", "make")
        self.assertEqual([r["command"] for r in self.rows()], ["make"])


class RunCommand(unittest.TestCase):
    """The run itself, through sh but without systemd-run (CI has no user manager): its exit code and output."""
    def setUp(self):
        real = subprocess.run
        # Drop systemd-run's part of the argv: what is left from "sh" on is the run as such
        patcher = mock.patch.object(schedule.subprocess, "run", lambda argv, **kw: real(argv[argv.index("sh"):], **kw))
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_code_and_output(self):
        self.assertEqual(schedule.run_command("x", "echo out; echo err >&2; exit 3"), (3, "out\nerr\n"))

    def test_local_bin_in_path(self):
        code, out = schedule.run_command("x", 'echo "$PATH"')
        self.assertEqual(code, 0)
        self.assertIn(os.path.expanduser("~/.local/bin"), out.strip().split(":"))


if __name__ == "__main__":
    unittest.main(verbosity=1, argv=sys.argv[:1])
