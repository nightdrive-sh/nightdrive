#!/usr/bin/env python3
"""remind's rules (#3118): `python3 config/hypr/scripts/remind_test.py`. Minutes as typed, the state file kept under its
lock, a cancelled reminder never told, and at login the missed ones told and the waiting ones armed again. systemd and the
banner are stubbed: nothing here starts a timer or shows anything."""

import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
import time
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("remind", os.path.join(HERE, "remind"))
remind = importlib.util.module_from_spec(importlib.util.spec_from_loader("remind", loader))
loader.exec_module(remind)


class Minutes(unittest.TestCase):
    def test_forms(self):
        for text, n in [("15", 15), ("90m", 90), ("2h", 120), ("1h30m", 90), ("1h 30m", 90), ("45min", 45), ("10080", 10080)]:
            self.assertEqual(remind.parse_minutes(text), n, text)

    def test_refused(self):
        for text in ["0", "", "h", "m", "-5", "1.5", "10081", "soon", "2d"]:
            self.assertIsNone(remind.parse_minutes(text), text)


class Clock(unittest.TestCase):
    def test_next_such_time(self):
        import datetime
        now = datetime.datetime(2026, 11, 18, 22, 30).timestamp()
        at = lambda t: datetime.datetime.fromtimestamp(remind.when(t, now))
        self.assertEqual(at("22:45"), datetime.datetime(2026, 11, 18, 22, 45))
        self.assertEqual(at("22.45"), datetime.datetime(2026, 11, 18, 22, 45))
        self.assertEqual(at("9:05"), datetime.datetime(2026, 11, 19, 9, 5))     # passed today: tomorrow
        self.assertEqual(at("22:30"), datetime.datetime(2026, 11, 19, 22, 30))  # now is past too
        self.assertEqual(remind.when("60", now), now + 3600)                    # a plain number stays minutes
        for t in ["24:00", "22:60", "22:5", "2245"[:0], "x:10"]:
            self.assertIsNone(remind.clock_time(t, now), t)


class Timers(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        remind.STATE = os.path.join(self.dir.name, "reminders.json")
        remind.CANCELLED = os.path.join(self.dir.name, "reminders-cancelled.json")   # never the user's own
        self.armed, self.disarmed, self.told, self.active = [], [], [], set()
        remind.arm = lambda r: (self.armed.append(r["id"]), (True, ""))[1]
        remind.disarm = self.disarmed.append
        remind.armed = lambda rid: rid in self.active
        remind.tell = lambda rid, message, note, tries=1: self.told.append((message, note))

    def tearDown(self):
        self.dir.cleanup()

    def run_cmd(self, fn, **kw):
        fn(types.SimpleNamespace(json=True, **kw))

    def rows(self):
        with open(remind.STATE) as f:
            return json.load(f)["reminders"]

    def test_add_list_cancel(self):
        self.run_cmd(remind.cmd_add, when="10", message=["Tea", "is", "ready"])
        self.run_cmd(remind.cmd_add, when="5", message=[])
        rows = self.rows()
        self.assertEqual([r["message"] for r in rows], ["Tea is ready", remind.DEFAULT_MESSAGE])
        self.assertEqual(self.armed, [r["id"] for r in rows])
        self.run_cmd(remind.cmd_cancel, id=rows[0]["id"])
        self.assertEqual(self.disarmed, [rows[0]["id"]])
        self.assertEqual([r["id"] for r in self.rows()], [rows[1]["id"]])

    def test_put_back_at_its_time(self):
        """Claude's cancel undone: the same time and message again (remind add @UNIX)."""
        at = int(time.time()) + 600
        self.run_cmd(remind.cmd_add, when=f"@{at}", message=["Back"])
        self.assertEqual([(r["at"], r["message"]) for r in self.rows()], [(at, "Back")])
        with self.assertRaises(SystemExit):
            self.run_cmd(remind.cmd_add, when=f"@{int(time.time()) - 5}", message=["Too late"])

    def test_cancel_undone_gives_the_same_row(self):
        """Claude's cancel undone (remind uncancel): the same row, also an event's, which has no @UNIX to add back."""
        self.run_cmd(remind.cmd_add, when="10", message=["Tea"])
        rid = self.rows()[0]["id"]
        self.run_cmd(remind.cmd_cancel, id=rid)
        self.run_cmd(remind.cmd_uncancel, id=rid)
        self.assertEqual([(r["id"], r["message"]) for r in self.rows()], [(rid, "Tea")])
        self.assertEqual(self.armed, [rid, rid])
        with self.assertRaises(SystemExit):   # once only
            self.run_cmd(remind.cmd_uncancel, id=rid)

    def test_no_uncancel_once_its_time_passed(self):
        self.run_cmd(remind.cmd_add, when="5", message=["Late"])
        rid = self.rows()[0]["id"]
        self.run_cmd(remind.cmd_cancel, id=rid)
        real = time.time
        remind.time.time = lambda: real() + 3600
        try:
            with self.assertRaises(SystemExit):
                self.run_cmd(remind.cmd_uncancel, id=rid)
        finally:
            remind.time.time = real
        self.assertEqual(self.rows(), [])

    def test_fire_tells_once(self):
        self.run_cmd(remind.cmd_add, when="1", message=["Call back"])
        rid = self.rows()[0]["id"]
        self.run_cmd(remind.cmd_fire, id=rid)
        self.run_cmd(remind.cmd_fire, id=rid)          # a second run (a restart) says nothing again
        self.assertEqual([t[0] for t in self.told], ["Call back"])
        self.assertEqual(self.rows(), [])

    def test_cancelled_never_told(self):
        self.run_cmd(remind.cmd_add, when="1", message=["Gone"])
        rid = self.rows()[0]["id"]
        self.run_cmd(remind.cmd_cancel, id="all")
        self.run_cmd(remind.cmd_fire, id=rid)
        self.assertEqual(self.told, [])

    def test_restore_after_login(self):
        now = int(time.time())
        rows = [{"id": "aa", "at": now - 600, "message": "Missed"},
                {"id": "bb", "at": now + 600, "message": "Waiting, timer gone"},
                {"id": "cc", "at": now + 900, "message": "Waiting, timer still there"}]
        with open(remind.STATE, "w") as f:
            json.dump({"reminders": rows}, f)
        self.active = {"cc"}
        self.run_cmd(remind.cmd_restore)
        self.assertEqual([t[0] for t in self.told], ["Missed"])
        self.assertIn("Missed", self.told[0][1])
        self.assertEqual(self.armed, ["bb"])
        self.assertEqual([r["id"] for r in self.rows()], ["bb", "cc"])

    def test_broken_state_file(self):
        with open(remind.STATE, "w") as f:
            f.write("{not json")
        self.run_cmd(remind.cmd_add, when="3", message=["Fresh"])
        self.assertEqual([r["message"] for r in self.rows()], ["Fresh"])


if __name__ == "__main__":
    unittest.main(verbosity=1, argv=sys.argv[:1])
