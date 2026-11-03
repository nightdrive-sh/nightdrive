#!/usr/bin/env python3
"""when.py's readings of a due, as the command, Claude and the window's fields give them: python3 when_test.py"""

import unittest
from datetime import date, datetime

import when

NOW = datetime(2026, 11, 2, 14, 20)   # a Monday afternoon


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


class Label(unittest.TestCase):
    """The region's way (Settings › Region), with its entry given rather than read from the user's locale.conf"""
    FI = {"day": "d.M.", "short": "d.M.yyyy", "time": "H:mm"}
    US = {"day": "M/d", "short": "M/d/yyyy", "time": "h:mm AP"}

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
