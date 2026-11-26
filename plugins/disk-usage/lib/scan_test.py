#!/usr/bin/env python3
"""scan.py and claude.py: the cache and the chosen folders, and what Claude's top shows (hidden names folded, only
the folders Access lets it use)."""

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

# A home of its own before the modules read it
TMP = tempfile.TemporaryDirectory()
HOME = os.path.realpath(TMP.name)
os.environ.update(HOME=HOME, XDG_CACHE_HOME=HOME + "/.cache", XDG_STATE_HOME=HOME + "/.local/state")
for var in ("NIGHTDRIVE_MCP", "NIGHTDRIVE_MCP_OPTIONS", "NIGHTDRIVE_MCP_OPTIONS_FROM"):
    os.environ.pop(var, None)

# CI runs the tests with python3 -I, which leaves the script's own folder off the path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import claude  # noqa: E402
import scan  # noqa: E402


def write(path, n=50_000):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(os.urandom(n))


class Scan(unittest.TestCase):
    def test_scan_cached_and_read_back(self):
        write(f"{HOME}/Pictures/a.jpg")
        r = scan.scan(HOME + "/Pictures", progress=False)
        self.assertTrue(os.path.isfile(scan.cache_file(HOME + "/Pictures")))
        self.assertEqual(scan.read_cache(HOME + "/Pictures")["total"], r["total"])
        self.assertTrue(scan.cache_file(HOME + "/Pictures").startswith(HOME + "/.cache/nightdrive/disk-usage/"))

    def test_not_a_folder(self):
        with self.assertRaises(SystemExit):
            scan.scan(HOME + "/nothing", progress=False)

    def test_remember_newest_first_and_capped(self):
        for i in range(scan.MAX_FOLDERS + 2):
            os.makedirs(f"{HOME}/f{i}", exist_ok=True)
            scan.remember(f"{HOME}/f{i}")
        got = scan.folders()
        self.assertEqual(len(got), scan.MAX_FOLDERS)
        self.assertEqual(got[0], f"{HOME}/f{scan.MAX_FOLDERS + 1}")
        scan.remember(got[0], add=False)
        self.assertNotIn(got[0], scan.folders())

    def test_places_start_with_home_and_system(self):
        p = scan.places()
        self.assertEqual([r["path"] for r in p[:2]], [os.path.expanduser("~"), "/"])
        self.assertIn("free", p[0]["disk"])

    def test_human(self):
        self.assertEqual(scan.human(512), "512 B")
        self.assertEqual(scan.human(1_500_000), "1.5 MB")
        self.assertEqual(scan.human(250_000_000_000), "250 GB")


class Claude(unittest.TestCase):
    def setUp(self):
        write(f"{HOME}/Videos/film.mkv", 300_000)
        write(f"{HOME}/.secret-app/data.bin", 200_000)
        write(f"{HOME}/.cache/thing/blob", 100_000)

    def tearDown(self):
        for var in ("NIGHTDRIVE_MCP", "NIGHTDRIVE_MCP_OPTIONS_FROM"):
            os.environ.pop(var, None)

    def as_claude(self, folders):
        os.environ["NIGHTDRIVE_MCP"] = "1"
        os.environ["NIGHTDRIVE_MCP_OPTIONS_FROM"] = json.dumps({"apps-files": {"folders": folders}})

    def top(self, *args):
        out = io.StringIO()
        with redirect_stdout(out):
            claude.main(["claude.py", "top", *args])
        return json.loads(out.getvalue())

    def test_hidden_names_folded(self):
        self.as_claude(["~"])
        r = self.top("--limit", "50")
        names = [e["name"] for e in r["entries"]]
        self.assertFalse([n for n in names if n.startswith(".")], names)
        hidden = [e for e in r["entries"] if e["kind"] == claude.HIDDEN]
        self.assertEqual(len(hidden), 1)
        self.assertGreaterEqual(hidden[0]["size"], 300_000)
        self.assertIn("Videos", names)

    def test_outside_claudes_folders_refused(self):
        os.makedirs(f"{HOME}/Downloads", exist_ok=True)
        self.as_claude(["~/Downloads"])
        with self.assertRaises(SystemExit):
            self.top("--", HOME + "/Videos")
        with self.assertRaises(SystemExit):
            self.top()                          # home itself is outside Downloads

    def test_hidden_or_outside_home_refused(self):
        self.as_claude(["~"])
        for path in (HOME + "/.cache", "/etc", HOME + "/Videos/../.cache"):
            with self.assertRaises(SystemExit, msg=path):
                self.top("--", path)

    def test_link_counts_where_it_leads(self):
        os.makedirs(f"{HOME}/Downloads", exist_ok=True)
        os.symlink(HOME + "/.cache", f"{HOME}/Downloads/sneaky")
        self.as_claude(["~/Downloads"])
        with self.assertRaises(SystemExit):
            self.top("--", HOME + "/Downloads/sneaky")

    def test_card_names_kinds_and_refuses_unknown(self):
        out = claude.card(["thumbnails", "packages"])
        self.assertEqual(out["Empties"].splitlines()[0].split(":")[0], "Thumbnails")
        with self.assertRaises(SystemExit):
            claude.card(["home"])


if __name__ == "__main__":
    try:
        unittest.main()
    finally:
        TMP.cleanup()
