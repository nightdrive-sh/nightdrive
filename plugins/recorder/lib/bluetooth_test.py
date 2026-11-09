#!/usr/bin/env python3
"""Bluetooth headsets as microphones (#2250): `python3 plugins/recorder/lib/bluetooth_test.py`. A headset in A2DP is
listed by its card; recording from it switches the card to its best headset profile and records from the source that
brings, and save puts the card back in A2DP; so do a crash's recovery and another mic picked during a pause. A headset
that is gone, or whose microphone never appears, is refused in plain words, with the card as it was. pactl is
fake_pactl.py and pw-record fake_pw_record.py: no real headset is touched."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CARD = "bluez_card.34_0E_22_1C_90_DC"


class Headset(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / "run").mkdir()
        self.state = root / "pactl.json"
        self.args = root / "pw-args"
        self.env = dict(os.environ, HOME=str(root), XDG_STATE_HOME=str(root / "state"),
                        XDG_CONFIG_HOME=str(root / "config"), XDG_RUNTIME_DIR=str(root / "run"),
                        RECORDINGS_DIR=str(root / "Recordings"), RECORDER_PACTL=str(HERE / "fake_pactl.py"),
                        FAKE_PACTL_STATE=str(self.state), RECORDER_PW_RECORD=str(HERE / "fake_pw_record.py"),
                        FAKE_PW_ARGS=str(self.args))

    def tearDown(self):
        if self.py("capture.py", "status")["state"] != "idle":
            self.py("capture.py", "save")
        self.tmp.cleanup()

    def py(self, script, *args, ok=True, env=None):
        done = subprocess.run([sys.executable, str(HERE / script), *args, "--json"], capture_output=True, text=True,
                              env=env or self.env, timeout=30)
        if ok:
            self.assertEqual(done.returncode, 0, done.stderr)
            return json.loads(done.stdout)
        return done

    def card(self):
        return json.loads(self.state.read_text()) if self.state.exists() else {"profile": "a2dp-sink", "switches": []}

    def targets(self):
        lines = self.args.read_text().splitlines() if self.args.exists() else []
        return [ln.split("--target ")[1].split(" ")[0] if "--target " in ln else "" for ln in lines]

    def test_listed_in_a2dp(self):
        out = self.py("bluetooth.py", "list")
        self.assertEqual(out, [{"card": CARD, "name": "Jari (AirPods)", "profile": "a2dp-sink",
                                "headset": "headset-head-unit"}])

    def test_record_switches_and_save_switches_back(self):
        st = self.py("capture.py", "record", "--mic", CARD)
        self.assertEqual(st["state"], "recording")
        self.assertEqual(st["mic"], CARD)                       # the card stays the mic: the window names it so
        self.assertEqual(self.card()["profile"], "headset-head-unit")
        self.assertEqual(self.targets(), ["bluez_input.34:0E:22:1C:90:DC"])
        self.py("capture.py", "pause")
        self.py("capture.py", "record")                         # going on: still in headset mode, no new switch
        self.assertEqual(self.card()["switches"], ["headset-head-unit"])
        self.assertEqual(len(self.targets()), 2)
        saved = self.py("capture.py", "save")["saved"]
        self.assertTrue(saved["path"].endswith(".wav"))
        self.assertEqual(self.card()["switches"], ["headset-head-unit", "a2dp-sink"])

    def test_already_headset_left_alone(self):
        self.state.write_text(json.dumps({"profile": "headset-head-unit-msbc", "switches": []}))
        self.py("capture.py", "record", "--mic", CARD)
        self.py("capture.py", "save")
        self.assertEqual(self.card()["switches"], [])

    def test_other_mic_during_pause_gives_it_back(self):
        self.py("capture.py", "record", "--mic", CARD)
        self.py("capture.py", "pause")
        self.py("capture.py", "record", "--mic", "alsa_input.platform-sound")
        self.assertEqual(self.card()["profile"], "a2dp-sink")
        self.assertEqual(self.targets()[-1], "alsa_input.platform-sound")
        self.py("capture.py", "save")
        self.assertEqual(self.card()["switches"], ["headset-head-unit", "a2dp-sink"])

    def test_recovery_gives_it_back(self):
        self.py("capture.py", "record", "--mic", CARD)
        runtime = Path(self.env["XDG_RUNTIME_DIR"]) / "recorder/state.json"
        pid = json.loads(runtime.read_text())["pid"]
        os.kill(pid, 9)
        runtime.unlink()                                       # a reboot: the runtime state is gone
        out = self.py("capture.py", "status")
        self.assertIn("(recovered)", out["recovered"]["name"])
        self.assertEqual(self.card()["profile"], "a2dp-sink")

    def test_no_source_refused_and_restored(self):
        done = self.py("capture.py", "record", "--mic", CARD, ok=False,
                       env=dict(self.env, FAKE_PACTL_NO_SOURCE="1", RECORDER_SOURCE_WAIT="0.3"))
        self.assertEqual(done.returncode, 1)
        self.assertIn("microphone didn't appear", done.stderr)
        self.assertEqual(self.card()["profile"], "a2dp-sink")
        self.assertEqual(self.py("capture.py", "status")["state"], "idle")

    def test_gone_refused(self):
        done = self.py("capture.py", "record", "--mic", "bluez_card.00_11_22_33_44_55", ok=False)
        self.assertEqual(done.returncode, 1)
        self.assertIn("isn't connected", done.stderr)
        self.assertFalse(self.args.exists())


if __name__ == "__main__":
    unittest.main()
