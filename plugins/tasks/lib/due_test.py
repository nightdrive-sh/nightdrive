#!/usr/bin/env python3
"""How due.py starts a task's notification: python3 due_test.py. The timer's oneshot service ends as soon as `tasks due`
returns, and systemd stops what is left in its cgroup. A systemd-run left running as a child (Popen) was stopped with
it before it had made the notification's unit: 5 of 10 runs showed nothing (#3326, as unit-failed's in #3313). So
systemd-run is waited for, and only without one does the notification get a process of its own."""

import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

# CI runs the tests with python3 -I, which leaves the script's own folder off the path
sys.path.insert(0, str(Path(__file__).resolve().parent))

import due  # noqa: E402


class Spawn(unittest.TestCase):
    def spawn(self, which="/usr/bin/systemd-run", run=None, env=None):
        run = run or mock.Mock(return_value=subprocess.CompletedProcess([], 0))
        with mock.patch.object(due.shutil, "which", return_value=which), \
                mock.patch.object(due.subprocess, "run", run), \
                mock.patch.object(due.subprocess, "Popen") as popen, \
                mock.patch.dict(due.os.environ, env or {}, clear=True):
            due.spawn(["notice", "uid-1"])
        return run, popen

    def test_waits_for_systemd_run(self):
        run, popen = self.spawn()
        cmd = run.call_args.args[0]
        self.assertEqual(cmd[:2], ["systemd-run", "--user"])
        self.assertEqual(cmd[-2:], ["notice", "uid-1"])
        self.assertIn("timeout", run.call_args.kwargs)
        popen.assert_not_called()

    def test_carries_the_store(self):
        # The unit starts from the user manager's environment: a store of its own (a test's, the sandbox's) goes along
        run, _ = self.spawn(env={"NIGHTDRIVE_TASKS_DIR": "/x/tasks", "XDG_STATE_HOME": "/x/state", "OTHER": "1"})
        cmd = run.call_args.args[0]
        self.assertIn("--setenv=NIGHTDRIVE_TASKS_DIR=/x/tasks", cmd)
        self.assertIn("--setenv=XDG_STATE_HOME=/x/state", cmd)
        self.assertFalse(any("OTHER" in c for c in cmd))
        self.assertLess(cmd.index("--setenv=XDG_STATE_HOME=/x/state"), cmd.index("--"))

    def test_without_a_user_manager(self):
        run, popen = self.spawn(run=mock.Mock(return_value=subprocess.CompletedProcess([], 1)))
        popen.assert_called_once()
        self.assertEqual(popen.call_args.args[0][-2:], ["notice", "uid-1"])
        self.assertTrue(popen.call_args.kwargs.get("start_new_session"))

    def test_without_systemd_run(self):
        run, popen = self.spawn(which=None)
        run.assert_not_called()
        self.assertEqual(popen.call_args.args[0][0], sys.executable)

    def test_slow_systemd_run_shows_it_once(self):
        _, popen = self.spawn(run=mock.Mock(side_effect=subprocess.TimeoutExpired("systemd-run", 20)))
        popen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
