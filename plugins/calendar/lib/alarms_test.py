#!/usr/bin/env python3
"""alarms.py: which VALARMs ring and when, and the editor's reminder written and read back."""

import datetime as dt
import unittest

import icalendar

import alarms

EVENT = """BEGIN:VEVENT
UID:x
DTSTART:20261105T100000
DTEND:20261105T110000
SUMMARY:Dentist
{alarms}END:VEVENT
"""


def alarm(trigger, action="DISPLAY", extra=""):
    return f"BEGIN:VALARM\nACTION:{action}\nTRIGGER{trigger}\n{extra}END:VALARM\n"


def vevent(*parts):
    text = "BEGIN:VCALENDAR\nVERSION:2.0\n" + EVENT.format(alarms="".join(parts)) + "END:VCALENDAR\n"
    return icalendar.Calendar.from_ical(text.replace("\n", "\r\n")).walk("VEVENT")[0]


START = alarms.local(dt.datetime(2026, 11, 5, 10, 0))
END = alarms.local(dt.datetime(2026, 11, 5, 11, 0))


class Times(unittest.TestCase):
    def test_relative_to_start_and_end(self):
        e = vevent(alarm(":-PT15M"), alarm(";RELATED=END:-PT5M", "AUDIO"))
        self.assertEqual(alarms.times(e, START, END), [START - dt.timedelta(minutes=15), END - dt.timedelta(minutes=5)])

    def test_apple_placeholders_and_snoozes_dont_ring(self):
        e = vevent(alarm(";VALUE=DATE-TIME:19760401T005545Z", "NONE"),
                   alarm(":-PT5M", extra="RELATED-TO:abc\n"))
        self.assertEqual(alarms.times(e, START, END), [])

    def test_dismissed_elsewhere_is_seen(self):
        # The next day in UTC: after 9:45 local in any zone
        e = vevent(alarm(":-PT15M", extra="ACKNOWLEDGED:20261106T120000Z\n"))
        self.assertEqual(alarms.times(e, START, END), [])

    def test_at_a_time(self):
        e = vevent(alarm(";VALUE=DATE-TIME:20261105T070000Z"))
        at = alarms.local(dt.datetime(2026, 11, 5, 7, 0, tzinfo=dt.timezone.utc))
        self.assertEqual(alarms.times(e, START, END), [at])


class Reminder(unittest.TestCase):
    def test_set_and_read_back(self):
        e = vevent(alarm(":-PT2H"), alarm(";VALUE=DATE-TIME:19760401T005545Z", "NONE"))
        self.assertEqual(alarms.reminder(e), 120)
        alarms.set_reminder(e, 15)
        self.assertEqual(alarms.reminder(e), 15)
        # The phone's placeholder stays, the old alarm goes
        self.assertEqual(sorted(str(a["action"]) for a in e.walk("VALARM")), ["DISPLAY", "NONE"])
        alarms.set_reminder(e, None)
        self.assertIsNone(alarms.reminder(e))

    def test_minutes(self):
        self.assertIsNone(alarms.minutes(None))
        self.assertIsNone(alarms.minutes("none"))
        self.assertEqual(alarms.minutes(-540), -540)
        with self.assertRaises(SystemExit):
            alarms.minutes("soon")
        with self.assertRaises(SystemExit):
            alarms.minutes(60000)


if __name__ == "__main__":
    unittest.main()
