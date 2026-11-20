#!/usr/bin/env python3
"""AppAudio plays a sound file to its end (#3332): `python3 config/quickshell/kit/audio_test.py`.

ffmpeg's pulse output throws away the server's buffer when it closes, so every file lost its last ~2 s. Here AppAudio's
own ffmpeg command (read from the QML in Quickshell, offscreen) plays short and long wav, ogg and mp3 files into a null
sink of a PipeWire of the test's own: no hardware, no network sinks, its own D-Bus, so nothing is heard and the
desktop's sound is left alone. The sink's monitor is recorded, and the tone heard in it must last as long as the file.
"""

import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = ("qs", "ffmpeg", "ffprobe", "pipewire", "pipewire-pulse", "wireplumber", "dbus-run-session", "pactl", "parec")
MISSING = [t for t in TOOLS if not shutil.which(t)]
SLACK = 0.1  # seconds the heard tone may differ from the file

RUNNER = """
import QtQuick
import Quickshell
ShellRoot {
    AppAudio { id: audio; app: "Test"; title: "tone" }
    Timer {
        running: true; interval: 1
        onTriggered: {
            console.warn("CMD " + JSON.stringify([audio.command("FILE", 0), audio.command("FILE", 1.5)]))
            Qt.quit()
        }
    }
}
"""

# The PipeWire's base configs only: the system's conf.d may add network sinks (RAOP finds speakers on the LAN)
WIREPLUMBER = """wireplumber.profiles = {
  main = {
    monitor.alsa = disabled
    monitor.alsa-midi = disabled
    monitor.bluez = disabled
    monitor.bluez.midi = disabled
    monitor.v4l2 = disabled
    monitor.libcamera = disabled
    support.reserve-device = disabled
    support.logind = disabled
  }
}
"""
START = """#!/bin/sh
pipewire & sleep 0.5
pipewire-pulse &
wireplumber &
wait
"""


def commands():
    """AppAudio's argv from the start and from 1.5 s on, with FILE where the file goes."""
    with tempfile.TemporaryDirectory() as d:
        # A copy beside the shell: a type in the shell's own folder needs no import (the kit's folder is outside it)
        shutil.copy(HERE / "AppAudio.qml", d)
        (Path(d) / "shell.qml").write_text(RUNNER)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
        out = subprocess.run(["qs", "-p", d], env=env, capture_output=True, text=True, timeout=30)
    m = re.search(r"CMD (\[.*\])", out.stdout + out.stderr)
    if not m:
        raise AssertionError("no command from AppAudio:\n" + out.stdout + out.stderr)
    return json.loads(m.group(1))


def heard(wav):
    """Seconds from the first sound to the last in a recording."""
    out = subprocess.run(["ffmpeg", "-hide_banner", "-i", wav, "-af", "silencedetect=n=-50dB:d=0.2", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", out)]
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", out)]
    return starts[-1] - ends[0] if ends and starts else 0.0


@unittest.skipUnless(not MISSING, "needs " + ", ".join(MISSING))
class PlaysToTheEnd(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cmds = commands()
        # A short runtime folder: the pulse socket's path has to fit in a sockaddr_un
        cls.tmp = tempfile.mkdtemp(prefix="aa", dir="/tmp")
        t = Path(cls.tmp)
        conf, wp = t / "conf", t / "cfg" / "wireplumber" / "wireplumber.conf.d"
        conf.mkdir()
        wp.mkdir(parents=True)
        for name in ("pipewire.conf", "pipewire-pulse.conf", "client.conf"):
            src = next((p for p in (Path("/usr/share/pipewire") / name, Path("/etc/pipewire") / name) if p.exists()), None)
            if not src:
                raise unittest.SkipTest("no " + name)
            shutil.copy(src, conf / name)
        (wp / "90-test.conf").write_text(WIREPLUMBER)
        (t / "start").write_text(START)
        (t / "start").chmod(0o755)
        cls.env = {k: v for k, v in os.environ.items() if not k.startswith(("PIPEWIRE", "PULSE"))}
        cls.env.update(XDG_RUNTIME_DIR=cls.tmp, XDG_CONFIG_HOME=str(t / "cfg"), XDG_STATE_HOME=str(t / "state"),
                       PIPEWIRE_CONFIG_DIR=str(conf))
        cls.server = subprocess.Popen(["dbus-run-session", "--", str(t / "start")], env=cls.env, cwd=cls.tmp,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(50):
            if subprocess.run(["pactl", "info"], env=cls.env, capture_output=True).returncode == 0:
                break
            time.sleep(0.2)
        else:
            cls.tearDownClass()
            raise unittest.SkipTest("PipeWire didn't start")
        subprocess.run(["pactl", "load-module", "module-null-sink", "sink_name=test"], env=cls.env, check=True,
                       capture_output=True)
        subprocess.run(["pactl", "set-default-sink", "test"], env=cls.env, check=True)
        cls.files = Path(cls.tmp) / "files"
        cls.files.mkdir()

    @classmethod
    def tearDownClass(cls):
        try:
            os.killpg(cls.server.pid, signal.SIGTERM)
            cls.server.wait(5)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            os.killpg(cls.server.pid, signal.SIGKILL)
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def play(self, seconds, ext, start=0):
        """Seconds of tone heard when AppAudio plays a `seconds` long file from `start`."""
        f = self.files / f"t{seconds}.{ext}"
        if not f.exists():
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"sine=f=440:d={seconds}",
                            "-ac", "2", "-ar", "48000", str(f)], check=True)
        argv = [str(f) if a == "FILE" else a for a in self.cmds[1 if start else 0]]
        rec = self.files / "rec.wav"
        r = subprocess.Popen(["parec", "-d", "test.monitor", "--file-format=wav", "--format=s16le",
                              "--rate=48000", "--channels=2", str(rec)], env=self.env)
        try:
            time.sleep(0.5)
            subprocess.run(argv, env=self.env, check=True, timeout=seconds + 15)
            # What is left in the buffer would play now; parec too throws away its own ~2 s buffer when it is stopped
            time.sleep(3)
        finally:
            r.terminate()
            r.wait(5)
        return heard(str(rec))

    def test_short_files(self):
        for ext in ("wav", "ogg", "mp3"):
            with self.subTest(ext):
                self.assertAlmostEqual(self.play(3, ext), 3, delta=SLACK)

    def test_long_file(self):
        self.assertAlmostEqual(self.play(12, "ogg"), 12, delta=SLACK)

    def test_from_a_place_on(self):
        # A resumed pause or a seek: the rest of the file, to its end
        self.assertAlmostEqual(self.play(4, "mp3", start=1.5), 2.5, delta=SLACK)

    def test_command_reads_back(self):
        # The test plays what AppAudio runs: its file and place, into pulse
        argv = self.cmds[1]
        self.assertEqual(argv[argv.index("-i") + 1], "FILE")
        self.assertEqual(argv[argv.index("-ss") + 1], "1.50")
        self.assertIn("pulse", argv)


if __name__ == "__main__":
    unittest.main()
