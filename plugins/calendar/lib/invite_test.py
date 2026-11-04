#!/usr/bin/env python3
"""calendar invite (invite.py, invite_write.py) on calendar folders of their own (#2008):
`python3 plugins/calendar/lib/invite_test.py`. No server: the calendars are temporary folders, the sync is recorded."""

import sys
import tempfile
import unittest
from pathlib import Path

import icalendar

sys.path.insert(0, str(Path(__file__).parent))
import calendars  # noqa: E402
import invite  # noqa: E402
import invite_write  # noqa: E402
import write  # noqa: E402

# As Outlook sends one: a zone only the file defines, the sender's alarm, an attachment and a URL to leave out
INVITE = """BEGIN:VCALENDAR
METHOD:{method}
PRODID:Microsoft Exchange Server 2010
VERSION:2.0
BEGIN:VTIMEZONE
TZID:FLE Standard Time
BEGIN:STANDARD
DTSTART:16010101T040000
TZOFFSETFROM:+0300
TZOFFSETTO:+0200
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:16010101T030000
TZOFFSETFROM:+0200
TZOFFSETTO:+0300
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VEVENT
ORGANIZER;CN="Maija M‮eikäläinen":mailto:maija@example.com
ATTENDEE;ROLE=REQ-PARTICIPANT;RSVP=TRUE;CN=Jari:mailto:jari@example.com
DESCRIPTION:Agenda\\n- budget
UID:040000008200E00074C5B7101A82E008-ONE
SUMMARY;LANGUAGE=en-US:Planning\x07 review
DTSTART;TZID=FLE Standard Time:20261110T{start}00
DTEND;TZID=FLE Standard Time:20261110T{end}00
LOCATION:Room 4
SEQUENCE:{seq}
DTSTAMP:20261104T090000Z
URL:https://example.com/track
ATTACH:https://example.com/agenda.pdf
X-MICROSOFT-CDO-BUSYSTATUS:BUSY
BEGIN:VALARM
ACTION:DISPLAY
TRIGGER:-PT15M
END:VALARM
END:VEVENT
END:VCALENDAR
"""


def ics(method="REQUEST", start="1000", end="1100", seq=0):
    return icalendar.Calendar.from_ical(INVITE.format(method=method, start=start, end=end, seq=seq))


class InviteTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.cals = []
        for cid, ro in (("acc/home", False), ("feed/google", True)):
            folder = root / cid
            folder.mkdir(parents=True)
            self.cals.append({"id": cid, "name": cid.split("/")[1].title(), "read_only": ro, "shared": False,
                              "path": str(folder), "color": "#fff", "source": cid.split("/")[0], "events": 0})
        self.synced = []
        self.saved = [(calendars, "calendars", calendars.calendars), (write, "sync", write.sync)]
        calendars.calendars = lambda: self.cals
        write.sync = lambda cal: self.synced.append(cal["id"]) or True

    def tearDown(self):
        for m, n, v in self.saved:
            setattr(m, n, v)
        self.tmp.cleanup()

    def files(self, i=0):
        return list(Path(self.cals[i]["path"]).glob("*.ics"))

    def test_reads_it_as_plain_text_in_local_time(self):
        info = invite.describe(ics())
        self.assertEqual(info["state"], "new")
        self.assertEqual(info["title"], "Planning review")           # the bell is gone
        self.assertEqual(info["organizer"], {"name": "Maija Meikäläinen", "address": "maija@example.com"})
        self.assertEqual((info["start"], info["end"]), ("2026-11-10T10:00", "2026-11-10T11:00"))   # Helsinki
        self.assertEqual(info["notes"], "Agenda\n- budget")
        self.assertEqual([c["id"] for c in info["calendars"]], ["acc/home"])   # not the read-only one

    def test_add_keeps_only_the_events_own_fields(self):
        result = invite_write.run(ics(), "add", "acc/home")
        self.assertEqual(result["done"], "added")
        self.assertEqual(self.synced, ["acc/home"])
        text = self.files()[0].read_text()
        for gone in ("METHOD", "ATTACH", "URL:", "VALARM", "X-MICROSOFT"):
            self.assertNotIn(gone, text)
        self.assertIn("ATTENDEE", text)
        self.assertIn("TZID:FLE Standard Time", text)
        self.assertEqual(invite.describe(ics())["state"], "added")

    def test_an_update_is_offered_and_keeps_the_users_reminder(self):
        invite_write.run(ics(), "add", "acc/home")
        path = self.files()[0]
        stored = icalendar.Calendar.from_ical(path.read_bytes())
        next(iter(stored.walk("VEVENT"))).add_component(icalendar.Alarm({"action": "DISPLAY", "trigger": "-PT1H"}))
        path.write_bytes(stored.to_ical())
        newer = ics(start="1300", end="1400", seq=1)
        info = invite.describe(newer)
        self.assertEqual((info["state"], info["changes"]), ("changed", ["time"]))
        self.assertEqual(invite_write.run(newer, "add", "")["done"], "updated")
        self.assertEqual(self.files(), [path])
        text = path.read_text()
        self.assertIn("T130000", text)
        self.assertIn("TRIGGER:-PT1H", text)
        self.assertEqual(invite.describe(ics(seq=0))["state"], "older")

    def test_a_cancellation_removes_it(self):
        self.assertEqual(invite.describe(ics("CANCEL"))["state"], "gone")
        invite_write.run(ics(), "add", "acc/home")
        self.assertEqual(invite.describe(ics("CANCEL", seq=1))["state"], "cancelled")
        self.assertEqual(invite_write.run(ics("CANCEL", seq=1), "remove", None)["done"], "removed")
        self.assertEqual(self.files(), [])

    def test_nothing_goes_in_a_read_only_calendar(self):
        with self.assertRaises(SystemExit):
            invite_write.run(ics(), "add", "feed/google")
        self.assertEqual(self.files(1), [])

    def test_a_broken_or_huge_file_is_refused(self):
        with self.assertRaises(SystemExit):
            invite.read(__file__)   # not a calendar
        big = Path(self.tmp.name) / "big.ics"
        big.write_bytes(b"x" * (invite.MAX_BYTES + 1))
        with self.assertRaises(SystemExit):
            invite.read(str(big))


if __name__ == "__main__":
    unittest.main()
