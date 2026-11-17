"""Away or at the computer (presence.py): logind's idle hint read right, and a choice made on the page holding only
until the computer sees a change of its own. Nothing here locks the session or waits for it to go idle.

    python3 config/companion/lib/presence_test.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import presence  # noqa: E402

NOW = 1_800_000_000


def show(idle, since):
    return f"IdleHint={'yes' if idle else 'no'}\nIdleSinceHint={int(since * 1e6)}\n"


class IdleTest(unittest.TestCase):
    def test_in_use(self):
        self.assertEqual(presence.idle_seconds(show(False, NOW - 900), NOW), 0)

    def test_idle_counts_from_the_last_input(self):
        # hypridle sets the hint a minute after the last input: four minutes since then is five without input
        self.assertEqual(presence.idle_seconds(show(True, NOW - 240), NOW), 300)

    def test_never_set(self):
        self.assertIsNone(presence.idle_seconds("IdleHint=no\nIdleSinceHint=0\n", NOW))
        self.assertIsNone(presence.idle_seconds("", NOW))


class DetectTest(unittest.TestCase):
    def test_locked_is_away_at_once(self):
        self.assertEqual(presence.detect(idle=lambda: 0, locked=lambda: True), "locked")

    def test_idle_past_the_limit(self):
        self.assertEqual(presence.detect(idle=lambda: presence.IDLE_LIMIT, locked=lambda: False), "idle")
        self.assertEqual(presence.detect(idle=lambda: presence.IDLE_LIMIT - 1, locked=lambda: False), "")

    def test_unknown_idle_is_at_the_computer(self):
        # a desktop that doesn't tell logind: taps keep bringing windows up, as before
        self.assertEqual(presence.detect(idle=lambda: None, locked=lambda: False), "")


class SetTest(unittest.TestCase):
    def setUp(self):
        self.now = ""
        self.p = presence.Presence(detect=lambda: self.now)

    def test_detected(self):
        self.assertEqual(self.p.look(), {"away": False, "why": "", "set": False})
        self.now = "locked"
        self.assertEqual(self.p.look(), {"away": True, "why": "locked", "set": False})

    def test_away_set_holds_until_the_computer_changes(self):
        self.p.set(True)
        self.assertEqual(self.p.look(), {"away": True, "why": "set", "set": True})
        self.now = "idle"           # you left: detected now, the choice no longer needed
        self.assertEqual(self.p.look(), {"away": True, "why": "idle", "set": False})
        self.now = ""               # back at the computer
        self.assertFalse(self.p.look()["away"])

    def test_here_set_while_idle_ends_with_the_lock(self):
        self.now = "idle"
        self.p.set(False)
        self.assertEqual(self.p.look(), {"away": False, "why": "set", "set": True})
        self.now = "locked"
        self.assertEqual(self.p.look(), {"away": True, "why": "locked", "set": False})

    def test_setting_what_is_detected_holds_nothing(self):
        self.now = "locked"
        self.p.set(True)
        self.now = ""
        self.assertFalse(self.p.look()["away"])

    def test_only_true_or_false(self):
        with self.assertRaises(ValueError):
            self.p.set("yes")


if __name__ == "__main__":
    unittest.main()
