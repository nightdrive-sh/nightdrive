#!/usr/bin/env python3
"""A task edited on two devices, merged field by field from the version both started from (merge.py, #3397):
`python3 plugins/tasks/lib/merge_test.py`."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ics import Task  # noqa: E402
from merge import merge  # noqa: E402


def vtodo(*props, uid="t1", modified="20261123T100000Z", calendar=""):
    """A task file as another app or an older Tasks may have written it: the props in the order given."""
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Test//EN"] + list(calendar and [calendar]) + [
        "BEGIN:VTODO", f"UID:{uid}", "DTSTAMP:20261123T090000Z"]
    if modified:
        lines.append(f"LAST-MODIFIED:{modified}")
    lines += list(props) + ["END:VTODO", "END:VCALENDAR"]
    return "\r\n".join(lines) + "\r\n"


BASE = vtodo("SUMMARY:Buy milk", "STATUS:NEEDS-ACTION", "DUE;VALUE=DATE:20261201", "PRIORITY:5",
             modified="20261123T080000Z")
EARLY, LATE = "20261123T100000Z", "20261123T110000Z"


def task(text):
    return Task(text)


class Merge(unittest.TestCase):
    def test_different_fields_both_kept(self):
        mine = vtodo("SUMMARY:Buy oat milk", "STATUS:NEEDS-ACTION", "DUE;VALUE=DATE:20261201", "PRIORITY:5",
                     modified=EARLY)
        theirs = vtodo("SUMMARY:Buy milk", "STATUS:NEEDS-ACTION", "DUE;VALUE=DATE:20261205", "PRIORITY:1",
                       modified=LATE)
        m = merge(BASE, mine, theirs, "laptop")
        t = task(m.text)
        self.assertEqual(t.get("SUMMARY"), "Buy oat milk")
        self.assertEqual(t.get("DUE"), "20261205")
        self.assertEqual(t.get("PRIORITY"), "1")
        self.assertEqual(m.lost, [])
        self.assertEqual(t.get("DESCRIPTION"), "")          # nothing lost, so no note

    def test_same_field_newer_wins_and_the_other_goes_in_the_note(self):
        mine = vtodo("SUMMARY:Buy milk today", "STATUS:NEEDS-ACTION", "DUE;VALUE=DATE:20261201", "PRIORITY:5",
                     modified=LATE)
        theirs = vtodo("SUMMARY:Buy milk and bread", "STATUS:NEEDS-ACTION", "DUE;VALUE=DATE:20261201",
                       "PRIORITY:5", modified=EARLY)
        m = merge(BASE, mine, theirs, "laptop")
        t = task(m.text)
        self.assertEqual(t.get("SUMMARY"), "Buy milk today")
        self.assertEqual([(x["field"], x["value"], x["from"]) for x in m.lost],
                         [("Title", "Buy milk and bread", "another computer")])
        note = t.get("DESCRIPTION")
        self.assertIn("Title: Buy milk and bread", note)
        self.assertIn("another computer", note)

    def test_this_computers_loss_is_named_with_its_host(self):
        mine = vtodo("SUMMARY:Mine", "STATUS:NEEDS-ACTION", modified=EARLY)
        theirs = vtodo("SUMMARY:Theirs", "STATUS:NEEDS-ACTION", modified=LATE)
        m = merge(vtodo("SUMMARY:Old", "STATUS:NEEDS-ACTION"), mine, theirs, "laptop")
        self.assertEqual(task(m.text).get("SUMMARY"), "Theirs")
        self.assertIn("laptop", task(m.text).get("DESCRIPTION"))
        self.assertIn("Title: Mine", task(m.text).get("DESCRIPTION"))

    def test_a_tie_keeps_the_hubs(self):
        mine = vtodo("SUMMARY:Mine", modified=EARLY)
        theirs = vtodo("SUMMARY:Theirs", modified=EARLY)
        self.assertEqual(task(merge(vtodo("SUMMARY:Old"), mine, theirs).text).get("SUMMARY"), "Theirs")

    def test_no_last_modified_is_older(self):
        mine = vtodo("SUMMARY:Mine", modified="")
        theirs = vtodo("SUMMARY:Theirs", modified=EARLY)
        self.assertEqual(task(merge(vtodo("SUMMARY:Old", modified=""), mine, theirs).text).get("SUMMARY"), "Theirs")
        mine = vtodo("SUMMARY:Mine", modified=EARLY)
        theirs = vtodo("SUMMARY:Theirs", modified="")
        self.assertEqual(task(merge(vtodo("SUMMARY:Old", modified=""), mine, theirs).text).get("SUMMARY"), "Mine")

    def test_removal_never_wins_over_an_edit(self):
        # Mine removed the due date (newer), theirs moved it: the moved date stays, and nothing is noted
        mine = vtodo("SUMMARY:Buy milk", "STATUS:NEEDS-ACTION", "PRIORITY:5", modified=LATE)
        theirs = vtodo("SUMMARY:Buy milk", "STATUS:NEEDS-ACTION", "DUE;VALUE=DATE:20261224", "PRIORITY:5",
                       modified=EARLY)
        m = merge(BASE, mine, theirs)
        self.assertEqual(task(m.text).get("DUE"), "20261224")
        self.assertEqual(m.lost, [])

    def test_a_removal_on_one_side_alone_is_kept(self):
        mine = vtodo("SUMMARY:Buy milk", "STATUS:NEEDS-ACTION", "PRIORITY:5", modified=EARLY)
        theirs = vtodo("SUMMARY:Buy milk", "STATUS:NEEDS-ACTION", "DUE;VALUE=DATE:20261201", "PRIORITY:1",
                       modified=LATE)
        t = task(merge(BASE, mine, theirs).text)
        self.assertIsNone(t.line("DUE"))
        self.assertEqual(t.get("PRIORITY"), "1")

    def test_done_moves_as_one_field(self):
        # Done on one device (STATUS, COMPLETED and PERCENT-COMPLETE together), retitled on the other
        mine = vtodo("SUMMARY:Buy milk", "STATUS:COMPLETED", "COMPLETED:20261123T100000Z", "PERCENT-COMPLETE:100",
                     "DUE;VALUE=DATE:20261201", "PRIORITY:5", modified=EARLY)
        theirs = vtodo("SUMMARY:Buy milk!", "STATUS:NEEDS-ACTION", "DUE;VALUE=DATE:20261201", "PRIORITY:5",
                       modified=LATE)
        t = task(merge(BASE, mine, theirs).text)
        self.assertEqual((t.get("SUMMARY"), t.get("STATUS"), t.get("PERCENT-COMPLETE")),
                         ("Buy milk!", "COMPLETED", "100"))
        self.assertIsNotNone(t.line("COMPLETED"))

    def test_done_against_undone_by_time(self):
        base = vtodo("SUMMARY:X", "STATUS:COMPLETED", "COMPLETED:20261120T100000Z", "PERCENT-COMPLETE:100")
        mine = vtodo("SUMMARY:X", "STATUS:NEEDS-ACTION", modified=LATE)                 # undone, later
        theirs = vtodo("SUMMARY:X", "STATUS:COMPLETED", "COMPLETED:20261123T100000Z", "PERCENT-COMPLETE:100",
                       modified=EARLY)                                                   # done again, earlier
        m = merge(base, mine, theirs, "laptop")
        t = task(m.text)
        self.assertEqual(t.get("STATUS"), "NEEDS-ACTION")
        self.assertIsNone(t.line("COMPLETED"))      # no COMPLETED left over from the losing side
        self.assertEqual([(x["field"], x["value"]) for x in m.lost], [("Done", "yes")])

    def test_notes_both_edited_keep_both_texts(self):
        base = vtodo("SUMMARY:X", "DESCRIPTION:Shop", modified="")
        mine = vtodo("SUMMARY:X", "DESCRIPTION:Shop at Lidl", modified=EARLY)
        theirs = vtodo("SUMMARY:X", "DESCRIPTION:Shop\\, then the bank", modified=LATE)
        note = task(merge(base, mine, theirs, "laptop").text).get("DESCRIPTION")
        self.assertTrue(note.startswith("Shop, then the bank"), note)
        self.assertIn("Notes: Shop at Lidl", note)

    def test_unknown_properties_and_alarms_survive(self):
        alarm = ["BEGIN:VALARM", "ACTION:DISPLAY", "TRIGGER:-PT15M", "END:VALARM"]
        base = vtodo("SUMMARY:X", "X-APPLE-SORT-ORDER:3", *alarm, modified="")
        mine = vtodo("SUMMARY:X", "X-APPLE-SORT-ORDER:3", "CATEGORIES:home", *alarm, modified=EARLY)
        theirs = vtodo("SUMMARY:Y", "X-APPLE-SORT-ORDER:3", *alarm, modified=LATE,
                       calendar="X-WR-CALNAME:Hub")
        text = merge(base, mine, theirs).text
        t = task(text)
        self.assertEqual((t.get("SUMMARY"), t.get("CATEGORIES"), t.get("X-APPLE-SORT-ORDER")), ("Y", "home", "3"))
        self.assertEqual(text.count("BEGIN:VALARM"), 1)
        self.assertIn("X-WR-CALNAME:Hub", text)         # the calendar's own lines: the Hub's file is the frame

    def test_an_alarm_added_on_one_side(self):
        alarm = ["BEGIN:VALARM", "ACTION:DISPLAY", "TRIGGER:-PT15M", "END:VALARM"]
        base = vtodo("SUMMARY:X", modified="")
        mine = vtodo("SUMMARY:X", *alarm, modified=EARLY)
        theirs = vtodo("SUMMARY:Y", modified=LATE)
        text = merge(base, mine, theirs).text
        self.assertEqual(task(text).get("SUMMARY"), "Y")
        self.assertIn("TRIGGER:-PT15M", text)
        self.assertLess(text.index("END:VALARM"), text.index("END:VTODO"))
        self.assertEqual(task(text).get("SUMMARY"), "Y")     # the VTODO's own lines still read past the alarm

    def test_result_is_marked_changed(self):
        mine = vtodo("SUMMARY:A", "SEQUENCE:4", modified=EARLY)
        theirs = vtodo("SUMMARY:X", "PRIORITY:1", "SEQUENCE:2", modified=LATE)
        t = task(merge(vtodo("SUMMARY:X", "SEQUENCE:1"), mine, theirs).text)
        self.assertEqual(t.get("SEQUENCE"), "5")
        self.assertGreater(t.get("LAST-MODIFIED"), LATE)
        self.assertEqual(len([i for i in t.own() if t.lines[i].name == "LAST-MODIFIED"]), 1)

    def test_nothing_of_mine_to_add_gives_the_hubs_file_as_it_is(self):
        mine = vtodo("SUMMARY:Buy milk", "STATUS:NEEDS-ACTION", "DUE;VALUE=DATE:20261201", "PRIORITY:5",
                     modified=LATE)                 # only touched
        theirs = vtodo("SUMMARY:Buy bread", "STATUS:NEEDS-ACTION", "DUE;VALUE=DATE:20261201", "PRIORITY:5",
                       modified=EARLY)
        self.assertEqual(merge(BASE, mine, theirs).text, theirs)

    def test_cant_merge(self):
        ok = vtodo("SUMMARY:X")
        self.assertIsNone(merge(None, ok, ok))                          # no version to start from: keep both
        self.assertIsNone(merge(ok, "not a task", ok))
        self.assertIsNone(merge(ok, ok, vtodo("SUMMARY:X", uid="other")))
        self.assertIsNone(merge(b"\xff", ok, ok))

    def test_bytes_in_and_line_endings_kept(self):
        mine = vtodo("SUMMARY:A", modified=EARLY).encode()
        theirs = vtodo("SUMMARY:X", "PRIORITY:1", modified=LATE).encode()
        text = merge(vtodo("SUMMARY:X").encode(), mine, theirs).text
        self.assertIn("SUMMARY:A\r\nPRIORITY:1\r\n", text)
        self.assertTrue(text.endswith("END:VCALENDAR\r\n"))


if __name__ == "__main__":
    unittest.main()
