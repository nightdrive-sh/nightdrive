#!/usr/bin/env python3
"""Recorder's core (#2248): `python3 plugins/recorder/lib/capture_test.py`. A recording made of pieces across pauses
is saved as one WAV as long as they are; toggle and new do what a key does; a pw-record that dies is a pause, one
that can't start leaves nothing behind; pieces left by a crash come back as "(recovered)", even with a header that
was never finished; the recordings are listed, renamed with their files, never overwritten; settings refuse what the
window couldn't show. pw-record is fake_pw_record.py, which writes silence; nothing touches the sound system."""

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import wav   # noqa: E402

RUN = 0.4   # seconds a piece records for in a test


class Env(unittest.TestCase):
    """Each test in a home of its own: state, settings, runtime and the recordings' folder."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.rec = root / "Recordings"
        # XDG_DATA_HOME: no Voxtype model, so a save isn't transcribed (transcribe_test's part)
        self.env = dict(os.environ, XDG_DATA_HOME=str(root / "data"), XDG_STATE_HOME=str(root / "state"),
                        XDG_CONFIG_HOME=str(root / "config"), XDG_RUNTIME_DIR=str(root / "run"),
                        RECORDINGS_DIR=str(self.rec), HOME=str(root),
                        RECORDER_PW_RECORD=str(HERE / "fake_pw_record.py"))
        (root / "run").mkdir()

    def tearDown(self):
        state = self.cap("status")
        if state["state"] == "recording":
            self.cap("save")
        self.tmp.cleanup()

    def run_py(self, script, *args, env=None, ok=True):
        done = subprocess.run([sys.executable, str(HERE / script), *args, "--json"], capture_output=True, text=True,
                              env=env or self.env, timeout=20)
        if ok:
            self.assertEqual(done.returncode, 0, done.stderr)
            return json.loads(done.stdout)
        return done

    def cap(self, *args, **kw):
        return self.run_py("capture.py", *args, **kw)

    def recs(self, *args, **kw):
        return self.run_py("recordings.py", *args, **kw)

    def runtime_state(self):
        return json.loads((Path(self.env["XDG_RUNTIME_DIR"]) / "recorder/state.json").read_text())


class Wav(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def piece(self, name, frames, header_says=None):
        p = self.dir / name
        p.write_bytes(wav.header(48000, 1, 16, frames * 2 if header_says is None else header_says) + b"\1\0" * frames)
        return p

    def test_length_from_the_header(self):
        self.assertAlmostEqual(wav.duration(self.piece("a.wav", 24000)), 0.5)

    def test_unfinished_header_takes_the_file(self):
        self.assertAlmostEqual(wav.duration(self.piece("a.wav", 48000, header_says=0)), 1.0)
        self.assertAlmostEqual(wav.duration(self.piece("b.wav", 48000, header_says=10**9)), 1.0)

    def test_join_keeps_every_frame(self):
        out = self.dir / "out.wav"
        info = wav.join([self.piece("a.wav", 4800), self.piece("b.wav", 9600, header_says=0)], out)
        self.assertEqual(info.length, 14400 * 2)
        self.assertAlmostEqual(wav.duration(out), 0.3)
        self.assertEqual(out.read_bytes()[44:], b"\1\0" * 14400)

    def test_nothing_to_join(self):
        (self.dir / "junk.wav").write_bytes(b"not a wav")
        with self.assertRaises(wav.WavError):
            wav.join([self.piece("a.wav", 0), self.dir / "junk.wav"], self.dir / "out.wav")
        self.assertFalse((self.dir / "out.wav").exists())


class Capture(Env):
    def test_idle(self):
        self.assertEqual(self.cap("status")["state"], "idle")

    def test_pieces_across_a_pause_make_one_recording(self):
        self.assertEqual(self.cap("record", "--name", "Playtest")["state"], "recording")
        time.sleep(RUN)
        paused = self.cap("pause")
        self.assertEqual(paused["state"], "paused")
        self.assertGreater(paused["elapsed"], RUN * 0.8)
        time.sleep(RUN)   # a pause doesn't count
        self.assertAlmostEqual(self.cap("status")["elapsed"], paused["elapsed"], delta=0.05)
        self.cap("record")
        time.sleep(RUN)
        shown = self.cap("pause")["elapsed"]
        out = self.cap("save")
        self.assertEqual(out["state"], "idle")
        self.assertEqual(out["saved"]["name"], "Playtest")
        self.assertAlmostEqual(out["saved"]["duration"], shown, delta=0.1)   # the clock tells the file's length
        self.assertEqual([p.name for p in self.rec.iterdir()], ["Playtest.wav"])
        self.assertFalse(any((Path(self.env["XDG_STATE_HOME"]) / "recorder/session").glob("*")))

    def test_toggle_records_pauses_and_goes_on(self):
        self.assertEqual([self.cap("toggle")["state"] for _ in range(3)], ["recording", "paused", "recording"])

    def test_new_saves_and_starts_the_next(self):
        first = self.cap("record", "--name", "One")
        time.sleep(RUN)
        out = self.cap("new", "--name", "Two")
        self.assertEqual(out["saved"]["name"], "One")
        self.assertEqual((out["state"], out["name"]), ("recording", "Two"))
        self.assertLess(out["elapsed"], RUN)
        self.assertEqual(first["state"], "recording")

    def test_a_saved_name_is_never_overwritten(self):
        self.rec.mkdir()
        (self.rec / "Take.txt").write_text("an older transcript")
        self.cap("record", "--name", "Take")
        time.sleep(RUN)
        self.assertEqual(self.cap("save")["saved"]["name"], "Take (2)")

    def test_a_pw_record_that_dies_is_a_pause(self):
        self.cap("record")
        time.sleep(RUN)
        os.kill(self.runtime_state()["pid"], signal.SIGKILL)
        time.sleep(0.2)
        state = self.cap("status")
        self.assertEqual(state["state"], "paused")
        self.assertGreater(state["elapsed"], RUN * 0.5)

    def test_a_pw_record_that_cant_start_leaves_nothing(self):
        done = self.cap("record", env=dict(self.env, FAKE_PW_FAIL="1"), ok=False)
        self.assertEqual(done.returncode, 1)
        self.assertIn("Host is down", done.stderr)
        self.assertEqual(self.cap("status")["state"], "idle")

    def test_save_with_nothing_recorded(self):
        done = self.cap("save", ok=False)
        self.assertEqual((done.returncode, done.stderr.strip()), (1, "Nothing is being recorded."))

    def test_a_cut_off_recording_comes_back(self):
        self.cap("record", "--name", "Idea")
        time.sleep(RUN)
        state = self.runtime_state()
        os.kill(state["pid"], signal.SIGKILL)       # its header still says 0 bytes
        (Path(self.env["XDG_RUNTIME_DIR"]) / "recorder/state.json").unlink()   # a reboot clears the runtime
        out = self.cap("status")
        self.assertEqual(out["state"], "idle")
        self.assertEqual(out["recovered"]["name"], "Idea (recovered)")
        self.assertGreater(out["recovered"]["duration"], RUN * 0.5)
        self.assertNotIn("recovered", self.cap("status"))   # once


class Recordings(Env):
    def make(self, name, seconds=0.1, transcript=False):
        self.rec.mkdir(exist_ok=True)
        p = self.rec / f"{name}.wav"
        frames = int(48000 * seconds)
        p.write_bytes(wav.header(48000, 1, 16, frames * 2) + b"\0\0" * frames)
        if transcript:
            p.with_suffix(".txt").write_text("[00:00] hello")
        return p

    def test_list_newest_first(self):
        old = self.make("Old", 1.5)
        os.utime(old, (time.time() - 60,) * 2)
        self.make("New", transcript=True)
        out = self.recs("list")
        self.assertEqual([r["name"] for r in out["recordings"]], ["New", "Old"])
        self.assertEqual(out["recordings"][1]["duration"], 1.5)
        self.assertTrue(out["recordings"][0]["transcript"].endswith("New.txt"))
        self.assertEqual(self.recs("list", "--limit", "1")["total"], 2)

    def test_no_folder_yet(self):
        self.assertEqual(self.recs("list")["recordings"], [])

    def test_rename_takes_its_files(self):
        self.make("Take", transcript=True)
        (self.rec / "Take.mp3").write_bytes(b"x")
        out = self.recs("rename", "Take", "Level 3 notes")
        self.assertEqual((out["name"], out["was"]), ("Level 3 notes", "Take"))
        self.assertEqual(sorted(p.name for p in self.rec.iterdir()),
                         ["Level 3 notes.mp3", "Level 3 notes.txt", "Level 3 notes.wav"])

    def test_transcript(self):
        self.make("Talk", transcript=True)
        out = self.recs("transcript", "Talk")
        self.assertEqual((out["name"], out["text"]), ("Talk", "[00:00] hello"))
        self.make("Silent")
        done = self.recs("transcript", "Silent", ok=False)
        self.assertEqual((done.returncode, done.stderr.strip()),
                         (1, "Silent has no transcript yet: recorder transcribe makes one."))

    def test_rename_onto_another(self):
        self.make("A")
        self.make("B")
        done = self.recs("rename", "A", "B", ok=False)
        self.assertEqual((done.returncode, done.stderr.strip()), (1, "There is a recording B already."))

    def test_names_are_file_names(self):
        self.make("x")
        self.assertEqual(self.recs("rename", "x", "../a/b.wav")["name"], "a b")
        self.assertEqual(self.recs("info", str(self.rec / "a b.wav"))["name"], "a b")
        done = self.recs("info", "/etc/passwd", ok=False)
        self.assertIn("isn't in your recordings' folder", done.stderr)


class Settings(Env):
    def test_defaults_and_a_change(self):
        out = self.run_py("settings.py", "get")
        self.assertEqual((out["model"], out["transcribe_on_save"], out["path"]), ("parakeet", True, str(self.rec)))
        self.assertFalse(self.run_py("settings.py", "set", "transcribe_on_save", "off")["transcribe_on_save"])
        self.assertEqual(self.run_py("settings.py", "set", "model", "whisper")["model"], "whisper")

    def test_refused(self):
        for key, value in (("model", "tiny"), ("language", "sv"), ("nope", "1"), ("transcribe_on_save", "maybe")):
            self.assertEqual(self.run_py("settings.py", "set", key, value, ok=False).returncode, 1)

    def test_a_hand_edited_file(self):
        cfg = Path(self.env["XDG_CONFIG_HOME"]) / "recorder/settings.json"
        cfg.parent.mkdir(parents=True)
        cfg.write_text('{"model": "huge", "mic": 5, "language": "fi"}')
        out = self.run_py("settings.py", "get")
        self.assertEqual((out["model"], out["mic"], out["language"]), ("parakeet", "", "fi"))


if __name__ == "__main__":
    unittest.main()
