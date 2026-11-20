#!/usr/bin/env python3
"""remind's events (#3279): `python3 config/hypr/scripts/remind_events_test.py`. wake, login, arrive PLACE and leave
PLACE as WHEN, --from, a reminder that comes under the lock waiting for the unlock, the first unlock after waking
telling wake's, a week not seen told anyway ("Didn't arrive at work"), and each told once whoever comes first (a login's
restore and its `places check --wake`, side by side). places.json is in a throwaway home; systemd, the lock and the
banner are stubbed: nothing here starts a timer or shows anything."""

import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
import threading
import time
import types
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("remind", os.path.join(HERE, "remind"))
remind = importlib.util.module_from_spec(importlib.util.spec_from_loader("remind", loader))
loader.exec_module(remind)

DAY = 86400


class Stubbed(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.locked = False
        self.armed, self.disarmed, self.told, self.active = [], [], [], set()
        home = os.path.join(self.dir.name, "home")
        os.makedirs(os.path.join(home, ".config", "nightdrive"))
        with open(os.path.join(home, ".config", "nightdrive", "places.json"), "w") as f:
            json.dump({"places": [{"name": "work", "wifi": ["Office"]}, {"name": "home", "wifi": ["Den"]}]}, f)
        patches = [mock.patch.dict(os.environ, {"HOME": home}),
                   mock.patch.object(remind.event_runs, "WOKE", os.path.join(self.dir.name, "woke"))]
        for name, stub in [("STATE", os.path.join(self.dir.name, "reminders.json")),
                           ("arm", lambda r: (self.armed.append(r["id"]), (True, ""))[1]),
                           ("disarm", self.disarmed.append),
                           ("armed", lambda rid: rid in self.active),
                           ("screen_locked", lambda: self.locked),
                           ("tell", lambda rid, message, note, tries=1: self.told.append((message, note)))]:
            patches.append(mock.patch.object(remind, name, stub))
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def call(self, name, **kw):
        with mock.patch("builtins.print") as out:
            getattr(remind, "cmd_" + name)(types.SimpleNamespace(**kw))
        return json.loads(out.call_args[0][0]) if kw.get("json") and out.call_args else None

    def add(self, when, message, start=None):
        return self.call("add", json=True, when=when, message=[message], from_=start)

    def rows(self):
        try:
            with open(remind.STATE) as f:
                return json.load(f)["reminders"]
        except FileNotFoundError:
            return []

    def put(self, *rows):
        with open(remind.STATE, "w") as f:
            json.dump({"reminders": list(rows)}, f)

    def messages(self):
        return [t[0] for t in self.told]


class Add(Stubbed):
    def test_events_as_when(self):
        for when, kind, place in [("wake", "wake", None), ("login", "login", None),
                                  ("arrive WORK", "arrive", "work"), ("leave home", "leave", "home")]:
            out = self.add(when, "Tea")
            self.assertEqual((out["when"], out["place"], out["at"], out["clock"]), (kind, place, None, None), when)
            self.assertEqual(out["label"], kind + (" " + place if place else ""))
        # only an arrival and a leaving have a timer: their week
        ids = {r["on"]: r["id"] for r in self.rows()}
        self.assertEqual(self.armed, [ids["arrive"], ids["leave"]])

    def test_unknown_place_and_from_without_event_refused(self):
        for when, start in [("arrive office", None), ("arrive", None), ("wake work", None), ("15", "05:00"),
                            ("arrive work", "yesterday")]:
            with self.assertRaises(SystemExit), mock.patch("sys.stderr"):
                self.add(when, "x", start)
        self.assertEqual(self.rows(), [])

    def test_from_keeps_an_early_arrival(self):
        out = self.add("arrive work", "Write the dialogue", "05:00")
        self.assertIsNotNone(out["from"])
        start = self.rows()[0]["from"]
        with mock.patch("time.time", return_value=start - 60):
            self.call("event", json=True, kind="arrive", place="work")
        self.assertEqual(self.told, [])
        with mock.patch("time.time", return_value=start + 60):
            out = self.call("event", json=True, kind="arrive", place="Work")
        self.assertEqual(self.messages(), ["Write the dialogue"])
        self.assertEqual(self.told[0][1], "On arriving at work")
        self.assertEqual(len(out["told"]), 1)
        self.assertEqual(self.rows(), [])

    def test_unquoted_place(self):
        self.assertEqual(remind.join_place(["add", "arrive", "work", "Tea"]), ["add", "arrive work", "Tea"])
        self.assertEqual(remind.join_place(["add", "--from", "05:00", "leave", "home", "Go"]),
                         ["add", "--from", "05:00", "leave home", "Go"])
        self.assertEqual(remind.join_place(["add", "15", "arrive", "soon"]), ["add", "15", "arrive", "soon"])

    def test_command_line(self):
        """As typed: --json before WHEN, the place unquoted, --from anywhere. wake has no timer: nothing is armed."""
        import subprocess
        run = lambda *args: subprocess.run([os.path.join(HERE, "remind"), *args], capture_output=True, text=True,
                                           env={**os.environ, "XDG_RUNTIME_DIR": self.dir.name})
        out = json.loads(run("--json", "wake", "Stretch", "--from", "05:00").stdout)
        self.assertEqual((out["when"], out["message"]), ("wake", "Stretch"))
        self.assertEqual(json.loads(run("--json").stdout)["reminders"][0]["id"], out["id"])
        self.assertIn("No place called 'office'", run("arrive", "office", "x").stderr)

    def test_list_times_first_then_events(self):
        self.add("arrive work", "B")
        self.add("wake", "A")
        self.add("30", "C")
        out = self.call("list", json=True)["reminders"]
        self.assertEqual([r["message"] for r in out], ["C", "A", "B"])
        self.assertEqual([r["when"] for r in out], ["time", "wake", "arrive"])
        self.assertEqual({r["state"] for r in out}, {"waiting"})


class Events(Stubbed):
    def test_arrival_tells_its_place_only_once(self):
        self.add("arrive work", "Work")
        self.add("arrive home", "Home")
        self.add("leave work", "Left")
        self.call("event", json=True, kind="arrive", place="work")
        self.call("event", json=True, kind="arrive", place="work")
        self.assertEqual(self.messages(), ["Work"])
        self.assertEqual(sorted(r["message"] for r in self.rows()), ["Home", "Left"])

    def test_under_the_lock_waits_for_the_unlock(self):
        self.add("leave work", "Buy milk")
        self.locked = True
        out = self.call("event", json=True, kind="leave", place="work")
        self.assertEqual((out["told"], len(out["unlock"])), ([], 1))
        self.assertEqual(self.told, [])
        listed = self.call("list", json=True)["reminders"]
        self.assertEqual(listed[0]["state"], "unlock")
        self.call("event", json=True, kind="leave", place="work")   # leaving again doesn't tell it twice
        self.locked = False
        self.call("unlocked")
        self.call("unlocked")
        self.assertEqual(self.told, [("Buy milk", "On leaving work")])

    def test_wake_at_the_first_unlock_after_waking(self):
        self.add("wake", "Stretch")
        self.call("unlocked")                     # an unlock with no sleep before it
        self.assertEqual(self.told, [])
        self.locked = True
        self.call("woke")
        self.assertEqual(self.told, [])
        self.locked = False
        self.call("unlocked")
        self.assertEqual(self.told, [("Stretch", "On waking")])

    def test_wake_with_no_lock_now(self):
        self.add("wake", "Stretch")
        self.call("woke")
        self.assertEqual(self.messages(), ["Stretch"])

    def test_week_not_seen_comes_anyway(self):
        self.add("arrive work", "Characters")
        rid = self.rows()[0]["id"]
        self.call("expire", id=rid)                # not its week yet (a stray run): nothing
        self.assertEqual(self.told, [])
        with mock.patch("time.time", return_value=time.time() + 7 * DAY + 5):
            self.call("expire", id=rid)
        self.assertEqual(self.messages(), ["Characters"])
        self.assertEqual(self.told[0][1], "Didn't arrive at work in a week")
        self.assertEqual(self.rows(), [])

    def test_week_under_the_lock_waits_and_keeps_its_note(self):
        self.add("leave home", "Keys")
        rid = self.rows()[0]["id"]
        self.locked = True
        with mock.patch("time.time", return_value=time.time() + 7 * DAY + 5):
            self.call("expire", id=rid)
        self.assertEqual(self.told, [])
        self.locked = False
        self.call("unlocked")
        self.assertTrue(self.told[0][1].startswith("Didn't leave home"), self.told)

    def test_cancel_takes_its_timer(self):
        self.add("arrive work", "x")
        rid = self.rows()[0]["id"]
        self.call("cancel", json=True, id=rid)
        self.assertEqual(self.disarmed, [rid])
        self.call("event", json=True, kind="arrive", place="work")
        self.assertEqual(self.told, [])


class Login(Stubbed):
    def test_restore(self):
        now = int(time.time())
        self.put({"id": "t1", "at": now - 60, "message": "Missed time"},
                 {"id": "t2", "at": now + 600, "message": "Later"},
                 {"id": "l1", "on": "login", "added": now - 99, "message": "At login"},
                 {"id": "l2", "on": "login", "added": now - 99, "from": now + 3600, "message": "Not yet"},
                 {"id": "w1", "on": "wake", "added": now - 99, "message": "Wake"},
                 {"id": "a1", "on": "arrive", "place": "work", "added": now - 99, "message": "Arrive"},
                 {"id": "a2", "on": "arrive", "place": "work", "added": now - 8 * DAY, "message": "Old"},
                 {"id": "u1", "on": "leave", "place": "home", "added": now - 99, "state": "unlock", "message": "Under"})
        self.call("restore")
        self.assertEqual(sorted(self.messages()), ["At login", "Missed time", "Old", "Under"])
        self.assertEqual(sorted(r["id"] for r in self.rows()), ["a1", "l2", "t2", "w1"])
        self.assertEqual(sorted(self.armed), ["a1", "t2"])   # the timers the logout took
        notes = dict(self.told)
        self.assertTrue(notes["Old"].startswith("Didn't arrive at work"))
        self.assertTrue(notes["Missed time"].startswith("Missed while you were away"))

    def test_restore_and_places_check_side_by_side(self):
        """A login starts both at once (autostart.lua): an arrival and a login reminder are each told once."""
        self.add("arrive work", "Arrive")
        self.add("login", "Login")
        restore = lambda: remind.cmd_restore(types.SimpleNamespace())
        event = lambda: remind.cmd_event(types.SimpleNamespace(json=True, kind="arrive", place="work"))
        with mock.patch("builtins.print"):   # once around the threads: a patch per thread would race
            for order in [(restore, event, restore), (event, restore, event)]:   # either order, and a double start
                threads = [threading.Thread(target=f) for f in order]
                for t in threads:
                    t.start()
                for t in threads:
                    t.join()
        self.assertEqual(sorted(self.messages()), ["Arrive", "Login"])


if __name__ == "__main__":
    unittest.main(verbosity=1, argv=sys.argv[:1])
