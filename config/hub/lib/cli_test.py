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


class TimerTest(unittest.TestCase):
    """systemctl disable removes the timer's link in ~/.config/systemd/user (link.sh's), so a plain `enable` by name
    found no unit after `timer off` (#3396). "on" enables it by the repo's file, which links it again."""

    def test_on_enables_the_repos_file_and_off_disables_by_name(self):
        from unittest import mock
        import cli
        calls = []
        ok = mock.Mock(returncode=0, stderr="")
        with mock.patch.dict(os.environ, {"NIGHTDRIVE_HUB_NO_TIMER": ""}), \
                mock.patch.object(cli.subprocess, "run", lambda cmd, **kw: calls.append(cmd) or ok):
            self.assertEqual(cli.timer(True), "on")
            self.assertEqual(cli.timer(False), "off")
        on, off = calls
        self.assertEqual(on[:4], ["systemctl", "--user", "enable", "--now"])
        self.assertTrue(os.path.isabs(on[4]) and os.path.isfile(on[4]), on[4])
        self.assertEqual(os.path.basename(on[4]), cli.TIMER)
        self.assertEqual(off, ["systemctl", "--user", "disable", "--now", cli.TIMER])


if __name__ == "__main__":
    unittest.main()
