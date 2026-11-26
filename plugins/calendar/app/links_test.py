#!/usr/bin/env python3
"""How Calendar shows the links in an event's notes and place (links.js, #3444): `python3 plugins/calendar/app/links_test.py`.
Outlook's "words<URL>" shows the words as the link, "<URL>" and "[URL]" lose their brackets, a long address shows
short but links whole, and Teams' frame of underscores becomes a short rule. The invitation below is made up: no real
meeting's address, id or passcode.

links.js is QML's JavaScript, so it runs in Quickshell (offscreen) and its HTML is read back here."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from html import unescape
from pathlib import Path

HERE = Path(__file__).resolve().parent

RUNNER = """
import QtQuick
import Quickshell
import "%s" as Links
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const out = {}
            for (const [name, text] of Object.entries(%s)) out[name] = Links.rich(text, "green", "gray")
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

# Made up in Teams' form: the thread and tenant ids are zeros and letters, not a meeting's
JOIN = ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_AAAAbbbbCCCCddddEEEEffff%40thread.v2/0"
        "?context=%7b%22Tid%22%3a%2200000000-0000-0000-0000-000000000000%22%7d")
OPTIONS = "https://teams.microsoft.com/meetingOptions/?organizerId=00000000-0000-0000-0000-000000000000"
CASES = {
    "frame": "_" * 80,
    "outlook": f"Click here to join the meeting<{JOIN}>",
    "two": "Download Teams<https://example.com/download> | Join on the web<https://example.com/web>",
    "angle_alone": f"<{OPTIONS}>",
    "bare_long": f"Join: {JOIN}",
    "bare_short": "See https://example.com/a.",
    "bracketed": "Docs [https://example.com/docs]",
    "markdown": "[Agenda](https://example.com/agenda)",
    "bare_then_words": "See https://example.com/a and Join<https://example.com/b>",
    "tags": 'Room <b>4</b> "https://example.com/z"',
    "indent": "  Help<https://example.com/help>",
}


def links(html):
    """Each <a> as (href, its text), unescaped."""
    return [(unescape(h), unescape(t)) for h, t in re.findall(r'<a href="([^"]*)"[^>]*>(.*?)</a>', html)]


def text(html):
    return unescape(re.sub(r"<[^>]+>", "", html))


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Links(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "links.js").as_uri(), json.dumps(CASES)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("links.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def test_outlook_words_are_the_link(self):
        self.assertEqual(links(self.out["outlook"]), [(JOIN, "Click here to join the meeting")])
        self.assertEqual(text(self.out["outlook"]), "Click here to join the meeting")

    def test_two_on_a_line(self):
        self.assertEqual(links(self.out["two"]), [("https://example.com/download", "Download Teams"),
                                                  ("https://example.com/web", "Join on the web")])
        self.assertEqual(text(self.out["two"]), "Download Teams | Join on the web")

    def test_angle_brackets_alone_go(self):
        [(href, shown)] = links(self.out["angle_alone"])
        self.assertEqual(href, OPTIONS)
        self.assertNotIn("<", text(self.out["angle_alone"]))
        self.assertTrue(shown.startswith("teams.microsoft.com/meetingOptions"), shown)

    def test_long_address_shows_short_links_whole(self):
        [(href, shown)] = links(self.out["bare_long"])
        self.assertEqual(href, JOIN)
        self.assertLessEqual(len(shown), 48)
        self.assertTrue(shown.startswith("teams.microsoft.com/l/meetup-join/") and shown.endswith("…"), shown)

    def test_short_address_whole_without_scheme(self):
        self.assertEqual(links(self.out["bare_short"]), [("https://example.com/a", "example.com/a")])
        self.assertEqual(text(self.out["bare_short"]), "See example.com/a.")

    def test_brackets_and_markdown(self):
        self.assertEqual(links(self.out["bracketed"]), [("https://example.com/docs", "example.com/docs")])
        self.assertEqual(links(self.out["markdown"]), [("https://example.com/agenda", "Agenda")])

    def test_an_address_is_not_link_words(self):
        self.assertEqual(links(self.out["bare_then_words"]), [("https://example.com/a", "example.com/a"),
                                                              ("https://example.com/b", "and Join")])

    def test_frame_is_a_short_rule(self):
        self.assertNotIn("_", self.out["frame"])
        self.assertIn('color:gray', self.out["frame"])

    def test_text_is_escaped(self):
        self.assertNotIn("<b>", self.out["tags"])
        self.assertEqual(links(self.out["tags"])[0][0], "https://example.com/z")

    def test_leading_spaces_stay_text(self):
        self.assertEqual(text(self.out["indent"]), "  Help")


if __name__ == "__main__":
    unittest.main()
