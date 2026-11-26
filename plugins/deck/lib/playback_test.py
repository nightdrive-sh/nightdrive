#!/usr/bin/env python3
"""Deck's side of Claude's tools (#1858): `python3 plugins/deck/lib/playback_test.py`. A Deck too old for them says
"update Deck" instead of its usage, and a genre radio starts only from Deck's own list of genres. A stand-in `deck`
on PATH answers, so no real Deck or Spotify is asked."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import playback  # noqa: E402

# What Deck 0.1.1 prints for status --json and ctl save, on stderr with exit status 2
OLD_DECK = 'echo "usage: deck [tui | taste | serve | ctl <toggle|play|pause> | --help | --version]" >&2; exit 2'
GENRES = [
    {"id": "synthwave", "name": "Synthwave", "seeds": [
        {"uri": "spotify:artist:a", "name": "The Midnight"},
        {"uri": "spotify:track:b", "name": "The Midnight · Sunset"},
        {"uri": "spotify:track:c", "name": "FM-84 · Running in the Night"}]},
    {"id": "80s-rock", "name": "80s rock", "seeds": [], "own": True},
]


class StandIn(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin = Path(self.tmp.name)
        path = mock.patch.dict(os.environ, {"PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}"})
        path.start()
        self.addCleanup(path.stop)
        self.addCleanup(self.tmp.cleanup)

    def deck(self, script):
        f = self.bin / "deck"
        f.write_text(f"#!/bin/sh\n{script}\n")
        f.chmod(0o755)


class TooOld(StandIn):
    def test_status_says_update(self):
        self.deck(OLD_DECK)
        with self.assertRaises(playback.Failed) as e:
            playback.status()
        self.assertEqual(str(e.exception), playback.TOO_OLD)

    def test_another_failure_keeps_decks_words(self):
        self.deck('echo "deck: no Deck is running" >&2; exit 1')
        with self.assertRaises(playback.Failed) as e:
            playback.ctl("pause")
        self.assertEqual(str(e.exception), "no Deck is running")


class Genres(StandIn):
    def setUp(self):
        super().setUp()
        self.deck(f"cat <<'EOF'\n{json.dumps(GENRES)}\nEOF")

    def test_list_without_seeds(self):
        self.assertEqual(playback.genres(), [
            {"id": "synthwave", "name": "Synthwave", "artists": ["The Midnight", "FM-84"]},
            {"id": "80s-rock", "name": "80s rock", "artists": [], "own": True},
        ])

    def test_radio_only_from_the_list(self):
        with mock.patch.object(playback, "ctl") as ctl, mock.patch.object(playback, "start_player"):
            for genre in ("vaporwave", "--help", "-x", "Synthwave"):
                with self.assertRaises(playback.Failed):
                    playback.radio(genre)
            ctl.assert_not_called()

    def test_radio_starts(self):
        st = {"playing": True, "title": "Sunset", "artist": "The Midnight", "track_uri": "spotify:track:b",
              "radio": {"genre": "synthwave", "name": "Synthwave"}}
        with mock.patch.object(playback, "ctl") as ctl, mock.patch.object(playback, "start_player"), \
                mock.patch.object(playback, "status", side_effect=[{"track_uri": None}, st]):
            out = playback.radio("synthwave")
        ctl.assert_called_once_with("radio", "synthwave")
        self.assertEqual(out["radio"], "Synthwave")
        self.assertEqual(out["title"], "Sunset")


if __name__ == "__main__":
    unittest.main()
