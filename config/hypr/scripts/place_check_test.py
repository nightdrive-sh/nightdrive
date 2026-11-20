#!/usr/bin/env python3
"""`places check` (#3277): `python3 config/hypr/scripts/place_check_test.py`. The state kept over checks, the one leave
timer, and the events sent only to a command that knows `event`. A throwaway HOME (the real places.json is never
touched), the Wi-Fi from NIGHTDRIVE_PLACES_WIFI, and no systemd: the timer and the commands are replaced."""

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = tempfile.mkdtemp(prefix="place-check-test-")
os.environ["HOME"] = HOME
sys.path.insert(0, HERE)
import place_check  # noqa: E402
from place_rules import LEAVE_HOLD  # noqa: E402

PLACES = os.path.join(HOME, ".config/nightdrive/places.json")


class Fake:
    def __init__(self):
        self.armed, self.disarmed, self.told = [], [], []

    def arm(self, at):
        self.armed.append(at)
        return f"{place_check.UNIT}-{int(at)}"

    def disarm(self, unit):
        self.disarmed.append(unit)

    def tell(self, kind, name):
        self.told.append((kind, name))
        return [{"command": ["remind", "event", kind, name], "ok": True, "skipped": None}]

    def check(self, wifi, now, event=None):
        return place_check.check(event, now=now, wifi=wifi, arm=self.arm, disarm=self.disarm, tell=self.tell)


def write_places(rows):
    os.makedirs(os.path.dirname(PLACES), exist_ok=True)
    with open(PLACES, "w") as f:
        json.dump({"places": rows}, f)


class Check(unittest.TestCase):
    def setUp(self):
        for p in (PLACES, place_check.state_path()):
            if os.path.exists(p):
                os.remove(p)
        write_places([{"name": "work", "wifi": ["Feature"]}, {"name": "home", "wifi": ["Koti"]}])
        self.f = Fake()

    def test_state_kept_between_checks(self):
        r = self.f.check(["Koti"], 1000)
        self.assertEqual((r["here"], r["events"]), (["home"], []))
        with open(place_check.state_path()) as fh:
            self.assertTrue(json.load(fh)["places"]["home"]["here"])
        self.f.check([], 2000)
        r = self.f.check(["Feature"], 9000)
        self.assertEqual(r["events"], [{"event": "arrive", "place": "work"}, {"event": "leave", "place": "home"}])
        self.assertEqual(self.f.told, [("arrive", "work"), ("leave", "home")])

    def test_one_leave_timer_rearmed_only_on_change(self):
        self.f.check(["Feature"], 1000)
        r = self.f.check([], 2000)
        self.assertEqual((r["next_check"], self.f.armed), (2000 + LEAVE_HOLD, [2000 + LEAVE_HOLD]))
        self.f.check([], 2050)                       # another check meanwhile: the same timer stays
        self.assertEqual((self.f.armed, self.f.disarmed), ([2000 + LEAVE_HOLD], []))
        r = self.f.check([], 2000 + LEAVE_HOLD)      # the timer's own check: left, nothing more to wait for
        self.assertEqual(r["events"], [{"event": "leave", "place": "work"}])
        self.assertEqual(self.f.disarmed, [f"{place_check.UNIT}-{2000 + LEAVE_HOLD}"])
        self.assertEqual(r["next_check"], None)

    def test_back_in_time_disarms(self):
        self.f.check(["Feature"], 1000)
        self.f.check([], 2000)
        r = self.f.check(["Feature"], 2060)
        self.assertEqual((r["events"], r["next_check"]), ([], None))
        self.assertEqual(self.f.disarmed, [f"{place_check.UNIT}-{2000 + LEAVE_HOLD}"])

    def test_sleep_and_wake(self):
        self.f.check(["Feature"], 1000)
        self.assertEqual(self.f.check(["Feature"], 2000, "sleep")["events"], [])
        r = self.f.check(["Feature"], 2000 + 3 * 86400, "wake")
        self.assertEqual(r["events"], [{"event": "arrive", "place": "work"}])

    def test_no_places_no_state_trouble(self):
        os.remove(PLACES)
        r = self.f.check(["Feature"], 1000)
        self.assertEqual((r["here"], r["events"], r["next_check"]), ([], [], None))

    def test_text(self):
        self.f.check(["Feature"], 1000)
        r = self.f.check([], 2000)
        self.assertIn("Here: work", place_check.text(r))
        self.assertIn("Checks again at", place_check.text(r))


def script(folder, name, body):
    p = os.path.join(folder, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body)
    os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)


class Tell(unittest.TestCase):
    def test_only_commands_that_know_event(self):
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "ran")
            # remind as it is before #3279 (no event in its choices); schedule with one, logging what it got
            script(d, "remind", 'echo "usage: nightdrive remind [-h] {add,list,show,cancel,fire,restore} ..."\n'
                                f'echo "$@" >> {log}\n')
            script(d, "schedule", 'case "$1" in --help) echo "usage: x [-h] {add,list,event,woke} ..."; exit 0;; esac\n'
                                  f'echo "$@" >> {log}\n')
            old = place_check.SCRIPTS
            place_check.SCRIPTS = d
            try:
                ran = place_check.tell("arrive", "work")
            finally:
                place_check.SCRIPTS = old
            with open(log) as f:
                got = f.read().splitlines()
        self.assertEqual(got, ["--help", "event arrive work"])   # remind only asked for its usage
        self.assertEqual(ran, [{"command": ["remind", "event", "arrive", "work"], "ok": False,
                                "skipped": "no event command"},
                               {"command": ["schedule", "event", "arrive", "work"], "ok": True, "skipped": None}])

    def test_failing_command_is_reported_not_raised(self):
        with tempfile.TemporaryDirectory() as d:
            script(d, "remind", 'case "$1" in --help) echo "{add,event}";; *) echo no >&2; exit 3;; esac\n')
            script(d, "schedule", 'echo "{add}"\n')
            old = place_check.SCRIPTS
            place_check.SCRIPTS = d
            try:
                ran = place_check.tell("leave", "home")
            finally:
                place_check.SCRIPTS = old
        self.assertEqual([r["ok"] for r in ran], [False, False])
        self.assertEqual([r["skipped"] for r in ran], [None, "no event command"])


class Command(unittest.TestCase):
    def test_places_check_json(self):
        write_places([{"name": "work", "wifi": ["Feature"]}])
        if os.path.exists(place_check.state_path()):
            os.remove(place_check.state_path())
        env = dict(os.environ, HOME=HOME, NIGHTDRIVE_PLACES_WIFI="Feature\n")
        p = subprocess.run([os.path.join(HERE, "places"), "check", "--wake", "--json"],
                           capture_output=True, text=True, env=env)
        self.assertEqual(p.returncode, 0, p.stderr)
        r = json.loads(p.stdout)
        self.assertEqual((r["event"], r["wifi"], r["here"], r["events"], r["next_check"]),
                         ("wake", ["Feature"], ["work"], [], None))


if __name__ == "__main__":
    unittest.main()
