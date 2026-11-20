#!/usr/bin/env python3
"""schedule's events and missed times (#3149): `python3 config/hypr/scripts/schedule_events_test.py`. wake and login
rows, a time that comes under the lock waiting for the unlock, the first unlock after waking running wake's rows, and a
login that runs what is under LATE_HOURS late and asks about older ones (Run / Skip). systemd, the lock and the
notifications are stubbed: a start now runs the row's fire --now in this process."""

import importlib.machinery
import importlib.util
import json
import os
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

HOUR = 3600


class Stubbed(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.locked = False
        self.answer = ""
        self.armed, self.ran, self.notes, self.asked, self.started, self.disarmed = [], [], [], [], [], []
        self.timer_up = set()
        self.bodies = []

        def start_now(rid):   # as systemd-run would, but here and at once
            self.started.append(rid)
            schedule.cmd_fire(types.SimpleNamespace(id=rid, now=True))
            return True

        def notify(rid, summary, body="", pinned=False, actions=()):
            self.notes.append(summary)
            self.bodies.append(body)
            return self.answer if actions else ""

        for name, stub in [("STATE", os.path.join(self.dir.name, "schedule.json")),
                           ("arm", lambda r: (self.armed.append(r["id"]), (True, ""))[1]),
                           ("disarm", self.disarmed.append),
                           ("screen_locked", lambda: self.locked),
                           ("start_now", start_now),
                           ("notify", notify),
                           ("run_command", lambda rid, line: (self.ran.append(line), (0, ""))[1])]:
            patcher = mock.patch.object(schedule, name, stub)
            patcher.start()
            self.addCleanup(patcher.stop)
        # Every word a program: these are about commands, whatever this machine's PATH has (schedule_claude_test.py
        # tells commands and messages apart)
        patcher = mock.patch.object(schedule.claude, "is_command", lambda word: True)
        patcher.start()
        self.addCleanup(patcher.stop)
        for target, name, stub in [(schedule.timers, "armed", lambda unit: unit in self.timer_up),
                                   (schedule.event_runs, "WOKE", os.path.join(self.dir.name, "woke")),
                                   (schedule.event_runs, "ask_later", lambda s, rid: self.asked.append(rid))]:
            patcher = mock.patch.object(target, name, stub)
            patcher.start()
            self.addCleanup(patcher.stop)

    def add(self, when, command, start=None):
        schedule.cmd_add(types.SimpleNamespace(json=True, when=when, command=[command], from_=start))
        return self.rows()[-1]["id"]

    def rows(self):
        try:
            with open(schedule.STATE) as f:
                return json.load(f)["commands"]
        except FileNotFoundError:
            return []

    def put(self, *rows):
        """Rows as a past session left them (times in the past can't be added)."""
        with open(schedule.STATE, "w") as f:
            json.dump({"commands": list(rows)}, f)

    def call(self, name, **kw):
        getattr(schedule, "cmd_" + name)(types.SimpleNamespace(**kw))



class Events(Stubbed):
    def test_events_need_no_timer_and_list_last(self):
        self.add("wake", "open-pm")
        self.add("login", "make")
        self.add("10", "echo soon")
        self.assertEqual(len(self.armed), 1)
        with mock.patch("builtins.print") as out:
            self.call("list", json=True)
        listed = json.loads(out.call_args[0][0])["commands"]
        self.assertEqual([c["when"] for c in listed], ["time", "wake", "login"])
        self.assertIsNone(listed[1]["at"])
        self.assertEqual({c["state"] for c in listed}, {"waiting"})

    def test_time_under_the_lock_waits_for_the_unlock(self):
        rid = self.add("1", "make")
        self.locked = True
        self.call("fire", id=rid)
        self.assertEqual(self.ran, [])
        self.assertEqual(self.rows()[0]["state"], "unlock")
        self.locked = False
        self.call("unlocked")
        self.call("unlocked")   # a second unlock runs nothing again
        self.assertEqual(self.ran, ["make"])
        self.assertEqual(self.rows(), [])

    def test_wake_runs_at_the_first_unlock_after_waking(self):
        self.add("wake", "open-pm")
        self.add("login", "make")
        self.call("unlocked")   # an unlock without a sleep before it
        self.assertEqual(self.ran, [])
        self.locked = True
        self.call("woke")
        self.assertEqual(self.ran, [])
        self.locked = False
        self.call("unlocked")
        self.assertEqual(self.ran, ["open-pm"])
        self.assertEqual([r["on"] for r in self.rows()], ["login"])
        self.assertFalse(os.path.exists(schedule.event_runs.WOKE))

    def test_wake_without_a_lock_runs_at_once(self):
        self.add("wake", "open-pm")
        self.call("woke")
        self.assertEqual(self.ran, ["open-pm"])

    def test_login_runs_late_ones_and_asks_about_old_ones(self):
        now = time.time()
        self.put({"id": "late", "at": now - 11 * HOUR, "command": "late"},
                 {"id": "old", "at": now - 13 * HOUR, "command": "old"},
                 {"id": "slept", "at": now - 2 * HOUR, "command": "slept", "state": "unlock"},
                 {"id": "soon", "at": now + HOUR, "command": "soon"},
                 {"id": "up", "at": now + HOUR, "command": "up"},
                 {"id": "login", "on": "login", "added": now - HOUR, "command": "at-login"},
                 {"id": "wake", "on": "wake", "added": now - HOUR, "command": "on-wake"})
        self.timer_up.add(schedule.UNIT + "up")
        with open(schedule.event_runs.WOKE, "w"):
            pass
        self.call("restore")
        self.assertEqual(sorted(self.ran), ["at-login", "late", "slept"])
        self.assertEqual(self.asked, ["old"])
        self.assertEqual(self.armed, ["soon"])   # "up" still has its timer
        left = {r["id"]: r.get("state", "waiting") for r in self.rows()}
        self.assertEqual(left, {"old": "missed", "soon": "waiting", "up": "waiting", "wake": "waiting"})
        self.assertFalse(os.path.exists(schedule.event_runs.WOKE))   # a wake before the logout isn't this session's

    def test_missed_asks_run_or_skip(self):
        old = time.time() - 20 * HOUR
        self.put({"id": "a", "at": old, "command": "a", "state": "missed"},
                 {"id": "b", "at": old, "command": "b", "state": "missed"},
                 {"id": "c", "at": old, "command": "c", "state": "missed"})
        self.answer = "run"
        self.call("ask", id="a")
        self.answer = "skip"
        self.call("ask", id="b")
        self.answer = ""        # dismissed: it stays, missed
        self.call("ask", id="c")
        self.assertEqual(self.ran, ["a"])
        self.assertEqual([(r["id"], r["state"]) for r in self.rows()], [("c", "missed")])
        self.assertIn("Missed: c", self.notes)
        self.call("restore")    # the next login asks again, runs nothing
        self.assertEqual((self.ran, self.asked), (["a"], ["c"]))

    def test_run_now_whatever_it_waits_for(self):
        rid = self.add("wake", "open-pm")
        self.call("run", id=rid)
        self.assertEqual(self.ran, ["open-pm"])
        self.assertEqual(self.rows(), [])

    def test_a_late_run_says_when_it_was_due(self):
        self.put({"id": "x", "at": time.time() - HOUR, "command": "make"})
        self.call("fire", id="x", now=True)
        self.assertEqual((self.notes[0], self.ran), ("Running: make", ["make"]))
        self.assertTrue(self.bodies[0].startswith("Was due at "))


class Places(Stubbed):
    """arrive PLACE and leave PLACE (#3278): places.json in a throwaway home, events as `places check` sends them."""

    def setUp(self):
        super().setUp()
        home = os.path.join(self.dir.name, "home")
        os.makedirs(os.path.join(home, ".config", "nightdrive"))
        with open(os.path.join(home, ".config", "nightdrive", "places.json"), "w") as f:
            json.dump({"places": [{"name": "work", "wifi": ["Office"]}, {"name": "home", "wifi": ["Den"]}]}, f)
        patcher = mock.patch.dict(os.environ, {"HOME": home})
        patcher.start()
        self.addCleanup(patcher.stop)

    def listed(self):
        with mock.patch("builtins.print") as out:
            self.call("list", json=True)
        return json.loads(out.call_args[0][0])["commands"]

    def event(self, kind="arrive", place="work"):
        with mock.patch("builtins.print") as out:
            self.call("event", kind=kind, place=place, json=True)
        return json.loads(out.call_args[0][0])

    def test_added_with_its_place_and_its_week(self):
        rid = self.add("arrive Work", "make", start="05:00")
        r = self.rows()[0]
        self.assertEqual((r["on"], r["place"]), ("arrive", "work"))
        self.assertEqual(self.armed, [rid])   # the week's timer, not a run's
        c = self.listed()[0]
        self.assertEqual((c["when"], c["label"], c["place"], c["clock"]), ("arrive", "arrive work", "work", None))
        self.assertIn("T05:00:00", c["from"])
        with mock.patch("builtins.print") as out:
            self.call("list", json=False)
        self.assertIn("on arriving at work, not before 05:00", out.call_args_list[0][0][0])

    def test_unknown_place_and_from_on_a_time_refused(self):
        for when, start in (("arrive gym", None), ("leave", None), ("15", "05:00"), ("arrive work", "soon")):
            with self.assertRaises(SystemExit), mock.patch("sys.stderr"):
                self.add(when, "make", start=start)
        self.assertEqual(self.rows(), [])

    def test_typed_unquoted(self):
        a = schedule.parse_add(["arrive", "work", "--from", "05:00", "make", "--json"])
        self.assertEqual((a.when, a.from_, a.command), ("arrive work", "05:00", ["make", "--json"]))
        a = schedule.parse_add(["--from=8h", "leave", "home", "--", "make"])
        self.assertEqual((a.when, a.from_, a.command), ("leave home", "8h", ["make"]))

    def test_its_own_event_runs_it_once(self):
        rid = self.add("arrive work", "make")
        self.add("leave work", "lock-vpn")
        self.assertEqual(self.event("arrive", "home")["due"], [])
        self.assertEqual(self.event("arrive", "WORK")["due"], [rid])
        self.assertEqual(self.event("arrive", "work")["due"], [])   # once
        self.assertEqual(self.ran, ["make"])
        self.assertIn(rid, self.disarmed)                           # its week's timer goes
        self.assertEqual([r["on"] for r in self.rows()], ["leave"])

    def test_not_before_its_from(self):
        self.add("arrive work", "make", start="2h")
        self.assertEqual(self.event()["due"], [])
        later = time.time() + 3 * HOUR
        with mock.patch.object(schedule.event_runs.time, "time", lambda: later):
            self.event()
        self.assertEqual(self.ran, ["make"])

    def test_under_the_lock_it_waits_for_the_unlock(self):
        rid = self.add("arrive work", "make")
        self.locked = True
        self.assertEqual(self.event()["unlock"], [rid])
        self.assertEqual(self.ran, [])
        self.locked = False
        self.call("unlocked")
        self.assertEqual(self.ran, ["make"])

    def test_a_week_without_it_asks(self):
        rid = self.add("arrive work", "make")
        self.call("expire", id=rid)                  # an early call does nothing
        self.assertEqual(self.notes, [])
        r = self.rows()[0]
        r["added"] -= 8 * 24 * HOUR
        self.put(r)
        self.answer = ""                             # dismissed: missed, and the arrival still runs it
        self.call("expire", id=rid)
        self.assertEqual(self.notes, ["You didn't arrive at work: make"])
        self.assertEqual(self.rows()[0]["state"], "missed")
        self.event()
        self.assertEqual(self.ran, ["make"])

    def test_a_week_without_it_run_or_skip(self):
        old = time.time() - 8 * 24 * HOUR
        self.put({"id": "a", "on": "leave", "place": "work", "added": old, "command": "a"},
                 {"id": "b", "on": "leave", "place": "work", "added": old, "command": "b"})
        self.answer = "run"
        self.call("expire", id="a")
        self.answer = "skip"
        self.call("expire", id="b")
        self.assertEqual((self.ran, self.rows()), (["a"], []))
        self.assertEqual(self.notes[0], "You didn't leave work: a")

    def test_login_arms_the_week_asks_past_ones_runs_what_came_locked(self):
        now = time.time()
        self.put({"id": "wait", "on": "arrive", "place": "work", "added": now - HOUR, "command": "wait"},
                 {"id": "old", "on": "arrive", "place": "work", "added": now - 8 * 24 * HOUR, "command": "old"},
                 {"id": "came", "on": "leave", "place": "home", "added": now - HOUR, "command": "came",
                  "state": "unlock"})
        self.call("restore")
        self.assertEqual(self.ran, ["came"])
        self.assertEqual(self.asked, ["old"])
        self.assertEqual(self.armed, ["wait"])
        self.assertEqual({r["id"]: r.get("state") for r in self.rows()}, {"wait": None, "old": "missed"})

    def test_login_and_its_arrival_side_by_side_run_it_once(self):
        """autostart.lua starts `schedule restore` and `places check --wake` together: either order starts it once,
        and a start that came twice still runs it once."""
        for steps in (("restore", "event"), ("event", "restore")):
            self.ran.clear()
            rid = self.add("arrive work", "make")
            starts = []
            with mock.patch.object(schedule, "start_now", starts.append):
                for step in steps:
                    self.call("restore") if step == "restore" else self.event()
            self.assertEqual(starts, [rid], steps)
            for _ in range(2):
                schedule.cmd_fire(types.SimpleNamespace(id=rid, now=True))
            self.assertEqual((self.ran, self.rows()), (["make"], []), steps)


if __name__ == "__main__":
    unittest.main(verbosity=1, argv=sys.argv[:1])
