"""`nightdrive hub` (cli.py) around the sync: joining, leaving, a computer not joined, and the status's words.

    python3 config/hub/lib/cli_test.py
"""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import devices  # noqa: E402
import testhub  # noqa: E402


class CliTest(unittest.TestCase):
    def setUp(self):
        self.hub = testhub.TestHub()
        self.d = devices.Device("cli")

    def tearDown(self):
        self.d.close()
        self.hub.stop()

    def test_not_joined(self):
        self.assertEqual(self.d.run("sync", "--quiet").returncode, 0)     # the timer of a computer that left
        r = self.d.run("sync", ok=False)
        self.assertEqual(r.returncode, 1)
        self.assertIn("join", r.stderr)
        st = self.d.status()
        self.assertEqual((st["joined"], st["pending"]["tasks"]), (False, {"changed": 0, "deleted": 0}))
        self.assertIn("Not joined", self.d.run("status").stdout)

    def test_join_says_what_it_did_and_leaves_the_timer_alone(self):
        self.d.add("home", "Task")
        out = self.d.run("join", self.hub.url + "/").stdout
        self.assertIn("Joined the Hub at %s" % self.hub.url, out)
        self.assertIn("Tasks: 2 sent", out)
        self.assertIn("left alone", out)        # NIGHTDRIVE_HUB_NO_TIMER: a test never starts the real timer
        with open(os.path.join(self.d.env["XDG_CONFIG_HOME"], "nightdrive", "hub.json")) as f:
            self.assertEqual(json.load(f), {"url": self.hub.url, "server": self.hub.mem.server_id})
        self.assertIn("Tasks: up to date", self.d.run("sync").stdout)
        self.assertIn("Last sync: 20", self.d.run("status").stdout)

    def test_join_a_hub_out_of_reach_or_not_a_hub(self):
        url = self.hub.url
        self.hub.stop()
        r = self.d.run("join", url, ok=False)
        self.assertEqual(r.returncode, 1)
        self.assertIn("Can't join", r.stderr)
        self.assertIn("http(s)://", self.d.run("join", "hub.example", ok=False).stderr)
        self.hub = testhub.TestHub()        # tearDown stops it

    def test_leave_keeps_the_files(self):
        t = self.d.add("home", "Task")
        self.d.run("join", self.hub.url)
        self.assertIn("Every file stays", self.d.run("leave").stdout)
        self.assertIsNotNone(self.d.read(t))
        self.assertFalse(self.d.status()["joined"])

    def test_status_counts_what_waits(self):
        t = self.d.add("home", "Task")
        self.d.run("join", self.hub.url)
        self.d.write(t, devices.vtodo("x", "Edited"))
        self.d.add("home", "New")
        self.assertIn("2 changes to send", self.d.run("status").stdout)


if __name__ == "__main__":
    unittest.main()
