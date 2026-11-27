#!/usr/bin/env python3
"""spawn() reaps its child (#3657): `python3 config/hypr/scripts/spawn_test.py`."""
import os
import subprocess
import sys
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from spawn import spawn  # noqa: E402


def state(pid):
    """The child's state letter from /proc (Z for a zombie), or None once it is gone."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            return f.read().rsplit(")", 1)[1].split()[0]
    except FileNotFoundError:
        return None


@unittest.skipUnless(os.path.isdir("/proc/self"), "needs /proc")
class SpawnTest(unittest.TestCase):
    def wait_gone(self, pid, timeout=5):
        end = time.monotonic() + timeout
        while state(pid) is not None and time.monotonic() < end:
            time.sleep(0.02)
        return state(pid)

    def test_child_is_reaped_without_wait(self):
        p = spawn(["true"], stdout=subprocess.DEVNULL)
        self.assertIsNone(self.wait_gone(p.pid), "the exited child stayed as a zombie")
        self.assertEqual(p.returncode, 0)

    def test_bare_popen_leaves_a_zombie(self):
        # The control: what spawn() fixes. Popen's own reaping only runs at the next Popen, so none follows here.
        p = subprocess.Popen(["true"])
        time.sleep(0.3)
        self.assertEqual(state(p.pid), "Z")
        p.wait()

    def test_returns_at_once(self):
        t = time.monotonic()
        p = spawn(["sleep", "1"])
        self.assertLess(time.monotonic() - t, 0.5)
        self.assertIsNone(self.wait_gone(p.pid))


if __name__ == "__main__":
    unittest.main()
