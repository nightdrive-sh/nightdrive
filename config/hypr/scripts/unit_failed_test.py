#!/usr/bin/env python3
"""A notification when a service keeps failing (#3313): `python3 config/hypr/scripts/unit_failed_test.py`. The rules
(unit_failed.py) on their own, then `unit-failed UNIT` as its OnFailure= unit runs it, with journalctl, systemctl,
nmcli, systemd-run and notify-send stubbed: a throwaway home, no notification shows and nothing of systemd's is asked."""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import unit_failed as uf  # noqa: E402

CMD = os.path.join(HERE, "unit-failed")
UNIT = "nightdrive-test-fail.service"

STUBS = {
    # MESSAGE_ID=…: the unit's last success (UF_OK, Unix seconds; none when empty); otherwise its log, newest first
    "journalctl": """#!/bin/bash
if [[ $* == *MESSAGE_ID=* ]]; then
  [[ -n ${UF_OK:-} ]] && printf '{"__REALTIME_TIMESTAMP": "%s000000", "MESSAGE": "Finished"}\\n' "$UF_OK"
else
  echo '{"MESSAGE_ID": "be02cf6855d2428ba40df7e9d022f03d", "SYSLOG_IDENTIFIER": "systemd", "MESSAGE": "Failed to start"}'
  echo '{"SYSLOG_IDENTIFIER": "systemd", "MESSAGE": "test.service: Main process exited, code=exited"}'
  echo '{"SYSLOG_IDENTIFIER": "fail", "MESSAGE": "KeyError: default_reminder"}'
  echo '{"SYSLOG_IDENTIFIER": "fail", "MESSAGE": "Traceback (most recent call last):"}'
fi""",
    "systemctl": """#!/bin/bash
case "$*" in
  *"-p After"*) echo "${UF_AFTER:-basic.target}" ;;
  *"-p Description"*) echo "Test service" ;;
esac""",
    "nmcli": "#!/bin/bash\necho \"${UF_NET:-full}\"",
    # runs the notice here, as the unit of its own would
    "systemd-run": "#!/bin/bash\nwhile [[ $1 == -* ]]; do [[ $1 == -- ]] && { shift; break; }; shift; done\nexec \"$@\"",
    # keeps its arguments, then closes as if dismissed
    "notify-send": "#!/bin/bash\nprintf '%s\\n' \"$@\" >> \"$UF_NOTIFIED\"\necho ---- >> \"$UF_NOTIFIED\"",
}


class Rules(unittest.TestCase):
    def test_streak_counts_failures_in_a_row(self):
        e = None
        for i in range(uf.FAILS - 1):
            e = uf.record(e, 1000 + i * 60, None, True)
            self.assertFalse(uf.due(e, 1000 + i * 60, False))
        e = uf.record(e, 2000, None, True)
        self.assertEqual(e["count"], uf.FAILS)
        self.assertEqual(e["since"], 1000)
        self.assertTrue(uf.due(e, 2000, False))

    def test_success_in_between_starts_again(self):
        e = uf.record(uf.record(None, 1000, None, True), 1060, None, True)
        e = uf.record(e, 1200, 1100, True)        # finished well at 1100, after the last failure
        self.assertEqual((e["count"], e["since"]), (1, 1200))
        e = uf.record(e, 1260, 1100, True)        # the same old success doesn't reset it again
        self.assertEqual(e["count"], 2)

    def test_once_per_quiet_period(self):
        e = {"count": 50, "since": 0, "last": 5000, "notified": 4000}
        self.assertFalse(uf.due(e, 4000 + uf.QUIET - 1, False))
        self.assertTrue(uf.due(e, 4000 + uf.QUIET, False))

    def test_network_unit_offline_and_young_streak(self):
        e = uf.record(None, 1000, None, False)
        self.assertNotIn("count", e)               # offline: not counted, no streak started
        for t in (2000, 2300, 2600):
            e = uf.record(e, t, None, True)
        self.assertFalse(uf.due(e, 2600, True))   # three in a row, but not for NETWORK_AGE yet
        self.assertTrue(uf.due(e, 2000 + uf.NETWORK_AGE, True))
        self.assertTrue(uf.due(e, 2600, False))

    def test_prune_forgets_old_units(self):
        now = 10 * uf.FORGET
        state = {"old.service": {"count": 3, "last": now - uf.FORGET - 1},
                 "new.service": {"count": 1, "last": now - 60}}
        self.assertEqual(list(uf.prune(state, now)), ["new.service"])

    def test_message(self):
        now = time.time()
        s, b = uf.message(UNIT, {"count": 4, "since": now - 120}, now, "Test service", "KeyError: x")
        self.assertEqual(s, "Test service keeps failing")
        self.assertIn("Failed 4 times in a row since", b)
        self.assertIn("KeyError: x", b)
        self.assertIn(f"journalctl --user -u {UNIT}", b)


