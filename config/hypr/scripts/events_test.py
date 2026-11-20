#!/usr/bin/env python3
"""The WHEN grammar remind and schedule share (#3278): `python3 config/hypr/scripts/events_test.py`. Events read as
typed, a place known whatever its case and an unknown one refused with the places there are, --from still to come,
a row taken only by its own event once its --from has come, and the week after which a missing arrival is asked
about. The places are given as rows: nothing reads ~/.config."""

import datetime
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import events  # noqa: E402

PLACES = [{"name": "work", "wifi": ["Office"]}, {"name": "Home", "wifi": ["Den", "Den 5G"]}]
NOW = int(datetime.datetime(2026, 11, 19, 20, 0).timestamp())   # a Thursday evening
DAY = 86400


class Parse(unittest.TestCase):
    def test_not_an_event(self):
        for text in ("15", "14:45", "1h30m", "@123", ""):
            self.assertIsNone(events.parse(text, PLACES))

    def test_wake_and_login(self):
        self.assertEqual(events.parse("wake", PLACES), {"on": "wake"})
        self.assertEqual(events.parse("Login", PLACES), {"on": "login"})
        with self.assertRaises(events.WhenError):
            events.parse("wake work", PLACES)

    def test_a_place_in_any_case_keeps_its_own_name(self):
        self.assertEqual(events.parse("arrive WORK", PLACES), {"on": "arrive", "place": "work"})
        self.assertEqual(events.parse("leave  home ", PLACES), {"on": "leave", "place": "Home"})

    def test_unknown_or_missing_place_lists_the_places(self):
        with self.assertRaises(events.WhenError) as e:
            events.parse("arrive gym", PLACES)
        self.assertIn("work, Home", str(e.exception))
        self.assertIn("places add", str(e.exception))
        with self.assertRaises(events.WhenError) as e:
            events.parse("arrive", PLACES)
        self.assertIn("work, Home", str(e.exception))
        with self.assertRaises(events.WhenError) as e:
            events.parse("leave", [])
        self.assertIn("no places yet", str(e.exception))


class From(unittest.TestCase):
    def test_morning_said_in_the_evening_is_tomorrows(self):
        at = events.parse_from("05:00", NOW)
        self.assertEqual(datetime.datetime.fromtimestamp(at), datetime.datetime(2026, 11, 20, 5, 0))
        self.assertEqual(events.day_clock(at, NOW), "05:00 tomorrow")

    def test_minutes_and_a_date(self):
        self.assertEqual(events.parse_from("90m", NOW), NOW + 90 * 60)
        at = events.parse_from("2026-11-23 05:00", NOW)
        self.assertEqual(events.day_clock(at, NOW), "Mon 23.11. 05:00")

    def test_refused(self):
        for text in ("2026-11-01 05:00", "2026-12-24 05:00", "soon", "2026-13-01 05:00"):
            with self.assertRaises(events.WhenError):
                events.parse_from(text, NOW)


class Rows(unittest.TestCase):
    def setUp(self):
        self.r = events.row({"on": "arrive", "place": "work"}, NOW, events.parse_from("05:00", NOW))

    def test_only_its_own_event_after_its_from(self):
        morning = self.r["from"]
        self.assertFalse(events.matches(self.r, "arrive", "work", NOW))         # at work already this evening
        self.assertTrue(events.matches(self.r, "arrive", "Work", morning))
        self.assertFalse(events.matches(self.r, "leave", "work", morning))
        self.assertFalse(events.matches(self.r, "arrive", "home", morning))
        self.assertTrue(events.matches({"on": "wake", "added": NOW}, "wake", "", NOW))

    def test_the_week_counts_from_its_from(self):
        self.assertEqual(events.deadline(self.r), self.r["from"] + 7 * DAY)
        self.assertEqual(events.deadline(events.row({"on": "leave", "place": "work"}, NOW)), NOW + 7 * DAY)
        self.assertIsNone(events.deadline({"on": "wake", "added": NOW}))

    def test_said(self):
        self.assertEqual(events.label(self.r), "arrive work")
        self.assertEqual(events.describe(self.r, NOW), "On arriving at work, not before 05:00 tomorrow")
        self.assertEqual(events.describe(self.r, self.r["from"] + 1), "On arriving at work")
        self.assertEqual(events.card_when(self.r, NOW, PLACES),
                         "When I next arrive at work (Wi-Fi Office), not before 05:00 tomorrow")
        self.assertEqual(events.card_when({"on": "leave", "place": "Home"}, NOW, PLACES),
                         "When I next leave Home (Wi-Fi Den, Den 5G)")
        pub = events.public(self.r)
        self.assertEqual(pub["place"], "work")
        self.assertTrue(pub["from"].startswith("2026-11-20T05:00:00"))
        self.assertEqual(events.public({"on": "wake"}), {"place": None, "from": None})


if __name__ == "__main__":
    unittest.main(verbosity=1, argv=sys.argv[:1])
