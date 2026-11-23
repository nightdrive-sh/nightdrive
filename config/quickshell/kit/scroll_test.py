#!/usr/bin/env python3
"""Touchpad scrolling's arithmetic (Scroll.js, #3411): `python3 config/quickshell/kit/scroll_test.py`. Slow fingers move
the content by their own distance, quick ones further and smoothly so; the glide after a lift slows the way WebKit's
macOS glide does and ends; fingers that rested before lifting don't glide; a swipe the same way adds to a glide. And
TouchScroll.qml, which every app links, loads with it in a ListView.

Scroll.js is QML's JavaScript, so it runs in Quickshell (offscreen) and the results come back as JSON."""

import json
import math
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOUCH_SCROLL = HERE.parent / "TouchScroll.qml"

RUNNER = """
import QtQuick
import Quickshell
import "kit/Scroll.js" as S
ShellRoot {
    FloatingWindow {
        implicitWidth: 200; implicitHeight: 200
        ListView { id: list; anchors.fill: parent; model: 100; delegate: Text { text: index }
                   TouchScroll { id: ts; view: list } }
    }
    Timer {
        running: true; interval: 1
        onTriggered: {
            const t = S.TUNING
            const out = { t: t, loaded: ts.view === list }
            out.gain = [0, 100, t.accelFrom, (t.accelFrom + t.accelFull) / 2, t.accelFull, 99999, -99999]
                .map(v => S.gain(v))
            out.gains = []
            for (let v = 0; v <= 4000; v += 10) out.gains.push(S.gain(v))
            // Slow: 2 px every 16 ms (125 px/s); fast: 40 px every 8 ms (5000 px/s)
            const slow = [[0, 2], [16, 2], [32, 2]], fast = [[0, 40], [8, 40], [16, 40]]
            out.trackSlow = S.track(slow, 48, 2)
            out.trackFast = S.track(fast, 24, 40)
            out.trackBack = S.track(fast.map(s => [s[0], -s[1]]), 24, -40)
            // A lift 10 ms after 1000 px/s down; then the same after a 100 ms rest
            const swipe = [[0, 16], [16, 16], [32, 16], [48, 16], [64, 16]]
            out.release = S.release(swipe, 74, 64, 0)
            out.rested = S.release(swipe, 64 + t.liftGap, 64, 0)
            out.carried = S.release(swipe, 74, 64, 2000)
            out.reversed = S.release(swipe, 74, 64, -2000)
            out.tiny = S.release([[0, 1]], 5, 0, 0)
            out.capped = S.release([[0, 900], [8, 900]], 10, 8, 0)
            out.empty = S.release([], 10, 0, 500)
            // The glide from 3000 px/s at 60 Hz: its distance and how long it lasts
            let v = 3000, dist = 0, frames = 0
            while (v !== 0 && frames < 2000) { v = S.decay(v, 1 / 60); dist += v / 60; frames++ }
            out.glide = { dist: dist, frames: frames }
            out.decay8 = S.decay(1000, 0.008)
            out.decayWeak = S.decay(-100, 0.008)
            out.decayStop = S.decay(t.stopSpeed - 1, 0.001)
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class ScrollTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            # As an app has it: TouchScroll.qml beside the kit's folder
            (Path(tmp) / "kit").symlink_to(HERE)
            (Path(tmp) / "TouchScroll.qml").symlink_to(TOUCH_SCROLL)
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER)
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        line = next((l for l in (run.stdout + run.stderr).splitlines() if "RESULT " in l), None)
        if line is None:
            raise AssertionError("Quickshell gave no result:\n" + run.stdout + run.stderr)
        cls.r = json.loads(line.split("RESULT ", 1)[1])
        cls.t = cls.r["t"]

    def test_touch_scroll_loads(self):
        self.assertTrue(self.r["loaded"])

    def test_gain_is_one_when_slow_and_capped_when_fast(self):
        g = self.r["gain"]
        self.assertEqual(g[0], 1)
        self.assertEqual(g[1], 1)
        self.assertEqual(g[2], 1)
        self.assertAlmostEqual(g[3], 1 + (self.t["accelMax"] - 1) / 2)
        self.assertAlmostEqual(g[4], self.t["accelMax"])
        self.assertAlmostEqual(g[5], self.t["accelMax"])
        self.assertAlmostEqual(g[6], self.t["accelMax"], msg="the gain ignores the direction")

    def test_gain_rises_smoothly(self):
        gs = self.r["gains"]
        steps = [b - a for a, b in zip(gs, gs[1:])]
        self.assertTrue(all(s >= 0 for s in steps), "never falls as the fingers speed up")
        self.assertLess(max(steps), 0.02, "no step a finger could feel")

    def test_slow_fingers_move_pixel_for_pixel(self):
        self.assertEqual(self.r["trackSlow"], 2)

    def test_fast_fingers_go_further_either_way(self):
        self.assertAlmostEqual(self.r["trackFast"], 40 * self.t["accelMax"])
        self.assertAlmostEqual(self.r["trackBack"], -40 * self.t["accelMax"])

    def test_release_keeps_the_swipe_speed(self):
        # 80 px in 64 ms, read over the last releaseWindow: about 1000 px/s
        self.assertAlmostEqual(self.r["release"], 80 / 74 * 1000, delta=1)

    def test_fingers_that_rested_do_not_glide(self):
        self.assertEqual(self.r["rested"], 0)
        self.assertEqual(self.r["empty"], 0)
        self.assertEqual(self.r["tiny"], 0)

    def test_a_swipe_the_same_way_adds_to_the_glide(self):
        self.assertAlmostEqual(self.r["carried"], self.r["release"] + 2000, delta=1)
        self.assertAlmostEqual(self.r["reversed"], self.r["release"], delta=1)

    def test_glide_speed_is_capped(self):
        self.assertEqual(self.r["capped"], self.t["maxSpeed"])

    def test_glide_slows_as_webkit_does_and_ends(self):
        self.assertAlmostEqual(self.r["decay8"], 1000 * self.t["friction"])
        # Below weakBelow the friction is stronger: at 100 px/s, 3/5 of the way to slowFriction
        f, s = self.t["friction"], self.t["slowFriction"]
        self.assertAlmostEqual(self.r["decayWeak"], -100 * (f - (f - s) * 0.6))
        self.assertEqual(self.r["decayStop"], 0)
        g = self.r["glide"]
        tau = -0.008 / math.log(f)
        self.assertLess(g["frames"], 2000, "the glide ends")
        self.assertAlmostEqual(g["dist"], 3000 * tau, delta=3000 * tau * 0.1)


if __name__ == "__main__":
    unittest.main()
