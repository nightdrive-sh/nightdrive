#!/usr/bin/env python3
"""Recorder's export (#2250): `python3 plugins/recorder/lib/export_test.py`. A recording exports into each format
beside its WAV, as that format and as long; an export made again replaces the one before; a failed one leaves no half
file; a rename takes the exports along (recordings.files_of); a format or recording that isn't there is refused
in plain words. ffmpeg makes the sound; nothing touches the sound system."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SECONDS = 2


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "needs ffmpeg and ffprobe (ffmpeg-free)")
class Export(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.rec = root / "Recordings"
        self.rec.mkdir()
        self.env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / "config"), RECORDINGS_DIR=str(self.rec))
        # A tone, as pw-record writes: 48 kHz mono 16-bit
        subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi", "-i", f"sine=f=440:d={SECONDS}",
                        "-ar", "48000", "-ac", "1", "-c:a", "pcm_s16le", str(self.rec / "Talk.wav")], check=True)

    def tearDown(self):
        self.tmp.cleanup()

    def run_py(self, *args, ok=True, env=None):
        done = subprocess.run([sys.executable, str(HERE / "export.py"), *args, "--json"], capture_output=True,
                              text=True, env=env or self.env, timeout=60)
        if ok:
            self.assertEqual(done.returncode, 0, done.stderr)
            return json.loads(done.stdout)
        return done

    def probe(self, path):
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name:format=duration",
                              "-of", "json", str(path)], capture_output=True, text=True, check=True).stdout
        data = json.loads(out)
        return data["streams"][0]["codec_name"], float(data["format"]["duration"])

    def test_each_format(self):
        codecs = {"mp3": "mp3", "m4a": "aac", "flac": "flac", "opus": "opus"}
        for fmt, codec in codecs.items():
            with self.subTest(fmt=fmt):
                out = self.run_py("Talk", fmt.upper() if fmt == "mp3" else fmt)
                path = self.rec / f"Talk.{fmt}"
                self.assertEqual(out["export"], str(path))
                self.assertEqual(out["format"], fmt)
                self.assertGreater(out["export_size"], 0)
                found, seconds = self.probe(path)
                self.assertEqual(found, codec)
                self.assertAlmostEqual(seconds, SECONDS, delta=0.2)
        listed = self.run_py("Talk", "flac")["exports"]
        self.assertEqual(sorted(Path(p).suffix for p in listed), [".flac", ".m4a", ".mp3", ".opus"])
        self.assertEqual([p.name for p in self.rec.iterdir() if p.name.startswith(".")], [])

    def test_again_replaces(self):
        self.run_py("Talk", "mp3")
        (self.rec / "Talk.mp3").write_bytes(b"old")
        self.run_py("Talk", "mp3")
        self.assertEqual(self.probe(self.rec / "Talk.mp3")[0], "mp3")

    def test_failed_leaves_nothing(self):
        (self.rec / "Talk.mp3").write_bytes(b"before")
        broken = self.rec / "Broken.wav"
        broken.write_bytes(b"RIFF\0\0\0\0WAVEjunk")
        done = self.run_py("Broken", "mp3", ok=False)
        self.assertEqual(done.returncode, 1)
        self.assertIn("MP3 export failed", done.stderr)
        self.assertFalse((self.rec / "Broken.mp3").exists())
        self.assertEqual(sorted(p.name for p in self.rec.iterdir()), ["Broken.wav", "Talk.mp3", "Talk.wav"])

    def test_refused(self):
        done = self.run_py("Talk", "ogg", ok=False)
        self.assertEqual(done.returncode, 1)
        self.assertIn("mp3, m4a, flac, opus", done.stderr)
        done = self.run_py("Nobody", "mp3", ok=False)
        self.assertEqual(done.returncode, 1)
        self.assertIn("No recording Nobody", done.stderr)
        done = self.run_py("Talk", "mp3", ok=False, env=dict(self.env, RECORDER_FFMPEG="/nonexistent/ffmpeg"))
        self.assertIn("ffmpeg-free", done.stderr)

    def test_rename_takes_it_along(self):
        self.run_py("Talk", "opus")
        recs = [sys.executable, str(HERE / "recordings.py")]
        subprocess.run(recs + ["rename", "Talk", "Meeting"], check=True, env=self.env, capture_output=True)
        self.assertEqual(sorted(p.name for p in self.rec.iterdir()), ["Meeting.opus", "Meeting.wav"])

    def test_formats(self):
        out = self.run_py("formats")
        self.assertEqual([f["format"] for f in out], ["mp3", "m4a", "flac", "opus"])
        self.assertTrue(all(f["label"] and f["about"] for f in out))


if __name__ == "__main__":
    unittest.main()
