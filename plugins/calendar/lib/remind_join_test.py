#!/usr/bin/env python3
"""The notification with Join a minute before a meeting (remind.py, notice.py, #3444):
`python3 plugins/calendar/lib/remind_join_test.py`. When it comes (join_at), which buttons a notification has, and
`calendar remind` run as the timer runs it, in a home of its own with made-up invitations (no real meeting's address)
and the notifications off, so nothing shows on the desktop: the check still marks what came as seen."""

import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import notice  # noqa: E402
import remind  # noqa: E402

COMMAND = Path(__file__).resolve().parents[1] / "bin" / "calendar"
TEAMS = "https://teams.microsoft.com/meet/000000000000?p=TestOnly"
MEETING = {"url": TEAMS, "service": "Teams"}
START = dt.datetime(2026, 11, 23, 10, 0, tzinfo=dt.timezone.utc)

EVENT = """BEGIN:VCALENDAR\r
VERSION:2.0\r
PRODID:-//Nightdrive//remind_join_test//EN\r
BEGIN:VEVENT\r
UID:{uid}\r
DTSTAMP:{stamp}\r
DTSTART:{start}\r
DTEND:{end}\r
SUMMARY:{title}\r
DESCRIPTION:{notes}\r
{alarm}END:VEVENT\r
END:VCALENDAR\r
"""
ALARM = "BEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Reminder\r\nTRIGGER:-PT{m}M\r\nEND:VALARM\r\n"


def utc(t):
    return t.strftime("%Y%m%dT%H%M%SZ")


class JoinAt(unittest.TestCase):
    def event(self, **kw):
        return dict({"all_day": False, "meeting": MEETING}, **kw)

    def test_a_minute_before(self):
        self.assertEqual(remind.join_at(self.event(), START, []), START - dt.timedelta(minutes=1))

    def test_far_reminder_doesnt_stop_it(self):
        self.assertEqual(remind.join_at(self.event(), START, [START - dt.timedelta(minutes=15)]),
                         START - dt.timedelta(minutes=1))

    def test_own_reminder_near_the_start_is_enough(self):
        for m in (0, 1, 2):
            self.assertIsNone(remind.join_at(self.event(), START, [START - dt.timedelta(minutes=m)]), m)

    def test_none_without_a_meeting_all_day_or_off(self):
        self.assertIsNone(remind.join_at(self.event(meeting=None), START, []))
        self.assertIsNone(remind.join_at(self.event(all_day=True), START, []))
        self.assertIsNone(remind.join_at(self.event(), START, [], on=False))


class Buttons(unittest.TestCase):
    def test_reminder_of_a_meeting_has_join(self):
        self.assertEqual([k for k, _ in notice.actions({"kind": "reminder", "meeting": MEETING})],
                         ["default", "join", "open", "snooze"])

    def test_join_notice_has_no_snooze(self):
        self.assertEqual([k for k, _ in notice.actions({"kind": "join", "meeting": MEETING})],
                         ["default", "join", "open"])

    def test_plain_reminder_as_before(self):
        # A plan written before #3444 has no kind or meeting
        self.assertEqual([k for k, _ in notice.actions({})], ["default", "open", "snooze"])


@unittest.skipUnless(shutil.which("khal"), "needs khal (dnf install khal)")
class AsTheService(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="remind-join-test-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        config = self.home / ".config/calendar"
        config.mkdir(parents=True)
        (config / "calendars.conf").write_text("[ics work]\nname = Work\nurl-cmd = echo unused\n")
        self.folder = self.home / ".local/share/calendar/work/default"
        self.folder.mkdir(parents=True)
        self.now = dt.datetime.now(dt.timezone.utc).replace(second=0, microsecond=0)
        self.settings({})

    def settings(self, more):
        # Notifications off: the check plans and marks as seen, and shows nothing
        data = {"reminders": False, "default_reminder": None}
        (self.home / ".config/calendar/settings.json").write_text(json.dumps(dict(data, **more)))

    def add(self, uid, start, notes, alarm=None):
        (self.folder / f"{uid}.ics").write_text(EVENT.format(
            uid=uid, stamp=utc(self.now), start=utc(start), end=utc(start + dt.timedelta(hours=1)), title=uid,
            notes=notes, alarm=ALARM.format(m=alarm) if alarm is not None else ""), newline="")

    def run_command(self, *args):
        env = {"HOME": str(self.home), "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LANG": "C.UTF-8",
               "XDG_RUNTIME_DIR": str(self.home)}
        r = subprocess.run([str(COMMAND), *args], cwd=self.home, env=env, capture_output=True, text=True, timeout=180)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def seen(self):
        return json.loads((self.home / ".local/state/calendar/reminded.json").read_text())

    def test_due_a_minute_before_not_earlier(self):
        self.add("soon", self.now + dt.timedelta(minutes=1), f"Join the meeting<{TEAMS}>")
        self.add("later", self.now + dt.timedelta(minutes=30), f"Join: {TEAMS}")
        self.add("plain", self.now + dt.timedelta(minutes=1), "No call, https://example.com/agenda")
        self.run_command("remind")
        keys = [k for k in self.seen() if k.endswith("|join")]
        self.assertEqual(len(keys), 1, keys)
        self.assertTrue(keys[0].startswith("work/default|soon|"), keys)
        # The later one waits in the plan, a minute before its start, with its meeting for Join
        upcoming = json.loads(self.run_command("reminders", "--json", "--days", "1"))["reminders"]
        [later] = [a for a in upcoming if a["kind"] == "join"]
        self.assertEqual(later["uid"], "later")
        self.assertEqual(dt.datetime.fromisoformat(later["at"]), self.now + dt.timedelta(minutes=29))
        self.assertEqual(later["meeting"], MEETING)

    def test_own_reminder_at_the_start_and_setting_off(self):
        self.add("own", self.now + dt.timedelta(minutes=30), f"Join: {TEAMS}", alarm=0)
        self.add("other", self.now + dt.timedelta(minutes=40), f"Join: {TEAMS}")
        upcoming = json.loads(self.run_command("reminders", "--json", "--days", "1"))["reminders"]
        self.assertEqual(sorted((a["uid"], a["kind"]) for a in upcoming), [("other", "join"), ("own", "reminder")])
        self.assertEqual(upcoming[0]["meeting"], MEETING)   # the reminder has Join too
        self.run_command("reminders", "join", "off")
        upcoming = json.loads(self.run_command("reminders", "--json", "--days", "1"))["reminders"]
        self.assertEqual([a["kind"] for a in upcoming], ["reminder"])


if __name__ == "__main__":
    unittest.main()
