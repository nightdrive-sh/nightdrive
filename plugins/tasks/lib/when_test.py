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
