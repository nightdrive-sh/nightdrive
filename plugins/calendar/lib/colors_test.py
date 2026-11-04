#!/usr/bin/env python3
"""A calendar's own colour (colors.py, #2031): `python3 plugins/calendar/lib/colors_test.py`. The calendars are a
temporary folder, a CalDAV source's and an ICS one's; COLORS is a file in it."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import calendars  # noqa: E402
import colors  # noqa: E402
import sources  # noqa: E402

THEME = Path(__file__).resolve().parents[3] / "config/hypr/scripts/theme"


class ColorTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        cal = root / "data/acc/home"
        cal.mkdir(parents=True)
        (cal / "displayname").write_text("Home")
        (cal / "color").write_text("#0088FFFF")    # iCloud's, with its alpha
        (root / "data/feed/default").mkdir(parents=True)
        srcs = [{"name": "acc", "kind": "caldav", "read_only": False},
                {"name": "feed", "kind": "ics", "read_only": True, "title": "Feed", "color": "#4F8FE6"}]
        self.saved = [(m, n, getattr(m, n)) for m, n in ((sources, "DATA_DIR"), (sources, "sources"), (colors, "COLORS"))]
        sources.DATA_DIR = root / "data"
        sources.sources = lambda: srcs
        colors.COLORS = root / "config/colors.json"

    def tearDown(self):
        for m, n, v in self.saved:
            setattr(m, n, v)
        self.tmp.cleanup()

    def cal(self, cid):
        return calendars.find(cid)

    def test_server_colour_until_one_is_picked(self):
        self.assertEqual((self.cal("acc/home")["color"], self.cal("acc/home")["custom"]), ("#0088FF", False))
        r = colors.set_color("acc/home", "teal")
        self.assertEqual((r["color"], r["custom"], r["previous"]), ("#7ae2de", True, "reset"))
        self.assertEqual(self.cal("acc/home")["color"], "#7ae2de", "kept in COLORS, read again")
        self.assertEqual(self.cal("acc/home")["own_color"], "#0088FF", "the server's stays known")

    def test_over_an_ics_colour_and_reset(self):
        colors.set_color("feed/default", "#AABBCC")
        self.assertEqual(self.cal("feed/default")["color"], "#aabbcc")
        r = colors.set_color("feed/default", "reset")
        self.assertEqual((r["color"], r["custom"], r["previous"]), ("#4F8FE6", False, "#aabbcc"))
        self.assertEqual(colors.chosen(), {})

    def test_refuses_what_isnt_a_colour_or_a_calendar(self):
        with self.assertRaises(SystemExit):
            colors.set_color("acc/home", "chartreuse")
        with self.assertRaises(SystemExit):
            colors.set_color("acc/nope", "red")
        self.assertFalse(colors.COLORS.exists(), "nothing written")

    def test_broken_file_is_none(self):
        colors.COLORS.parent.mkdir(parents=True)
        colors.COLORS.write_text("{not json")
        self.assertEqual(self.cal("acc/home")["color"], "#0088FF")

    def test_palette_is_the_themes(self):
        # The theme script's colours by name (`theme list`: key, name, main colour); the rest are Theme.qml's
        out = subprocess.run([sys.executable, "-I", str(THEME), "list"], capture_output=True, text=True, check=True).stdout
        themes = {line.split("\t")[0]: line.split("\t")[2] for line in out.splitlines()}
        qml = (THEME.parents[2] / "quickshell/Theme.qml").read_text()
        for name, hexcol in colors.PALETTE:
            if name in themes:
                self.assertEqual(themes[name], hexcol, name)
            else:
                self.assertIn(f'"{hexcol}"', qml, name)


if __name__ == "__main__":
    unittest.main()
