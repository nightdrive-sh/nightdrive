#!/usr/bin/env python3
"""How notify.py starts a message's notification: python3 notify_test.py. It runs in the mail sync's oneshot service
(notmuch's post-new hook), which systemd stops with what is left in its cgroup when it ends. A systemd-run left running
as a child could be stopped before it had made the notification's unit (#3326: Tasks lost 5 of 10 that way). So
systemd-run is waited for, and only without one does the notification get a process of its own."""

import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

# CI runs the tests with python3 -I, which leaves the script's own folder off the path
sys.path.insert(0, str(Path(__file__).resolve().parent))

import notify  # noqa: E402


class Detached(unittest.TestCase):
    def detached(self, which="/usr/bin/systemd-run", run=None, env=None):
        run = run or mock.Mock(return_value=subprocess.CompletedProcess([], 0))
        env = {"XDG_RUNTIME_DIR": "/run/user/1000", **(env or {})}
        with mock.patch.object(notify.shutil, "which", return_value=which), \
                mock.patch.object(notify.subprocess, "run", run), \
                mock.patch.object(notify.subprocess, "Popen") as popen, \
                mock.patch.dict(notify.os.environ, env, clear=True):
            notify.detached("wait", "msg@example.com")
        return run, popen

    def test_waits_for_systemd_run(self):
        run, popen = self.detached(env={"NOTMUCH_CONFIG": "/x/notmuch"})
        cmd = run.call_args.args[0]
        self.assertEqual(cmd[:2], ["systemd-run", "--user"])
        self.assertIn("--setenv=NOTMUCH_CONFIG=/x/notmuch", cmd)
        self.assertEqual(cmd[-2:], ["wait", "msg@example.com"])
        self.assertIn("timeout", run.call_args.kwargs)
        popen.assert_not_called()

    def test_without_a_user_manager(self):
        _, popen = self.detached(run=mock.Mock(return_value=subprocess.CompletedProcess([], 1)))
        popen.assert_called_once()
        self.assertEqual(popen.call_args.args[0][0], sys.executable)

    def test_without_systemd_run(self):
        run, popen = self.detached(which=None)
        run.assert_not_called()
        popen.assert_called_once()

    def test_slow_systemd_run_shows_it_once(self):
        _, popen = self.detached(run=mock.Mock(side_effect=subprocess.TimeoutExpired("systemd-run", 20)))
        popen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
