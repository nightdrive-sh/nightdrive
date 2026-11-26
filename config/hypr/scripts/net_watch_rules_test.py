#!/usr/bin/env python3
"""net-watch's rules (#2057): `python3 config/hypr/scripts/net_watch_rules_test.py`. A drop is told only when it holds,
never after login or waking for a while, never for a connection the user turned off; "back" only after a "lost"."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from net_watch_rules import DEBOUNCE, FULL, GRACE, LIMITED, NONE, PORTAL, UNKNOWN, Watch  # noqa: E402


def online(t=0.0):
    """A watch past its grace, connected with full internet."""
    w = Watch(t - GRACE - 1)
    w.step(t, conn=FULL, up=True)
    return w


class Rules(unittest.TestCase):
    def test_drop_told_once_it_holds(self):
        w = online()
        self.assertEqual(w.step(100, conn=LIMITED), ([], 100 + DEBOUNCE))
        self.assertEqual(w.step(100 + DEBOUNCE - 1), ([], 100 + DEBOUNCE))
        self.assertEqual(w.step(100 + DEBOUNCE), (["lost"], None))
        self.assertEqual(w.step(120, conn=NONE), ([], None))   # limited → none: still the same "lost"
        self.assertEqual(w.step(130, conn=FULL), (["back"], None))

    def test_blip_unseen(self):
        w = online()
        w.step(100, conn=NONE)
        self.assertEqual(w.step(105, conn=FULL), ([], None))
        self.assertEqual(w.step(100 + DEBOUNCE), ([], None))

    def test_no_back_without_lost(self):
        w = online()
        self.assertEqual(w.step(5, conn=FULL), ([], None))

    def test_unknown_is_fine(self):   # NM without a connectivity check never says more
        w = online()
        self.assertEqual(w.step(100, conn=UNKNOWN), ([], None))

    def test_grace_after_login(self):
        w = Watch(0)
        _, wake = w.step(1, conn=NONE, up=True)
        self.assertEqual(wake, GRACE)
        self.assertEqual(w.step(GRACE - 1)[0], [])
        self.assertEqual(w.step(GRACE)[0], ["lost"])

    def test_grace_after_wake_and_sleep_clears(self):
        w = online()
        w.step(100, conn=NONE)
        w.step(100 + DEBOUNCE)
        self.assertEqual(w.step(200, asleep=True), (["clear"], None))
        self.assertEqual(w.step(201, conn=NONE, up=False), ([], None))
        self.assertEqual(w.step(500, asleep=False), ([], None))
        _, wake = w.step(505, up=True)
        self.assertEqual(wake, 500 + GRACE)
        self.assertEqual(w.step(512, conn=FULL), ([], None))   # online before the grace ran out: no word at all

    def test_user_turns_wifi_off(self):
        w = online()
        w.step(100, conn=NONE)
        self.assertEqual(w.step(103, up=False), ([], None))         # off before it was told: nothing
        self.assertEqual(w.step(100 + DEBOUNCE), ([], None))
        w.step(200, up=True, conn=NONE)
        w.step(200 + DEBOUNCE)
        self.assertEqual(w.step(300, up=False), (["clear"], None))  # off after: the card goes, no "back"

    def test_portal(self):
        w = Watch(0)
        _, wake = w.step(1, conn=PORTAL, up=True)   # no grace for a portal
        self.assertEqual(w.step(wake)[0], ["portal"])
        self.assertEqual(w.step(60, conn=FULL)[0], ["back"])

    def test_lost_then_portal(self):
        w = online()
        w.step(100, conn=NONE)
        w.step(100 + DEBOUNCE)
        _, wake = w.step(150, conn=PORTAL)
        self.assertEqual(w.step(wake)[0], ["portal"])


if __name__ == "__main__":
    unittest.main()
