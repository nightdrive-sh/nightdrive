#!/usr/bin/env python3
"""A recurring event added, changed and deleted, one time or every time (#2009: series.py through write.py and
change.py): `python3 plugins/calendar/lib/series_test.py`. No server: the calendar is a temporary folder and the sync
is recorded, not run; khal, when installed, reads the result as the window would."""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import zoneinfo
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import calendars  # noqa: E402
import change  # noqa: E402
import sources  # noqa: E402
import write  # noqa: E402

HKI = zoneinfo.ZoneInfo("Europe/Helsinki")
SERIES = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//EN
BEGIN:VEVENT
UID:S-1
DTSTAMP:20261101T080000Z
DTSTART;TZID=Europe/Helsinki:20261103T100000
DTEND;TZID=Europe/Helsinki:20261103T103000
RRULE:FREQ=WEEKLY;BYDAY=TU;COUNT=4
SUMMARY:Standup
BEGIN:VALARM
UID:A-1
ACTION:DISPLAY
TRIGGER:-PT5M
END:VALARM
END:VEVENT
END:VCALENDAR
"""


class SeriesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        folder = self.root / "data/acc/home"
        folder.mkdir(parents=True)
        self.cal = {"id": "acc/home", "name": "Home", "read_only": False, "shared": False, "path": str(folder),
                    "color": "#fff", "source": "acc", "events": 0}
        (folder / "S-1.ics").write_text(SERIES)
        self.synced = []
        self.saved = [(sources, "DATA_DIR", sources.DATA_DIR), (change, "UNDO_DIR", change.UNDO_DIR),
                      (calendars, "calendars", calendars.calendars), (write, "sync", write.sync),
                      (write, "local_zone", write.local_zone)]
        sources.DATA_DIR = self.root / "data"
        change.UNDO_DIR = self.root / "state/undo"
        calendars.calendars = lambda: [self.cal]
        write.sync = lambda cal: self.synced.append(cal["id"]) or True
        write.local_zone = lambda: HKI

    def tearDown(self):
        for m, n, v in self.saved:
            setattr(m, n, v)
        self.tmp.cleanup()

    def file(self, uid="S-1"):
        return Path(self.cal["path"]) / f"{uid}.ics"

    def times(self):
        """(start, title) of each time, as khal lists them for the window"""
        if not shutil.which("khal"):
            self.skipTest("khal isn't installed")
        conf = self.root / "khal.conf"
        conf.write_text(f'[calendars]\n[[t]]\npath = {self.cal["path"]}\n[locale]\ntimeformat = "%H:%M"\n'
                        'dateformat = "%Y-%m-%d"\nlongdateformat = "%Y-%m-%d"\ndatetimeformat = "%Y-%m-%dT%H:%M"\n'
                        f'longdatetimeformat = "%Y-%m-%dT%H:%M"\n[sqlite]\npath = {self.root}/khal.db\n')
        out = subprocess.run(["khal", "-c", str(conf), "list", "--day-format", "", "--json", "start", "--json", "title",
                              "2026-11-01", "2026-12-31"], capture_output=True, text=True, env={"TZ": "Europe/Helsinki",
                              "PATH": "/usr/bin:/bin"}, check=True).stdout
        return [(r["start"], r["title"]) for line in out.splitlines() if line.strip() for r in json.loads(line)]

    def test_refuses_without_a_scope(self):
        with self.assertRaises(SystemExit):
            change.edit("acc/home", "S-1", {"title": "x"})
        with self.assertRaises(SystemExit):
            change.edit("acc/home", "S-1", {"title": "x", "scope": "this"})   # which time?
        with self.assertRaises(SystemExit):
            write.delete("acc/home", "S-1", None)
        with self.assertRaises(SystemExit):
            change.edit("acc/home", "S-1", {"scope": "this", "occurrence": "2026-11-11T10:00", "title": "x"})
        self.assertEqual(self.file().read_text(), SERIES, "nothing written")

    def test_one_time_changed(self):
        r = change.edit("acc/home", "S-1", {"scope": "this", "occurrence": "2026-11-10T10:00", "title": "Planning",
                                            "start": "2026-11-11T13:00"})
        self.assertEqual((r["start"], r["end"]), ("2026-11-11T13:00", "2026-11-11T13:30"), "its length kept")
        text = self.file().read_text()
        self.assertIn("RECURRENCE-ID;TZID=Europe/Helsinki:20261110T100000", text)
        self.assertEqual(text.count("TRIGGER:-PT5M"), 2, "the copy has the alarm too")
        self.assertEqual(text.count("UID:A-1"), 1, "under a uid of its own")
        # Changed again, it is found by its own start, as calendar_events gives it
        change.edit("acc/home", "S-1", {"scope": "this", "occurrence": "2026-11-11T13:00", "location": "Room 2"})
        self.assertEqual(self.file().read_text().count("RECURRENCE-ID"), 1, "the same copy")
        self.assertEqual(self.times(), [("2026-11-03T10:00", "Standup"), ("2026-11-11T13:00", "Planning"),
                                        ("2026-11-17T10:00", "Standup"), ("2026-11-24T10:00", "Standup")])

    def test_one_time_keeps_its_calendar_and_rule(self):
        for data in ({"move_to": "Other"}, {"repeat": "daily"}):
            with self.assertRaises(SystemExit):
                change.edit("acc/home", "S-1", {"scope": "this", "occurrence": "2026-11-10T10:00", **data})

    def test_every_time_moved(self):
        change.edit("acc/home", "S-1", {"scope": "this", "occurrence": "2026-11-17T10:00", "title": "Retro"})
        write.delete("acc/home", "S-1", None, scope="this", occurrence="2026-11-24T10:00")
        # Seen on the 10th, moved to Wednesday 11:00: every time moves a day and to 11:00
        r = change.edit("acc/home", "S-1", {"scope": "all", "occurrence": "2026-11-10T10:00",
                                            "start": "2026-11-11T11:00", "title": "Standup"})
        self.assertEqual(r["start"], "2026-11-04T11:00", "the series' first time")
        text = self.file().read_text()
        self.assertIn("BYDAY=WE", text, "on Wednesdays now")
        self.assertIn("EXDATE;TZID=Europe/Helsinki:20261125T110000", text, "the deleted time moved along")
        self.assertEqual(self.times(), [("2026-11-04T11:00", "Standup"), ("2026-11-11T11:00", "Standup"),
                                        ("2026-11-17T10:00", "Retro")], "the changed time stays as it was changed")

    def test_every_time_renamed_stays_put(self):
        before = self.file().read_text()
        change.edit("acc/home", "S-1", {"scope": "all", "occurrence": "2026-11-10T10:00", "start": "2026-11-10T10:00",
                                        "end": "2026-11-10T10:30", "title": "Daily"})
        after = self.file().read_text()
        self.assertIn("DTSTART;TZID=Europe/Helsinki:20261103T100000", after, "the window sends the time as it was")
        self.assertNotEqual(before, after)

    def test_rule_changed_and_removed(self):
        change.edit("acc/home", "S-1", {"scope": "this", "occurrence": "2026-11-24T10:00", "title": "Last"})
        change.edit("acc/home", "S-1", {"scope": "all", "repeat": {"every": "week", "count": 2}})
        self.assertNotIn("RECURRENCE-ID", self.file().read_text(), "the changed fourth time is no time any more")
        r = change.edit("acc/home", "S-1", {"scope": "all", "repeat": None})
        self.assertNotIn("RRULE", self.file().read_text())
        self.assertNotIn("repeat", r)
        # A single event is made to repeat without a scope
        r = change.edit("acc/home", "S-1", {"repeat": "daily"})
        self.assertEqual(r["repeat"], "Every day")

    def test_delete_one_then_all(self):
        r = write.delete("acc/home", "S-1", {"title": "Standup", "start": "2026-11-17T10:00"}, scope="this")
        self.assertEqual((r["start"], r["scope"]), ("2026-11-17T10:00", "this"))
        self.assertIn("EXDATE;TZID=Europe/Helsinki:20261117T100000", self.file().read_text())
        with self.assertRaises(SystemExit):   # the card's start must still be a time of it
            write.delete("acc/home", "S-1", {"title": "Standup", "start": "2026-11-17T10:00"}, scope="all")
        write.delete("acc/home", "S-1", {"title": "Standup", "start": "2026-11-10T10:00"}, scope="all")
        self.assertFalse(self.file().exists())

    def test_last_time_deleted_takes_the_file(self):
        for day in ("03", "10", "17"):
            write.delete("acc/home", "S-1", None, scope="this", occurrence=f"2026-11-{day}T10:00")
        self.assertTrue(self.file().exists())
        write.delete("acc/home", "S-1", None, scope="this", occurrence="2026-11-24T10:00")
        self.assertFalse(self.file().exists())

    def test_add_with_a_repeat_and_undo_it(self):
        r = write.add({"title": "Gym", "start": "2026-11-02T18:00", "calendar": "acc/home",
                       "repeat": {"every": "week", "days": ["MO", "TH"], "until": "2026-11-12"}})
        self.assertEqual(r["repeat"], "Every week on Mon, Thu, until 2026-11-12")
        self.assertIn("RRULE:FREQ=WEEKLY;UNTIL=20261112T215959Z;BYDAY=MO,TH", self.file(r["uid"]).read_text())
        gym = [t for t, title in self.times() if title == "Gym"]
        self.assertEqual(gym, ["2026-11-02T18:00", "2026-11-05T18:00", "2026-11-09T18:00", "2026-11-12T18:00"])
        write.delete("acc/home", r["uid"], None, scope="all")   # calendar_add's undo
        self.assertFalse(self.file(r["uid"]).exists())

    def test_all_day_series(self):
        r = write.add({"title": "Holiday", "start": "2026-12-24", "calendar": "acc/home", "repeat": "yearly"})
        change.edit("acc/home", r["uid"], {"scope": "this", "occurrence": "2027-12-24", "start": "2027-12-23"})
        self.assertIn("RECURRENCE-ID;VALUE=DATE:20271224", self.file(r["uid"]).read_text())

    def test_undo_puts_the_series_back(self):
        r = change.edit("acc/home", "S-1", {"scope": "all", "occurrence": "2026-11-10T10:00", "start": "2026-11-10T09:00"})
        change.restore(r["undo"])
        self.assertEqual(self.file().read_text(), SERIES)


if __name__ == "__main__":
    unittest.main()
