#!/usr/bin/env python3
"""`sources.py any`, the sync timer's condition (#2527): `python3 plugins/calendar/lib/sources_test.py`. Run as the
command the unit runs, with a throwaway config folder for Calendar's calendars.conf and Contacts' accounts.conf."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOURCES = Path(__file__).with_name("sources.py")


class AnySourceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.config = Path(self.tmp.name) / "config"
        (self.config / "calendar").mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def any(self, calendars=None):
        if calendars is not None:
            (self.config / "calendar/calendars.conf").write_text(calendars)
        env = {k: v for k, v in os.environ.items() if not k.startswith("XDG_")}
        env.update(HOME=self.tmp.name, XDG_CONFIG_HOME=str(self.config))
        return subprocess.run([sys.executable, "-I", str(SOURCES), "any"], env=env, capture_output=True).returncode

    def test_none_skips(self):
        # No Contacts account and no calendars.conf: nothing to sync, so the timer's round is skipped, not failed
        self.assertEqual(self.any(), 1)
        self.assertEqual(self.any(""), 1)

    def test_ics_source_syncs(self):
        self.assertEqual(self.any("[ics family]\nurl-cmd = echo https://example.invalid/f.ics\n"), 0)

    def test_broken_config_still_syncs(self):
        # The sync runs and fails visibly with calendars.conf's problem, instead of a silent skip
        self.assertEqual(self.any("[ics family]\n"), 0)


if __name__ == "__main__":
    unittest.main()
