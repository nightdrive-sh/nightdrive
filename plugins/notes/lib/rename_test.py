#!/usr/bin/env python3
"""A note's new title (#2014): `python3 plugins/notes/lib/rename_test.py`. The heading and the file name follow it, in
the note's own folder, never over another note; unrename puts back exactly what was there, and only while the note is
still what rename left. refile (#2049): the file follows a title changed in the window, when it was named after the
old one."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


class Notes(unittest.TestCase):
    """A folder of notes of its own for each test, and the notes command run on it."""
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.notes = Path(self.tmp.name) / "Notes"
        (self.notes / "Work").mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def run_notes(self, *args):
        env = {k: v for k, v in os.environ.items() if not k.startswith("NIGHTDRIVE_MCP")}
        env["NOTES_DIR"] = str(self.notes)
        return subprocess.run([sys.executable, str(HERE / "notes.py"), *args], env=env, capture_output=True,
                              text=True, timeout=30)

    def ok(self, *args):
        done = self.run_notes(*args)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout) if "--json" in args else done.stdout

    def undo(self, r):
        return self.ok("unrename", "--json", "--expect", r["md5"], "--", r["id"], r["old_id"], r["old_head"])

    def note(self, name, text):
        (self.notes / name).write_text(text)
        return text


class Rename(Notes):
    def test_heading_and_file_follow(self):
        before = self.note("Work/Plan.md", "\n## Plan ##\nsteps\n")
        r = self.ok("rename", "--json", "Work/Plan.md", "Next  year")
        self.assertEqual(r["id"], "Work/Next year.md")
        self.assertEqual((self.notes / r["id"]).read_text(), "\n## Next year\nsteps\n")
        self.assertFalse((self.notes / "Work/Plan.md").exists())
        self.undo(r)
        self.assertEqual((self.notes / "Work/Plan.md").read_text(), before)
        self.assertFalse((self.notes / r["id"]).exists())

    def test_no_heading_gets_one_and_loses_it_on_undo(self):
        before = self.note("loose.md", "just text\n")
        r = self.ok("rename", "--json", "loose", "Loose ends")
        self.assertEqual((self.notes / "Loose ends.md").read_text(), "# Loose ends\n\njust text\n")
        self.undo(r)
        self.assertEqual((self.notes / "loose.md").read_text(), before)

    def test_taken_name_gets_a_number(self):
        self.note("A.md", "# A\n")
        other = self.note("B.md", "# B\nmine\n")
        r = self.ok("rename", "--json", "A.md", "B")
        self.assertEqual(r["id"], "B 2.md")
        self.assertEqual((self.notes / "B.md").read_text(), other)

    def test_same_name_new_case_of_heading(self):
        self.note("Todo.md", "# todo\r\nx\r\n")
        r = self.ok("rename", "--json", "Todo.md", "Todo")
        self.assertEqual(r["id"], "Todo.md")
        self.assertEqual((self.notes / "Todo.md").read_bytes(), b"# Todo\r\nx\r\n")
        self.undo(r)
        self.assertEqual((self.notes / "Todo.md").read_bytes(), b"# todo\r\nx\r\n")

    def test_undo_leaves_an_edit_made_since(self):
        self.note("A.md", "# A\n")
        r = self.ok("rename", "--json", "A.md", "C")
        (self.notes / "C.md").write_text("# C\nwritten since\n")
        done = self.run_notes("unrename", "--expect", r["md5"], "--", r["id"], r["old_id"], r["old_head"])
        self.assertEqual(done.returncode, 1)
        self.assertEqual((self.notes / "C.md").read_text(), "# C\nwritten since\n")

    def test_undo_never_over_a_new_note_with_the_old_name(self):
        self.note("A.md", "# A\n")
        r = self.ok("rename", "--json", "A.md", "C")
        self.note("A.md", "# A\nnew\n")
        self.assertEqual(self.run_notes("unrename", "--expect", r["md5"], "--", r["id"], r["old_id"],
                                        r["old_head"]).returncode, 1)
        self.assertEqual((self.notes / "A.md").read_text(), "# A\nnew\n")

    def test_undo_stays_in_the_folder(self):
        self.note("A.md", "# A\n")
        r = self.ok("rename", "--json", "A.md", "C")
        for where in ("../A.md", "Work/A.md", ".A.md"):
            self.assertEqual(self.run_notes("unrename", "--expect", r["md5"], "--", r["id"], where,
                                            r["old_head"]).returncode, 1, where)

    def test_title_cannot_lead_out(self):
        self.note("A.md", "# A\n")
        r = self.ok("rename", "--json", "A.md", "../../.bashrc")
        self.assertEqual(r["id"], "bashrc.md")
        self.assertEqual(sorted(p.name for p in self.notes.iterdir() if p.is_file()), ["bashrc.md"])

    def test_empty_title_refused(self):
        self.note("A.md", "# A\n")
        self.assertEqual(self.run_notes("rename", "A.md", "  ").returncode, 1)
        self.assertEqual((self.notes / "A.md").read_text(), "# A\n")


class Refile(Notes):
    """A title changed in the window (#2049): the file follows it when it was named after the old one."""

    def test_new_note_named_by_its_heading(self):
        r = self.ok("create", "--json", "--untitled")
        self.assertEqual((r["id"], r["text"]), ("Untitled.md", "# \n"))
        self.note("Untitled.md", "# Shopping\nmilk\n")
        r = self.ok("refile", "--json", "--", "Untitled.md", "Untitled")
        self.assertEqual((r["id"], r["renamed"]), ("Shopping.md", True))
        self.assertEqual((self.notes / "Shopping.md").read_text(), "# Shopping\nmilk\n")
        self.assertFalse((self.notes / "Untitled.md").exists())

    def test_second_untitled_gets_a_number(self):
        self.ok("create", "--json", "--untitled")
        self.assertEqual(self.ok("create", "--json", "--untitled")["id"], "Untitled 2.md")

    def test_follows_a_name_that_was_the_title(self):
        self.note("Work/Plan 2.md", "# Next year\n")
        r = self.ok("refile", "--json", "Work/Plan 2.md", "Plan")
        self.assertEqual(r["id"], "Work/Next year.md")

    def test_keeps_a_name_of_its_own(self):
        self.note("2026-11-03.md", "# Standup\n")
        r = self.ok("refile", "--json", "2026-11-03.md", "Monday")
        self.assertEqual((r["id"], r["renamed"]), ("2026-11-03.md", False))

    def test_no_heading_keeps_its_name(self):
        self.note("Untitled.md", "just text\n")
        self.assertFalse(self.ok("refile", "--json", "Untitled.md", "Untitled")["renamed"])

    def test_never_over_another_note(self):
        self.note("Shopping.md", "# Shopping\nold\n")
        self.note("Untitled.md", "# Shopping\nnew\n")
        r = self.ok("refile", "--json", "Untitled.md", "Untitled")
        self.assertEqual(r["id"], "Shopping 2.md")
        self.assertEqual((self.notes / "Shopping.md").read_text(), "# Shopping\nold\n")


if __name__ == "__main__":
    unittest.main()
