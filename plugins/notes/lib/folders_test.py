#!/usr/bin/env python3
"""Folders and tags (#2016): `python3 plugins/notes/lib/folders_test.py`. Tags are read from the text and only there
(not a heading, a task's number, code or a link's address); folders are real folders, a note moved between them keeps
its name (numbered when taken) and its move back is its undo; list filters by folder (with what is under it) and tag
(with the tags nested in it)."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from tags import has_tag, tags_of   # noqa: E402


class Tags(unittest.TestCase):
    def test_words_after_a_hash(self):
        self.assertEqual(tags_of("#idea and #työ, (#paren) [#br]\n#start of a line"),
                         ["idea", "työ", "paren", "br", "start"])

    def test_not_tags(self):
        text = "# Heading\n## Sub\nTask #2016, page#part, colour #1e1e2e\n`#code` and [x](http://a/#anchor)\n"
        self.assertEqual(tags_of(text), [])

    def test_fenced_code_is_left_out(self):
        self.assertEqual(tags_of("```\n#include <x>\n```\n#real"), ["real"])

    def test_nested_and_trailing_marks(self):
        self.assertEqual(tags_of("#project/notes. #end- #a"), ["project/notes", "end", "a"])

    def test_once_each_case_aside(self):
        self.assertEqual(tags_of("#Idea #idea #IDEA"), ["Idea"])

    def test_has_tag_takes_nested(self):
        self.assertTrue(has_tag(["project/notes"], "project"))
        self.assertTrue(has_tag(["Project"], "#project"))
        self.assertFalse(has_tag(["projects"], "project"))


class Folders(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.notes = Path(self.tmp.name) / "Notes"
        (self.notes / "Work/Plans").mkdir(parents=True)
        (self.notes / "Empty").mkdir()
        (self.notes / ".hidden").mkdir()
        (self.notes / "Top.md").write_text("# Top\n#idea\n")
        (self.notes / "Work/Plan.md").write_text("# Plan\n#project/q3\n")
        (self.notes / "Work/Plans/Q3.md").write_text("# Q3\n#project\n")

    def tearDown(self):
        self.tmp.cleanup()

    def notes_cmd(self, *args):
        env = dict(os.environ, NOTES_DIR=str(self.notes))
        done = subprocess.run([sys.executable, str(HERE / "notes.py"), *args], env=env, capture_output=True, text=True,
                              timeout=30)
        return done.returncode, json.loads(done.stdout) if done.returncode == 0 and "--json" in args else done.stderr

    def ids(self, r):
        return sorted(n["id"] for n in r["notes"])

    def test_list_has_folders_and_tags(self):
        code, r = self.notes_cmd("list", "--json")
        self.assertEqual(code, 0)
        self.assertEqual([(f["path"], f["count"], f["own"]) for f in r["folders"]],
                         [("Empty", 0, 0), ("Work", 2, 1), ("Work/Plans", 1, 1)])
        self.assertEqual({t["name"]: t["count"] for t in r["tags"]}, {"idea": 1, "project": 1, "project/q3": 1})
        self.assertEqual(r["total"], 3)

    def test_list_by_folder_and_tag(self):
        self.assertEqual(self.ids(self.notes_cmd("list", "--json", "--folder", "Work")[1]),
                         ["Work/Plan.md", "Work/Plans/Q3.md"])
        self.assertEqual(self.ids(self.notes_cmd("list", "--json", "--tag", "project")[1]),
                         ["Work/Plan.md", "Work/Plans/Q3.md"])
        self.assertEqual(self.ids(self.notes_cmd("list", "--json", "--folder", "Work/Plans", "--tag", "project")[1]),
                         ["Work/Plans/Q3.md"])
        self.assertNotEqual(self.notes_cmd("list", "--json", "--folder", "../x")[0], 0)

    def test_move_keeps_the_name_and_numbers_a_taken_one(self):
        (self.notes / "Plan.md").write_text("# Other plan\n")
        code, r = self.notes_cmd("move", "--json", "--", "Work/Plan.md", "")
        self.assertEqual(code, 0)
        self.assertEqual((r["id"], r["old_id"], r["old_folder"], r["moved"]), ("Plan 2.md", "Work/Plan.md", "Work", True))
        code, back = self.notes_cmd("move", "--json", "--", r["id"], r["old_folder"])
        self.assertEqual(back["id"], "Work/Plan 2.md")

    def test_move_makes_a_new_folder(self):
        code, r = self.notes_cmd("move", "--json", "--", "Top.md", "New one")
        self.assertEqual((code, r["id"], r["made"]), (0, "New one/Top.md", True))

    def test_move_to_where_it_is(self):
        code, r = self.notes_cmd("move", "--json", "--", "Top.md", "")
        self.assertEqual((code, r["moved"]), (0, False))

    def test_move_stays_inside(self):
        for bad in ("../out", ".hidden", "/../x"):
            self.assertNotEqual(self.notes_cmd("move", "--json", "--", "Top.md", bad)[0], 0, bad)
        self.assertTrue((self.notes / "Top.md").exists())

    def test_mkdir_and_rmdir(self):
        self.assertEqual(self.notes_cmd("mkdir", "--json", "--", "Ideas/Small")[0], 0)
        self.assertTrue((self.notes / "Ideas/Small").is_dir())
        self.assertNotEqual(self.notes_cmd("mkdir", "--json", "--", "Ideas")[0], 0)      # there already
        self.assertNotEqual(self.notes_cmd("rmdir", "--json", "--", "Work")[0], 0)       # not empty
        self.assertEqual(self.notes_cmd("rmdir", "--json", "--", "Empty")[0], 0)
        self.assertFalse((self.notes / "Empty").exists())

    def test_create_in_a_folder(self):
        code, r = self.notes_cmd("create", "--json", "--folder", "Work", "--untitled")
        self.assertEqual((code, r["id"], r["folder"]), (0, "Work/Untitled.md", "Work"))


if __name__ == "__main__":
    unittest.main()
