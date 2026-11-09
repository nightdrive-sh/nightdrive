#!/usr/bin/env python3
"""Recorder's transcription (#2251): `python3 plugins/recorder/lib/transcribe_test.py`. A recording is cut at its
quiet moments, not every minute on the dot; each piece goes to the model Settings picked at 16 kHz, through the user's
own corrections, into NAME.txt with its time; the work runs in the background, one at a time, and can be cancelled,
leaving the transcript before it; a failure says why and keeps that transcript too; a missing Voxtype or model is
named with what to install. fake_voxtype.py stands in for Voxtype; ffmpeg makes and cuts the sound."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import voxtype  # noqa: E402

# A tone of 150 s with silences at 50–53 s (long) and 110–111 s: the cuts go in their middles
LENGTH = 150
SOUND = f"aevalsrc=0.5*sin(2*PI*440*t)*not(between(t\\,50\\,53))*not(between(t\\,110\\,111)):s=48000:d={LENGTH}"


class CutPoints(unittest.TestCase):
    def test_short_recording_is_one_piece(self):
        self.assertEqual(voxtype.cut_points(70, []), [])

    def test_longest_silence_in_the_window_wins(self):
        quiet = [(30, 32), (50, 50.4), (62, 64), (80, 90)]   # 30–32 too early, 80–90 too late
        self.assertEqual(voxtype.cut_points(100, quiet), [63.0])

    def test_no_silence_cuts_every_minute(self):
        self.assertEqual(voxtype.cut_points(190, []), [60.0, 120.0])

    def test_each_window_counts_from_the_cut_before(self):
        self.assertEqual(voxtype.cut_points(160, [(70, 72), (119, 121)]), [71.0, 120.0])


@unittest.skipUnless(shutil.which("ffmpeg"), "needs ffmpeg (ffmpeg-free)")
class Transcribe(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.rec = root / "Recordings"
        self.rec.mkdir()
        bin_dir, models, cfg = root / "bin", root / "data/voxtype/models", root / "config"
        for d in (bin_dir, models, cfg / "voxtype", root / "run"):
            d.mkdir(parents=True)
        for name in ("voxtype", "voxtype-onnx"):
            (bin_dir / name).symlink_to(HERE / "fake_voxtype.py")
        (models / "parakeet-tdt-0.6b-v3-int8").mkdir()
        (models / "ggml-large-v3-turbo.bin").write_bytes(b"")
        post = cfg / "voxtype/post-process"      # the user's corrections: here, "parakeet" made "Parakeet"
        post.write_text("#!/bin/sh\nsed 's/parakeet/Parakeet/'\n")
        post.chmod(0o755)
        self.log = root / "calls.log"
        self.env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(cfg), XDG_DATA_HOME=str(root / "data"),
                        XDG_STATE_HOME=str(root / "state"), XDG_RUNTIME_DIR=str(root / "run"),
                        RECORDINGS_DIR=str(self.rec), RECORDER_VOXTYPE_DIR=str(bin_dir),
                        FAKE_VOXTYPE_LOG=str(self.log))
        subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi", "-i", SOUND, "-ac", "1",
                        "-c:a", "pcm_s16le", str(self.rec / "Talk.wav")], check=True)

    def tearDown(self):
        for job in self.status():   # nothing left running after a test
            self.py("transcribe.py", "cancel", job["name"], ok=None)
        self.tmp.cleanup()

    def py(self, script, *args, ok=True, env=None):
        done = subprocess.run([sys.executable, str(HERE / script), *args, "--json"], capture_output=True, text=True,
                              env=env or self.env, timeout=60)
        if ok is True:
            self.assertEqual(done.returncode, 0, done.stderr)
            return json.loads(done.stdout)
        if ok is False:
            self.assertEqual(done.returncode, 1, done.stdout)
            return done.stderr.strip()
        return done

    def status(self):
        return self.py("transcribe.py", "status")["jobs"]

    def wait_until(self, test, seconds=30):
        end = time.time() + seconds
        while time.time() < end:
            if test():
                return
            time.sleep(0.1)
        self.fail("timed out")

    def test_transcript_has_a_paragraph_for_each_piece_with_its_time(self):
        self.py("transcribe.py", "run", "Talk")
        text = (self.rec / "Talk.txt").read_text()
        # Cut at 51.5 s and 110.5 s; 16 kHz pieces; the corrections applied; parakeet has no language
        self.assertEqual(text, "[00:00] Parakeet - 16000 52s\n\n[00:51] Parakeet - 16000 59s\n\n"
                               "[01:50] Parakeet - 16000 39s\n")
        calls = self.log.read_text().splitlines()
        self.assertEqual(len(calls), 3)
        self.assertTrue(calls[0].startswith("voxtype-onnx -q --engine parakeet --model parakeet-tdt-0.6b-v3-int8"))
        self.assertEqual(self.status(), [])
        self.assertFalse(list(self.rec.glob(".*")))           # no half-written file left

    def test_whisper_gets_its_language(self):
        self.py("settings.py", "set", "model", "whisper")
        self.py("settings.py", "set", "language", "fi")
        self.py("transcribe.py", "run", "Talk")
        self.assertIn("[00:00] whisper fi 16000 52s", (self.rec / "Talk.txt").read_text())
        self.assertTrue(self.log.read_text().startswith("voxtype -q --engine whisper --model large-v3-turbo"))

    def test_medium_is_whisper_medium_with_its_language(self):
        (Path(self.env["XDG_DATA_HOME"]) / "voxtype/models/ggml-medium.bin").write_bytes(b"")
        self.py("settings.py", "set", "model", "medium")
        self.py("settings.py", "set", "language", "en")
        self.py("transcribe.py", "run", "Talk")
        self.assertIn("[00:00] whisper en 16000 52s", (self.rec / "Talk.txt").read_text())
        self.assertTrue(self.log.read_text().startswith("voxtype -q --engine whisper --model medium --language en"))

    def test_start_runs_in_the_background_and_lists_its_progress(self):
        env = dict(self.env, FAKE_VOXTYPE_SLEEP="0.5")
        job = self.py("transcribe.py", "start", "Talk", env=env)
        self.assertEqual((job["name"], job["state"], job["model"]), ("Talk", "queued", "parakeet"))
        self.wait_until(lambda: any(j["state"] == "running" and j["total"] == 3 for j in self.status()))
        self.wait_until(lambda: not self.status())
        self.assertTrue((self.rec / "Talk.txt").read_text().startswith("[00:00] "))
        self.assertTrue(self.py("recordings.py", "info", "Talk")["transcript"])

    def test_cancel_stops_it_and_keeps_the_transcript_before_it(self):
        (self.rec / "Talk.txt").write_text("the old one\n")
        self.py("transcribe.py", "start", "Talk", env=dict(self.env, FAKE_VOXTYPE_SLEEP="5"))
        self.wait_until(lambda: any(j["state"] == "running" for j in self.status()))
        self.assertEqual(self.py("transcribe.py", "cancel", "Talk")["state"], "cancelled")
        self.assertEqual(self.status(), [])
        time.sleep(0.5)
        self.assertEqual((self.rec / "Talk.txt").read_text(), "the old one\n")
        self.assertFalse(list((Path(self.env["XDG_RUNTIME_DIR"]) / "recorder").glob("transcribe-*")))
        self.assertIn("isn't being transcribed", self.py("transcribe.py", "cancel", "Talk", ok=False))

    def test_a_failure_says_why_and_keeps_the_transcript_before_it(self):
        (self.rec / "Talk.txt").write_text("the old one\n")
        self.py("transcribe.py", "start", "Talk", env=dict(self.env, FAKE_VOXTYPE_FAIL="1"))
        self.wait_until(lambda: any(j["state"] == "failed" for j in self.status()))
        self.assertIn("the model is broken", self.status()[0]["error"])
        self.assertEqual((self.rec / "Talk.txt").read_text(), "the old one\n")
        self.py("transcribe.py", "cancel", "Talk")          # dismissed
        self.assertEqual(self.status(), [])

    def test_missing_voxtype_or_model_names_what_to_install(self):
        env = dict(self.env, RECORDER_VOXTYPE_DIR=str(Path(self.tmp.name) / "none"), PATH="/usr/bin:/bin")
        self.assertIn("Dictation", self.py("transcribe.py", "start", "Talk", ok=False, env=env))
        shutil.rmtree(Path(self.env["XDG_DATA_HOME"]) / "voxtype/models/parakeet-tdt-0.6b-v3-int8")
        self.assertIn("voxtype-onnx setup --download --model parakeet-tdt-0.6b-v3-int8",
                      self.py("transcribe.py", "start", "Talk", ok=False))
        check = self.py("voxtype.py", "check")
        self.assertEqual((check["parakeet"]["ready"], check["whisper"]["ready"]), (False, True))
        self.assertEqual(self.status(), [])

    def test_unknown_recording_is_refused(self):
        self.assertIn("Nope", self.py("transcribe.py", "start", "Nope", ok=False))


if __name__ == "__main__":
    unittest.main()
