#!/usr/bin/env python3
"""calendar edit and restore (change.py) on a calendar folder of their own (#2002): `python3 plugins/calendar/lib/change_test.py`.
No server: the calendars are two temporary folders and the sync is recorded, not run."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import calendars  # noqa: E402
import change  # noqa: E402
import sources  # noqa: E402
import write  # noqa: E402

EVENT = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//EN
BEGIN:VEVENT
UID:ABC-1
DTSTAMP:20261101T080000Z
DTSTART;TZID=Europe/Helsinki:20261105T100000
DTEND;TZID=Europe/Helsinki:20261105T113000
SUMMARY:Dentist
LOCATION:Kamppi
DESCRIPTION:Bring the card
SEQUENCE:2
BEGIN:VALARM
ACTION:DISPLAY
TRIGGER:-PT15M
END:VALARM
END:VEVENT
END:VCALENDAR
"""


class EditTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.patches = [(sources, "DATA_DIR", root / "data"), (change, "UNDO_DIR", root / "state/undo")]
        self.saved = [(m, n, getattr(m, n)) for m, n, _ in self.patches]
        for m, n, v in self.patches:
            setattr(m, n, v)
        self.cals = []
        for cid in ("acc/home", "acc/work"):
            folder = root / "data" / cid
            folder.mkdir(parents=True)
            self.cals.append({"id": cid, "name": cid.split("/")[1].title(), "read_only": False, "shared": False,
                              "path": str(folder), "color": "#fff", "source": "acc", "events": 0})
        (Path(self.cals[0]["path"]) / "ABC-1.ics").write_text(EVENT)
        self.synced = []
        self.saved += [(calendars, "calendars", calendars.calendars), (write, "sync", write.sync)]
        calendars.calendars = lambda: self.cals
        write.sync = lambda cal: self.synced.append(cal["id"]) or True

    def tearDown(self):
        for m, n, v in self.saved:
            setattr(m, n, v)
        self.tmp.cleanup()

    def file(self, cal=0):
        return Path(self.cals[cal]["path"]) / "ABC-1.ics"

    def test_change_keeps_the_rest(self):
        r = change.edit("acc/home", "ABC-1", {"title": "Dentist again", "start": "2026-11-06T14:00", "notes": ""})
        self.assertEqual((r["start"], r["end"]), ("2026-11-06T14:00", "2026-11-06T15:30"), "the length is kept")
        text = self.file().read_text()
        self.assertIn("SUMMARY:Dentist again", text)
        self.assertIn("LOCATION:Kamppi", text, "a field not given stays")
        self.assertNotIn("DESCRIPTION", text, "notes given empty are cleared")
        self.assertIn("SEQUENCE:3", text)
        self.assertIn("TRIGGER:-PT15M", text, "the alarm Calendar doesn't show stays")
        self.assertEqual(self.synced, ["acc/home"])

    def test_all_day_and_back(self):
        r = change.edit("acc/home", "ABC-1", {"start": "2026-11-07"})
        self.assertEqual((r["start"], r["end"], r["all_day"]), ("2026-11-07", "2026-11-07", True))
        self.assertIn("DTEND;VALUE=DATE:20261108", self.file().read_text(), "iCalendar's end is the day after")
        r = change.edit("acc/home", "ABC-1", {"start": "2026-11-07T09:00"})
        self.assertEqual(r["end"], "2026-11-07T10:00", "back to a time: an hour")

    def test_refuses_what_cannot_be(self):
        with self.assertRaises(SystemExit):
            change.edit("acc/home", "ABC-1", {"title": "  "})
        with self.assertRaises(SystemExit):
            change.edit("acc/home", "ABC-1", {"start": "2026-11-05T12:00", "end": "2026-11-05T11:00"})
        self.assertEqual(self.file().read_text(), EVENT, "nothing written")
        self.file().write_text(EVENT.replace("SEQUENCE:2", "RRULE:FREQ=WEEKLY"))
        with self.assertRaises(SystemExit):
            change.edit("acc/home", "ABC-1", {"title": "x"})

    def test_move_and_undo(self):
        r = change.edit("acc/home", "ABC-1", {"move_to": "Work"})
        self.assertTrue(r["moved"])
        self.assertFalse(self.file(0).exists())
        self.assertIn("SUMMARY:Dentist", self.file(1).read_text())
        self.assertEqual(self.synced, ["acc/home", "acc/work"], "the old calendar first")
        self.synced.clear()
        change.restore(r["undo"])
        self.assertEqual(self.file(0).read_text(), EVENT)
        self.assertFalse(self.file(1).exists())
        self.assertEqual(self.synced, ["acc/work", "acc/home"], "the UID leaves the other calendar first")

    def test_undo_refuses_a_later_change(self):
        r = change.edit("acc/home", "ABC-1", {"title": "One"})
        change.edit("acc/home", "ABC-1", {"title": "Two"})
        with self.assertRaises(SystemExit):
            change.restore(r["undo"])
        self.assertIn("SUMMARY:Two", self.file().read_text())

    def test_undo_stays_in_the_folder(self):
        r = change.edit("acc/home", "ABC-1", {"title": "One"})
        snap = change.UNDO_DIR / f"{r['undo']}.json"
        data = json.loads(snap.read_text())
        data["files"][0]["path"] = "../../etc/passwd"
        snap.write_text(json.dumps(data))
        with self.assertRaises(SystemExit):
            change.restore(r["undo"])


if __name__ == "__main__":
    unittest.main()
