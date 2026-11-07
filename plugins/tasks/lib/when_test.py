#!/usr/bin/env python3
"""when.py's readings of a due, as the command, Claude and the window's fields give them: python3 when_test.py"""

import unittest
from datetime import date, datetime
from unittest import mock

import when

NOW = datetime(2026, 11, 2, 14, 20)   # a Monday afternoon
# Entries of the kit's regions.json, the parts the readings and labels use
FI = {"order": "dmy", "day": "d.M.", "short": "d.M.yyyy", "time": "H:mm"}
UK = {"order": "dmy", "day": "d/M", "short": "dd/MM/yyyy", "time": "HH:mm"}
US = {"order": "mdy", "day": "M/d", "short": "M/d/yyyy", "time": "h:mm AP"}
SE = {"order": "ymd", "day": "d/M", "short": "yyyy-MM-dd", "time": "HH:mm"}
ISO = {"order": "ymd", "day": "MM-dd", "short": "yyyy-MM-dd", "time": "HH:mm"}


def setUpModule():
    # Finland's unless a test gives its region, not the region of the machine the tests run on
    patch = mock.patch.object(when.region, "current", lambda: FI)
    patch.start()
    unittest.addModuleCleanup(patch.stop)


class Parse(unittest.TestCase):
    def test_days(self):
        self.assertEqual(when.parse("today", NOW), date(2026, 11, 2))
        self.assertEqual(when.parse("Tomorrow", NOW), date(2026, 11, 3))
        self.assertEqual(when.parse("5.11.", NOW), date(2026, 11, 5))
        self.assertEqual(when.parse("5.11.2027", NOW), date(2027, 11, 5))
        self.assertEqual(when.parse("2026-11-05", NOW), date(2026, 11, 5))
        self.assertEqual(when.parse("+3d", NOW), date(2026, 11, 5))

    def test_weekdays_are_the_next_one(self):
        self.assertEqual(when.parse("fri", NOW), date(2026, 11, 6))
        self.assertEqual(when.parse("friday", NOW), date(2026, 11, 6))
        self.assertEqual(when.parse("mon", NOW), date(2026, 11, 9))   # not today

    def test_times(self):
        self.assertEqual(when.parse("tomorrow 10", NOW), datetime(2026, 11, 3, 10, 0))
        self.assertEqual(when.parse("fri 930", NOW), datetime(2026, 11, 6, 9, 30))
        self.assertEqual(when.parse("2026-11-05T10:00", NOW), datetime(2026, 11, 5, 10, 0))
        self.assertEqual(when.parse("5.11. 9.30", NOW), datetime(2026, 11, 5, 9, 30))
        # A time alone: the next such time, tomorrow once it has gone by today
        self.assertEqual(when.parse("16:00", NOW), datetime(2026, 11, 2, 16, 0))
        self.assertEqual(when.parse("930", NOW), datetime(2026, 11, 3, 9, 30))
        self.assertEqual(when.parse("+2h", NOW), datetime(2026, 11, 2, 16, 20))

    def test_unreadable(self):
        for text in ("31.11.", "someday", "25:00", "fri 9:75", ""):
            with self.assertRaises(ValueError, msg=text):
                when.parse(text, NOW)


class TwelveHour(unittest.TestCase):
    """am/pm, as a US user writes the time (#2046), in every region"""
    def test_clock(self):
        self.assertEqual(when.parse("3pm", NOW), datetime(2026, 11, 2, 15, 0))
        self.assertEqual(when.parse("3:30 PM", NOW), datetime(2026, 11, 2, 15, 30))
        self.assertEqual(when.parse("fri 3:30 pm", NOW), datetime(2026, 11, 6, 15, 30))
        self.assertEqual(when.parse("tomorrow 9 a.m.", NOW), datetime(2026, 11, 3, 9, 0))
        self.assertEqual(when.parse("5.11. 1030am", NOW), datetime(2026, 11, 5, 10, 30))
        self.assertEqual(when.parse("2026-11-05 2p", NOW), datetime(2026, 11, 5, 14, 0))

    def test_noon_and_midnight(self):
        self.assertEqual(when.parse("tomorrow 12pm", NOW), datetime(2026, 11, 3, 12, 0))
        self.assertEqual(when.parse("tomorrow 12am", NOW), datetime(2026, 11, 3, 0, 0))
        self.assertEqual(when.parse("12am", NOW), datetime(2026, 11, 3, 0, 0))   # gone by today: tomorrow's

    def test_fields(self):
        self.assertEqual(when.at("5.11.", "3:30 PM", NOW), datetime(2026, 11, 5, 15, 30))
        self.assertEqual(when.at("", "4pm", NOW), datetime(2026, 11, 2, 16, 0))

    def test_a_day_is_not_a_time(self):
        self.assertEqual(when.parse("5.11.", NOW), date(2026, 11, 5))   # the dot is no "a.m."

    def test_not_twelve_hour(self):
        for text in ("14pm", "0am", "fri 13:30pm", "3:75pm"):
            with self.assertRaises(ValueError, msg=text) as e:
                when.parse(text, NOW)
            self.assertIn("time", str(e.exception), msg=text)
        with self.assertRaises(ValueError):
            when.at("today", "14 pm", NOW)


