#!/usr/bin/env python3
"""Files' search below a folder: `python3 plugins/files/lib/search_test.py`. It finds names at every depth, case left
aside and the words as plain text; each row says the folder it is in; hidden files only with --hidden, and .git never;
an .ignore file is obeyed; the rows come in batches with a last line that counts them; without fd it says so."""

import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import search  # noqa: E402

FD = shutil.which("fd") or shutil.which("fdfind")


def run(folder, words, hidden=False):
    lines = []
    search.search(str(folder), words, hidden=hidden, emit=lines.append, fd=FD)
    out = [json.loads(x) for x in lines]
    rows = [r for o in out if "rows" in o for r in o["rows"]]
    return rows, out[-1]


@unittest.skipUnless(FD, "fd isn't installed (dnf install fd-find)")
class Search(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        for p in ["Report.pdf", "work/2026/q3/report-final.txt", "work/notes.md", ".hidden/report.txt",
                  ".git/report-head", "build/report.o", "a+b (1)/x[report].md"]:
            f = self.root / p
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text("x")
        (self.root / "reports").mkdir()
        (self.root / ".ignore").write_text("build/\n")

    def tearDown(self):
        self.tmp.cleanup()

    def names(self, rows):
        return sorted(r["name"] for r in rows)

    def test_every_depth_case_left_aside(self):
        rows, last = run(self.root, "report")
        self.assertEqual(self.names(rows), ["Report.pdf", "report-final.txt", "reports", "x[report].md"])
        self.assertEqual(last, {"done": True, "count": 4, "capped": False})

    def test_a_row_knows_its_folder(self):
        rows, _ = run(self.root, "final")
        r = rows[0]
        self.assertEqual(r["folder"], os.path.join("work", "2026", "q3"))
        self.assertEqual(r["path"], str(self.root / "work/2026/q3/report-final.txt"))
        self.assertFalse(r["dir"])
        self.assertEqual(r["size"], 1)
        self.assertGreater(r["modified"], 0)
        top, _ = run(self.root, "reports")
        self.assertEqual((top[0]["folder"], top[0]["dir"], top[0]["size"]), ("", True, 0))

    def test_words_are_plain_text(self):
        rows, _ = run(self.root, "[report]")
        self.assertEqual(self.names(rows), ["x[report].md"])
        rows, _ = run(self.root, "a+b (")
        self.assertEqual(self.names(rows), ["a+b (1)"])
        rows, _ = run(self.root, "-final")
        self.assertEqual(self.names(rows), ["report-final.txt"])

    def test_hidden_only_when_asked_and_git_never(self):
        rows, _ = run(self.root, "report", hidden=True)
        self.assertIn("report.txt", self.names(rows))
        self.assertNotIn("report-head", self.names(rows))
        self.assertNotIn("report.o", self.names(rows))      # .ignore still holds

    def test_batches(self):
        for i in range(search.BATCH + 5):
            (self.root / f"many-{i}").write_text("")
        lines = []
        search.search(str(self.root), "many-", emit=lines.append, fd=FD)
        batches = [json.loads(x)["rows"] for x in lines[:-1]]
        self.assertEqual([len(b) for b in batches], [search.BATCH, 5])
        self.assertEqual(json.loads(lines[-1])["count"], search.BATCH + 5)


class Missing(unittest.TestCase):
    def test_without_fd(self):
        old = os.environ.get("PATH")
        os.environ["PATH"] = ""
        try:
            lines = []
            self.assertIsNone(search.search("/", "x", emit=lines.append))
            self.assertEqual([json.loads(x) for x in lines], [{"missing": "fd"}])
        finally:
            os.environ["PATH"] = old


if __name__ == "__main__":
    unittest.main()
