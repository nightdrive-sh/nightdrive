#!/usr/bin/env python3
"""`calendar remind`, run as nightdrive-calendar-remind.service runs it: the command, not remind.py's functions, in a
home of its own with a calendar and an event. From 16.11. the timer failed every minute for days unseen (#3309):
sources.py put Contacts' lib first on sys.path, and its settings.py shadowed Calendar's. A test that imported
remind.py's parts itself had Calendar's settings already loaded and passed."""

import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

# CI runs the tests with python3 -I, which leaves the script's own folder off the path
sys.path.insert(0, str(Path(__file__).resolve().parent))

import write  # noqa: E402

COMMAND = Path(__file__).resolve().parents[1] / "bin" / "calendar"
DEFAULT = 60   # the settings' default reminder, minutes: the event below has none of its own

EVENT = """BEGIN:VCALENDAR\r
VERSION:2.0\r
PRODID:-//Nightdrive//remind_test//EN\r
BEGIN:VEVENT\r
UID:remind-test\r
DTSTAMP:{stamp}\r
DTSTART:{start}\r
DTEND:{end}\r
SUMMARY:Dentist\r
END:VEVENT\r
END:VCALENDAR\r
"""


def utc(t):
    return t.strftime("%Y%m%dT%H%M%SZ")


@unittest.skipUnless(shutil.which("khal"), "needs khal (dnf install khal)")
class AsTheService(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="remind-test-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        config, data = self.home / ".config/calendar", self.home / ".local/share/calendar"
        config.mkdir(parents=True)
        # An ICS calendar: the check reads only its folder, so the address is never fetched
        (config / "calendars.conf").write_text("[ics family]\nname = Family\nurl-cmd = echo unused\n")
        # Notifications off: the check still plans and marks what came as seen, and shows nothing on the desktop
        (config / "settings.json").write_text(json.dumps({"reminders": False, "default_reminder": DEFAULT}))
        folder = data / "family/default"
        folder.mkdir(parents=True)
        now = dt.datetime.now(dt.timezone.utc).replace(second=0, microsecond=0)
        self.start = now + dt.timedelta(minutes=30)   # its default reminder came half an hour ago
        (folder / "remind-test.ics").write_text(EVENT.format(
            stamp=utc(now), start=utc(self.start), end=utc(self.start + dt.timedelta(hours=1))), newline="")

    def run_command(self):
        # A user unit's environment: no PYTHONPATH, no desktop, the home as the working folder, and no TZ (the CI
        # runner sets one): khal then takes the system's zone, as Calendar does (write.local_zone)
        env = {"HOME": str(self.home), "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LANG": "C.UTF-8",
               "XDG_RUNTIME_DIR": str(self.home)}
        return subprocess.run([str(COMMAND), "remind"], cwd=self.home, env=env, capture_output=True, text=True,
                              timeout=180)

    def test_check_succeeds_and_uses_calendars_settings(self):
        r = self.run_command()
        self.assertEqual(r.returncode, 0, r.stderr)
        seen = json.loads((self.home / ".local/state/calendar/reminded.json").read_text())
        # The reminder came from Calendar's default_reminder: Contacts' settings have no such key
        at = (self.start - dt.timedelta(minutes=DEFAULT)).astimezone(write.local_zone())   # as the plan writes it
        self.assertTrue(any(k.startswith("family/default|remind-test|") and k.endswith(at.isoformat()) for k in seen),
                        seen)

    def test_second_check_reads_the_plan(self):
        self.assertEqual(self.run_command().returncode, 0)
        r = self.run_command()   # the plan is kept: this one reads the file and settings only
        self.assertEqual(r.returncode, 0, r.stderr)


class Imports(unittest.TestCase):
    def test_contacts_lib_shadows_nothing(self):
        """sources.py reads Contacts' config.py; none of Contacts' modules may take the place of Calendar's own"""
        lib = Path(__file__).resolve().parent
        code = ("import sys; sys.path.insert(0, sys.argv[1]); import sources, settings, calendars;"
                "print(settings.__file__); print(sys.path)")
        r = subprocess.run([sys.executable, "-I", "-c", code, str(lib)], capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        loaded, path = r.stdout.splitlines()
        self.assertEqual(Path(loaded).parent, lib)
        self.assertNotIn("contacts", path)


if __name__ == "__main__":
    unittest.main()