class RegionDays(unittest.TestCase):
    """A date typed the region's way (#2058), as the window's day field reads it (the kit's Dates.parse)"""
    def test_us(self):
        self.assertEqual(when.parse("11/5", NOW, US), date(2026, 11, 5))
        self.assertEqual(when.parse("11/5/2027", NOW, US), date(2027, 11, 5))
        self.assertEqual(when.parse("11/5/27", NOW, US), date(2027, 11, 5))
        self.assertEqual(when.parse("11/5 3pm", NOW, US), datetime(2026, 11, 5, 15, 0))
        self.assertEqual(when.at("11/5", "9:30 AM", NOW, US), datetime(2026, 11, 5, 9, 30))
        with self.assertRaises(ValueError):
            when.parse("13/5", NOW, US)   # no 13th month

    def test_day_first(self):
        self.assertEqual(when.parse("5/11", NOW, UK), date(2026, 11, 5))
        self.assertEqual(when.parse("05/11/2027", NOW, UK), date(2027, 11, 5))
        self.assertEqual(when.parse("5-11-27", NOW, FI), date(2027, 11, 5))
        self.assertEqual(when.at("5 11", "", NOW, FI), date(2026, 11, 5))   # a space in the day field

    def test_without_the_year_the_regions_own_day(self):
        self.assertEqual(when.parse("5/11", NOW, SE), date(2026, 11, 5))     # Sweden's day is d/M
        self.assertEqual(when.parse("11-05", NOW, ISO), date(2026, 11, 5))   # ISO's is MM-dd

    def test_iso_in_every_region(self):
        for r in (FI, US, SE, ISO):
            self.assertEqual(when.parse("2026-11-05", NOW, r), date(2026, 11, 5))
        self.assertEqual(when.parse("2026/11/05", NOW, US), date(2026, 11, 5))

    def test_the_machines_region(self):
        with mock.patch.object(when.region, "current", lambda: US):
            self.assertEqual(when.parse("11/5", NOW), date(2026, 11, 5))


class Label(unittest.TestCase):
    """The region's way (Settings › Region), with its entry given rather than read from the user's locale.conf"""
    FI, US = FI, US

    def test_finland(self):
        self.assertEqual(when.label(datetime(2026, 11, 2, 15, 0), NOW, self.FI), "Today 15:00")
        self.assertEqual(when.label(date(2026, 11, 3), NOW, self.FI), "Tomorrow")
        self.assertEqual(when.label(date(2026, 11, 1), NOW, self.FI), "Yesterday")
        self.assertEqual(when.label(date(2026, 11, 6), NOW, self.FI), "Fri 6.11.")
        self.assertEqual(when.label(datetime(2026, 11, 20, 9, 5), NOW, self.FI), "20.11. 9:05")
        self.assertEqual(when.label(date(2027, 1, 4), NOW, self.FI), "4.1.2027")

    def test_us(self):
        self.assertEqual(when.label(datetime(2026, 11, 2, 15, 0), NOW, self.US), "Today 3:00 PM")
        self.assertEqual(when.label(datetime(2026, 11, 3, 0, 30), NOW, self.US), "Tomorrow 12:30 AM")
        self.assertEqual(when.label(date(2026, 11, 6), NOW, self.US), "Fri 11/6")
        self.assertEqual(when.label(datetime(2026, 11, 20, 12, 0), NOW, self.US), "11/20 12:00 PM")
        self.assertEqual(when.label(date(2027, 1, 4), NOW, self.US), "1/4/2027")

    def test_none(self):
        self.assertEqual(when.label(None, NOW, self.US), "")


class At(unittest.TestCase):
    def test_fields(self):
        self.assertIsNone(when.at("", "", NOW))
        self.assertEqual(when.at("5.11", "", NOW), date(2026, 11, 5))          # a day in the day field
        self.assertEqual(when.at("5.11.", "930", NOW), datetime(2026, 11, 5, 9, 30))
        self.assertEqual(when.at("", "16", NOW), datetime(2026, 11, 2, 16, 0))

    def test_bad_time(self):
        with self.assertRaises(ValueError):
            when.at("today", "soon", NOW)


if __name__ == "__main__":
    unittest.main()
