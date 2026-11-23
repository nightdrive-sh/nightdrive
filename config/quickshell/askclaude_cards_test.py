#!/usr/bin/env python3
"""What Ask Claude's result cards say (AskClaudeCards.js, #2245): `python3 config/quickshell/askclaude_cards_test.py`.
A card's source as its domain, its licence's tone (a missing or "unknown" one is the warning, CC0 the free one), its
size and length as people read them, its file type's name, and which turn a card belongs to.

The .js is QML's JavaScript, so it runs in Quickshell (offscreen), as askclaude_markdown_test.py does."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent

RUNNER = """
import QtQuick
import Quickshell
import "%s" as Cards
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const out = {}
            for (const [name, call] of Object.entries(%s))
                out[name] = Cards[call[0]].apply(null, call.slice(1))
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

T = 1_700_000_000_000      # a turn's start, ms: 2023-11-14T22:13:20Z
CARDS = [{"n": 1, "added": "2023-11-14T22:13:20Z"},          # in the turn's first second
         {"n": 2, "added": "2023-11-15T00:14:00+02:00"},     # 40 s in, another offset
         {"n": 3, "added": "2023-11-14T22:13:19Z"},          # before it
         {"n": 4, "added": "2023-11-14T22:15:00Z"}]          # after it ended

CALLS = {
    "domain_www": ["domain", "https://www.Freesound.org/s/1/?x=1"],
    "domain_user_port": ["domain", "http://user@commons.wikimedia.org:8080/wiki"],
    "domain_bad": ["domain", "javascript:alert(1)"],
    "domain_none": ["domain", None],
    "tone_cc0": ["licenceTone", "CC0"],
    "tone_pd": ["licenceTone", "Public Domain Mark 1.0"],
    "tone_by": ["licenceTone", "CC BY 4.0"],
    "tone_site": ["licenceTone", "Pixabay Content License"],
    "tone_unknown": ["licenceTone", "unknown"],
    "tone_empty": ["licenceTone", ""],
    "tone_cc0ish": ["licenceTone", "CC0-like terms"],
    "size_b": ["size", 45],
    "size_kb": ["size", 52113],
    "size_small_mb": ["size", 1.5 * 1024 * 1024],
    "size_mb": ["size", 25 * 1024 * 1024],
    "size_bad": ["size", None],
    "dur_s": ["duration", 6.2],
    "dur_m": ["duration", 75.4],
    "dur_h": ["duration", 3723],
    "dur_unknown": ["duration", None],
    "kind_pdf": ["kind", {"mime": "application/pdf", "file": "x.pdf"}],
    "kind_mp3": ["kind", {"mime": "audio/mpeg", "file": "a.mp3"}],
    "kind_ext": ["kind", {"mime": "audio/ogg", "file": "engine.ogg"}],
    "during": ["during", CARDS, T + 500, T + 60_000],
    "during_running": ["during", CARDS, T, 1e308],
}


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class AskClaudeCards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "AskClaudeCards.js").as_uri(), json.dumps(CALLS)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("AskClaudeCards.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def test_domain(self):
        self.assertEqual(self.out["domain_www"], "freesound.org")
        self.assertEqual(self.out["domain_user_port"], "commons.wikimedia.org")
        self.assertEqual(self.out["domain_bad"], "")
        self.assertEqual(self.out["domain_none"], "")

    def test_licence_tone(self):
        self.assertEqual([self.out[k] for k in ("tone_cc0", "tone_pd", "tone_by", "tone_site")],
                         ["free", "free", "terms", "terms"])
        self.assertEqual([self.out[k] for k in ("tone_unknown", "tone_empty")], ["unknown", "unknown"])

    def test_size(self):
        self.assertEqual([self.out[k] for k in ("size_b", "size_kb", "size_small_mb", "size_mb", "size_bad")],
                         ["45 B", "51 KB", "1.5 MB", "25 MB", ""])

    def test_duration(self):
        self.assertEqual([self.out[k] for k in ("dur_s", "dur_m", "dur_h", "dur_unknown")],
                         ["0:06", "1:15", "1:02:03", ""])

    def test_kind(self):
        self.assertEqual([self.out[k] for k in ("kind_pdf", "kind_mp3", "kind_ext")], ["PDF", "MP3", "OGG"])

    def test_cards_of_a_turn(self):
        self.assertEqual([c["n"] for c in self.out["during"]], [1, 2])
        self.assertEqual([c["n"] for c in self.out["during_running"]], [1, 2, 4])


if __name__ == "__main__":
    unittest.main()