class Command(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        bindir = os.path.join(self.tmp.name, "bin")
        os.makedirs(bindir)
        for name, body in STUBS.items():
            path = os.path.join(bindir, name)
            with open(path, "w") as f:
                f.write(body)
            os.chmod(path, 0o755)
        self.notified = os.path.join(self.tmp.name, "notified")
        self.env = {"HOME": self.tmp.name, "PATH": bindir + ":/usr/bin:/bin", "UF_NOTIFIED": self.notified}
        self.state = os.path.join(self.tmp.name, ".local/state/nightdrive/unit-failed.json")

    def tearDown(self):
        self.tmp.cleanup()

    def run_cmd(self, *args, **env):
        p = subprocess.run([sys.executable, "-I", CMD, *args], env={**self.env, **env}, capture_output=True,
                           text=True, timeout=30)
        self.assertEqual(p.returncode, 0, p.stderr)
        return p.stdout

    def notices(self, wait=True):
        """The notifications sent so far (each its notify-send argv). The notice runs detached: wait for it."""
        end = time.time() + (10 if wait else 0.5)
        while time.time() < end and not os.path.exists(self.notified):
            time.sleep(0.05)
        try:
            with open(self.notified) as f:
                text = f.read()
        except OSError:
            return []
        return [n.strip("\n").split("\n") for n in text.split("----\n") if n.strip()]

    def test_one_notice_for_a_unit_failing_every_minute(self):
        for _ in range(uf.FAILS - 1):
            self.assertIn("in a row", self.run_cmd(UNIT))
        self.assertEqual(self.notices(wait=False), [])
        self.assertIn("notified", self.run_cmd(UNIT))
        notes = self.notices()
        self.assertEqual(len(notes), 1)
        argv = notes[0]
        self.assertIn("Test service keeps failing", argv)
        text = "\n".join(argv)
        self.assertIn(f"Failed {uf.FAILS} times in a row", text)
        self.assertIn("KeyError: default_reminder", text)   # its own last line, not systemd's
        self.assertIn(f"journalctl --user -u {UNIT}", text)
        self.assertIn("default=Show the log", argv)
        for _ in range(5):                                   # and none more today
            self.assertNotIn("notified", self.run_cmd(UNIT))
        time.sleep(0.3)
        self.assertEqual(len(self.notices()), 1)
        units = json.loads(self.run_cmd("list", "--json"))["units"]
        self.assertEqual([(u["unit"], u["count"]) for u in units], [(UNIT, uf.FAILS + 5)])

    def test_success_resets_the_count(self):
        self.run_cmd(UNIT)
        self.run_cmd(UNIT)
        ok = str(int(time.time()) + 1)                       # it ran well after those two
        time.sleep(1.1)
        self.assertIn(": 1 in a row", self.run_cmd(UNIT, UF_OK=ok))
        self.assertEqual(self.notices(wait=False), [])

    def test_sync_offline_never_notifies(self):
        for _ in range(10):
            self.assertIn("offline", self.run_cmd(UNIT, UF_AFTER="network-online.target basic.target", UF_NET="none"))
        self.assertEqual(self.notices(wait=False), [])
        self.assertEqual(json.loads(self.run_cmd("list", "--json"))["units"], [])

    def test_sync_online_notifies_once_the_streak_is_old(self):
        net = {"UF_AFTER": "network-online.target", "UF_NET": "full"}
        for _ in range(uf.FAILS + 2):
            self.run_cmd(UNIT, **net)
        self.assertEqual(self.notices(wait=False), [])        # failing, but only for seconds
        with open(self.state) as f:
            state = json.load(f)
        state[UNIT]["since"] -= uf.NETWORK_AGE
        with open(self.state, "w") as f:
            json.dump(state, f)
        self.assertIn("notified", self.run_cmd(UNIT, **net))
        self.assertEqual(len(self.notices()), 1)

    def test_list_when_nothing_fails(self):
        self.assertIn("No Nightdrive service is failing", self.run_cmd("list"))
        self.assertEqual(json.loads(self.run_cmd("list", "--json")), {"units": []})

    def test_usage(self):
        p = subprocess.run([sys.executable, "-I", CMD], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("unit-failed UNIT", p.stderr)


if __name__ == "__main__":
    unittest.main()
