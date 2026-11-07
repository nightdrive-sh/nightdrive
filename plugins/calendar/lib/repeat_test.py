#!/usr/bin/env python3
"""repeat.py's rules (#2009): `python3 plugins/calendar/lib/repeat_test.py`. The local zone is Helsinki's here, as
the times are written in it."""

import datetime as dt
import sys
import unittest
import zoneinfo
from pathlib import Path

import icalendar

sys.path.insert(0, str(Path(__file__).parent))
import repeat  # noqa: E402
import write  # noqa: E402

HKI = zoneinfo.ZoneInfo("Europe/Helsinki")


def event(lines):
    text = "BEGIN:VEVENT\nUID:R\n" + "\n".join(lines) + "\nEND:VEVENT\n"
    return icalendar.Event.from_ical(text.replace("\n", "\r\n"))


class RepeatTest(unittest.TestCase):
    def setUp(self):
        self.zone = write.local_zone
        write.local_zone = lambda: HKI

    def tearDown(self):
        write.local_zone = self.zone

    def test_spec_forms(self):
        self.assertIsNone(repeat.spec(None))
        self.assertIsNone(repeat.spec("none"))
        self.assertEqual(repeat.spec("biweekly")["interval"], 2)
        self.assertEqual(repeat.spec("weekdays")["days"], repeat.WEEKDAYS)
        s = repeat.spec({"every": "week", "days": ["th", "MO"], "until": "2027-06-01"})
        self.assertEqual((s["days"], s["until"]), (["MO", "TH"], dt.date(2027, 6, 1)), "days in the week's order")
        for bad in ("fortnightly", {"every": "hour"}, {"every": "day", "days": ["MO"]}, {"every": "week", "interval": 0},
                    {"every": "week", "until": "2027-01-01", "count": 3}, {"every": "week", "when": 1}, 5):
            with self.assertRaises(SystemExit, msg=bad):
                repeat.spec(bad)

    def test_rule_until_is_utc_for_a_time(self):
        start = dt.datetime(2026, 11, 2, 10, tzinfo=HKI)
        r = repeat.rule(repeat.spec({"every": "week", "until": "2026-11-30"}), start)
        self.assertEqual(r.to_ical(), b"FREQ=WEEKLY;UNTIL=20261130T215959Z", "the day's last moment here")
        r = repeat.rule(repeat.spec({"every": "day", "until": "2026-11-30"}), dt.date(2026, 11, 2))
        self.assertEqual(r.to_ical(), b"FREQ=DAILY;UNTIL=20261130")
        with self.assertRaises(SystemExit):   # a Monday start on Tue and Thu: the first time wouldn't be one
            repeat.rule(repeat.spec({"every": "week", "days": ["TU", "TH"]}), start)
        with self.assertRaises(SystemExit):
            repeat.rule(repeat.spec({"every": "week", "until": "2026-11-01"}), start)

    def test_read_back(self):
        e = event(["DTSTART;TZID=Europe/Helsinki:20261102T100000", "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH;UNTIL=20270601T205959Z"])
        r = repeat.read(e)
        self.assertEqual((r["every"], r["interval"], r["days"], r["until"], r["simple"]),
                         ("week", 2, ["MO", "TH"], "2027-06-01", True))
        self.assertEqual(r["text"], "Every 2 weeks on Mon, Thu, until 2027-06-01")
        r = repeat.read(event(["DTSTART:20261110T100000", "RRULE:FREQ=MONTHLY;BYDAY=2TU"]))
        self.assertFalse(r["simple"], "the second Tuesday: a rule the window's choices don't say")
        self.assertIsNone(repeat.read(event(["DTSTART:20261110T100000"])))

    def test_times_and_find(self):
        e = event(["DTSTART;TZID=Europe/Helsinki:20261026T100000", "RRULE:FREQ=WEEKLY;COUNT=4",
                   "EXDATE;TZID=Europe/Helsinki:20261102T100000"])
        got = [t.strftime("%m-%d %H:%M %Z") for t in repeat.times(e)]
        self.assertEqual(got, ["10-26 10:00 EET", "11-09 10:00 EET", "11-16 10:00 EET"], "excluded one out")
        self.assertIsNone(repeat.find(e, dt.datetime(2026, 11, 2, 10, tzinfo=HKI)))
        found = repeat.find(e, dt.datetime(2026, 11, 9, 8, tzinfo=dt.timezone.utc))
        self.assertEqual(repeat.native(found, e), dt.datetime(2026, 11, 9, 10, tzinfo=HKI))
        self.assertIsNone(repeat.find(e, dt.datetime(2026, 11, 9, 11, tzinfo=HKI)), "not at another hour")

    def test_across_summer_time(self):
        e = event(["DTSTART;TZID=Europe/Helsinki:20260320T090000", "RRULE:FREQ=WEEKLY;COUNT=3"])
        self.assertEqual([t.hour for t in repeat.times(e)], [9, 9, 9], "9:00 here, before and after the change")

    def test_all_day_and_floating(self):
        e = event(["DTSTART;VALUE=DATE:20261224", "RRULE:FREQ=YEARLY;UNTIL=20281224"])
        self.assertEqual(len(list(repeat.times(e))), 3)
        self.assertEqual(repeat.native(repeat.find(e, dt.date(2027, 12, 24)), e), dt.date(2027, 12, 24))
        f = event(["DTSTART:20261102T100000", "RRULE:FREQ=DAILY;UNTIL=20261104T080000Z"])
        self.assertEqual(len(list(repeat.times(f))), 3, "a floating start with a UTC until")
        self.assertEqual(repeat.native(repeat.find(f, dt.datetime(2026, 11, 3, 10, tzinfo=HKI)), f),
                         dt.datetime(2026, 11, 3, 10), "a floating series' time stays floating")

    def test_rdate_alone(self):
        e = event(["DTSTART;TZID=Europe/Helsinki:20261102T100000", "RDATE;TZID=Europe/Helsinki:20261105T100000"])
        self.assertEqual(len(list(repeat.times(e))), 2)
        self.assertFalse(repeat.read(e)["simple"])


if __name__ == "__main__":
    unittest.main()
