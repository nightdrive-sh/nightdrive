#!/usr/bin/env python3
"""The meeting link in an invitation (meeting.py, #3444): `python3 plugins/calendar/lib/meeting_test.py`.
The invitations are made up in each service's form: no real meeting's address, id or passcode."""

import sys
import unittest
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))

import meeting  # noqa: E402

ZERO = "00000000-0000-0000-0000-000000000000"
TEAMS_JOIN = ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_AAAAbbbbCCCCddddEEEEffff%40thread.v2/0"
              f"?context=%7b%22Tid%22%3a%22{ZERO}%22%7d")
TEAMS_NEW = "https://teams.microsoft.com/meet/000000000000?p=TestOnly"

# Outlook's plain text of a Teams invitation, its options and help links before the join link on purpose
TEAMS_CLASSIC = "\n".join([
    "_" * 80,
    "Microsoft Teams meeting",
    f"Meeting options<https://teams.microsoft.com/meetingOptions/?organizerId={ZERO}>",
    "Join on your computer, mobile app or room device",
    f"Click here to join the meeting<{TEAMS_JOIN}>",
    "Meeting ID: 000 000 000 000",
    "Passcode: Xx0000",
    "Download Teams<https://www.microsoft.com/microsoft-teams/download-app> | "
    "Join on the web<https://www.microsoft.com/microsoft-teams/join-a-meeting>",
    "Learn More<https://aka.ms/JoinTeamsMeeting>",
    "_" * 80,
])
# The newer form: the short address on a line of its own, and System reference
TEAMS_NEWER = "\n".join([
    "Microsoft Teams Need help?<https://aka.ms/JoinTeamsMeeting?omkt=en-US>",
    f"Join the meeting now<{TEAMS_NEW}>",
    "Meeting ID: 000 000 000 000",
    "Passcode: Xx0000",
    "System reference<https://dialin.teams.microsoft.com/usp/pstnconferencing>",
])
GOOGLE = "Join with Google Meet\nhttps://meet.google.com/aaa-bbbb-ccc\nOr dial: +1 000-000-0000 PIN: 000000#"
ZOOM = "Join Zoom Meeting\nhttps://example.zoom.us/j/0000000000?pwd=TestOnly.\n\nMeeting ID: 000 0000 0000"
WEBEX = "Join meeting\nhttps://example.webex.com/example/j.php?MTID=m0000000000000000000000000000000a\nMeeting number: 0000"


class Find(unittest.TestCase):
    def test_teams_classic_skips_options_and_help(self):
        self.assertEqual(meeting.find(notes=TEAMS_CLASSIC), {"url": TEAMS_JOIN, "service": "Teams"})

    def test_teams_newer_form(self):
        self.assertEqual(meeting.find(notes=TEAMS_NEWER), {"url": TEAMS_NEW, "service": "Teams"})

    def test_google_zoom_webex(self):
        self.assertEqual(meeting.find(notes=GOOGLE), {"url": "https://meet.google.com/aaa-bbbb-ccc",
                                                      "service": "Google Meet"})
        # The sentence's full stop isn't the address's
        self.assertEqual(meeting.find(notes=ZOOM)["url"], "https://example.zoom.us/j/0000000000?pwd=TestOnly")
        self.assertEqual(meeting.find(notes=WEBEX)["service"], "Webex")

    def test_url_field_then_place_then_notes(self):
        zoom = "https://example.zoom.us/j/0000000000"
        self.assertEqual(meeting.find(zoom, "https://meet.google.com/aaa-bbbb-ccc", TEAMS_CLASSIC)["url"], zoom)
        self.assertEqual(meeting.find("", "Room 4, https://meet.google.com/aaa-bbbb-ccc", TEAMS_CLASSIC)["service"],
                         "Google Meet")
        self.assertEqual(meeting.find("https://example.com/agenda", "Microsoft Teams Meeting", TEAMS_CLASSIC)["service"],
                         "Teams")

    def test_safe_links_unwrapped(self):
        wrapped = f"https://eur01.safelinks.protection.outlook.com/?url={quote(TEAMS_NEW, safe='')}&data=0&reserved=0"
        self.assertEqual(meeting.find(notes=f"Join<{wrapped}>"), {"url": TEAMS_NEW, "service": "Teams"})

    def test_not_a_meeting(self):
        for text in ["", "Main Street 1", "https://example.com/meet/x", "https://zoom.us/download",
                     "https://meet.google.com/", f"https://teams.microsoft.com/meetingOptions/?organizerId={ZERO}",
                     "https://evil.example/teams.microsoft.com/l/meetup-join/x", "https://notzoom.us/j/1",
                     "https://webex.com.evil.example/meet/x"]:
            self.assertIsNone(meeting.find(text, text, text), text)

    def test_subdomains_count(self):
        self.assertEqual(meeting.service("https://us02web.zoom.us/j/0000000000"), "Zoom")
        self.assertEqual(meeting.service("https://teams.live.com/meet/0000000000000"), "Teams")
        self.assertEqual(meeting.service("https://meet.jit.si/SomeTestRoom"), "Jitsi")


if __name__ == "__main__":
    unittest.main()
