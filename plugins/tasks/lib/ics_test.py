#!/usr/bin/env python3
"""A title or note is one value in the VTODO (#1925): `python3 plugins/tasks/lib/ics_test.py`. CR, CRLF, NEL and
Unicode's line and paragraph separators (and the other breaks splitlines() knows) are written escaped, so text Claude
or the user gives can't end its line and add a property (END:VTODO, STATUS, a VALARM) when the file is read back."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ics import Task, unfold  # noqa: E402

BREAKS = ["\r\n", "\r", "\n", "\x0b", "\x0c", "\x1c", "\x1d", "\x1e", "\x85", " ", " "]
INJECT = "STATUS:COMPLETED{0}DUE;VALUE=DATE:20000101{0}BEGIN:VALARM{0}ACTION:DISPLAY{0}END:VALARM{0}END:VTODO"


class Escape(unittest.TestCase):
    def own(self, task):
        return [task.lines[i].name for i in task.own()]

    def test_every_break_stays_in_its_value(self):
        for br in BREAKS:
            with self.subTest(br=repr(br)):
                title, note = f"Milk{br}{INJECT.format(br)}", f"Shop{br}PRIORITY:1"
                task = Task.new(title)
                task.set("DESCRIPTION", note)
                text = str(task)
                # The file as any reader splits it, Python's splitlines() too: a line per property, none injected
                self.assertEqual(text.splitlines(), text.split("\r\n")[:-1])
                back = Task(text)
                self.assertEqual(self.own(back).count("STATUS"), 1)
                self.assertEqual(back.get("STATUS"), "NEEDS-ACTION")
                self.assertNotIn("DUE", self.own(back))
                self.assertNotIn("PRIORITY", self.own(back))
                self.assertEqual([l.name for l in back.lines].count("BEGIN"), 2, "VCALENDAR and VTODO, no VALARM")
                self.assertEqual(back.get("SUMMARY"), f"Milk\n{INJECT.format(chr(10))}")
                self.assertEqual(back.get("DESCRIPTION"), "Shop\nPRIORITY:1")

    def test_long_text_folds_and_comes_back(self):
        title = ("Ääkköset ja rivinvaihto " * 8) + "; pilkku, ja \\ kenoviiva"
        back = Task(str(Task.new(title)))
        self.assertEqual(back.get("SUMMARY"), title.replace(" ", "\n"))

    def test_another_apps_value_stays_one_line(self):
        # A file from elsewhere with a raw U+2028 or CR in a value (not escaped): one value, not a new property
        for br in (" ", "\x85", "\r", "\x0c"):
            with self.subTest(br=repr(br)):
                text = ("BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nUID:x\r\n"
                        f"SUMMARY:Milk{br}STATUS:COMPLETED\r\nSTATUS:NEEDS-ACTION\r\nEND:VTODO\r\nEND:VCALENDAR\r\n")
                task = Task(text)
                self.assertEqual(task.get("STATUS"), "NEEDS-ACTION")
                self.assertEqual(task.get("SUMMARY"), f"Milk{br}STATUS:COMPLETED")

    def test_unfold(self):
        self.assertEqual(unfold("A:b\r\n c\r\nD:e\nF:g"), ["A:bc", "D:e", "F:g"])


if __name__ == "__main__":
    unittest.main()
