#!/usr/bin/env python3
"""The sleep hook's failed-sleep notice (#2033): `python3 config/system/nightdrive_sleep_test.py`. Runs the hook as
systemd-sleep would (pre, then post) against a made-up /sys/power/suspend_stats, in dry-run (no rfkill), with its /run
files, log and notifier in a throwaway folder: nothing of the machine's is read or changed."""

import os
import subprocess
import tempfile
import unittest

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "nightdrive-sleep")


class FailedSleep(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = self.tmp.name
        self.stats, self.run_dir = os.path.join(d, "stats"), os.path.join(d, "run")
        os.mkdir(self.stats)
        os.mkdir(self.run_dir)
        self.calls = os.path.join(d, "calls")
        self.notifier = os.path.join(d, "notify")
        with open(self.notifier, "w") as f:
            f.write(f'#!/bin/sh\necho "$1|$2" >> {self.calls}\n')
        os.chmod(self.notifier, 0o755)
        self.env = dict(os.environ, NIGHTDRIVE_DRYRUN="1", NIGHTDRIVE_SLEEP_RUN=self.run_dir,
                        NIGHTDRIVE_SUSPEND_STATS=self.stats, NIGHTDRIVE_SLEEP_NOTIFY=self.notifier,
                        NIGHTDRIVE_SLEEP_LOG=os.path.join(d, "log"), NIGHTDRIVE_BATTERY=os.path.join(d, "nobattery"),
                        NIGHTDRIVE_RADIOS="0")
        self.stat(fail=0, dev="", errno=0)

    def tearDown(self):
        self.tmp.cleanup()

    def stat(self, **values):
        for name, value in values.items():
            with open(os.path.join(self.stats, {"dev": "last_failed_dev", "errno": "last_failed_errno"}.get(name, name)),
                      "w") as f:
                f.write(f"{value}\n")

    def hook(self, stage):
        r = subprocess.run(["sh", HOOK, stage, "suspend"], env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

    def sleep(self, fails=False, dev="soc:display-subsystem", errno=-22):
        """One try: pre, the kernel counting a failure or not, post."""
        self.hook("pre")
        if fails:
            with open(os.path.join(self.stats, "fail")) as f:
                self.stat(fail=int(f.read()) + 1, dev=dev, errno=errno)
        self.hook("post")

    def notified(self):
        try:
            with open(self.calls) as f:
                return f.read().splitlines()
        except FileNotFoundError:
            return []

    def state(self):
        path = os.path.join(self.run_dir, "nightdrive-sleep.failed")
        if not os.path.exists(path):
            return None
        with open(path) as f:
            return dict(line.split("=", 1) for line in f.read().splitlines())

    def test_a_sleep_that_works_tells_nothing(self):
        self.sleep()
        self.assertEqual(self.notified(), [])
        self.assertIsNone(self.state())

    def test_the_first_failure_of_a_run_notifies_once(self):
        for _ in range(3):
            self.sleep(fails=True)
        self.assertEqual(self.notified(), ["soc:display-subsystem|-22"])
        s = self.state()
        self.assertEqual((s["count"], s["dev"], s["errno"]), ("3", "soc:display-subsystem", "-22"))
        self.assertEqual(oct(os.stat(os.path.join(self.run_dir, "nightdrive-sleep.failed")).st_mode & 0o777), "0o644")

    def test_a_sleep_that_works_ends_the_run(self):
        self.sleep(fails=True)
        self.sleep()
        self.assertIsNone(self.state())
        self.sleep(fails=True, dev="f01ac0000.cio", errno=-16)
        self.assertEqual(self.notified(), ["soc:display-subsystem|-22", "f01ac0000.cio|-16"])

    def test_without_suspend_stats_it_stays_quiet(self):
        self.env["NIGHTDRIVE_SUSPEND_STATS"] = os.path.join(self.tmp.name, "missing")
        self.sleep()
        self.assertEqual(self.notified(), [])
        self.assertIsNone(self.state())
        self.assertFalse(os.path.exists(os.path.join(self.run_dir, "nightdrive-sleep.fails")))


if __name__ == "__main__":
    unittest.main()
