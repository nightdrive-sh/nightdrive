#!/usr/bin/env python3
"""Arriving at and leaving places (#3277): `python3 config/hypr/scripts/place_rules_test.py`. An arrival only after
ARRIVE_GAP away, sleep included; a leaving only after LEAVE_HOLD without the network; waking gives the network time."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from place_rules import ARRIVE_GAP, LEAVE_HOLD, here, step  # noqa: E402

WORK = {"name": "work", "wifi": ["Feature"]}
HOME = {"name": "home", "wifi": ["Koti", "Koti 5G"]}
ROWS = [WORK, HOME]
H = 3600
FRI_5PM = 1_800_000_000
MON_8AM = FRI_5PM + 2 * 24 * H + 15 * H


def at_work(t=0):
    """A state that has been at work since before t (the place known, here)."""
    state = {}
    step(state, ROWS, ["Feature"], t - 10)
    return state


class Arriving(unittest.TestCase):
    def test_friday_to_monday_at_work_is_arriving(self):
        s = at_work(FRI_5PM)
        self.assertEqual(step(s, ROWS, ["Feature"], FRI_5PM, "sleep"), ([], None))
        # The network may already be up when the wake is told, or come up a moment later: an arrival either way
        self.assertEqual(step(s, ROWS, ["Feature"], MON_8AM, "wake")[0], [("arrive", "work")])
        s = at_work(FRI_5PM)
        step(s, ROWS, ["Feature"], FRI_5PM, "sleep")
        self.assertEqual(step(s, ROWS, [], MON_8AM, "wake"), ([], MON_8AM + LEAVE_HOLD))
        self.assertEqual(step(s, ROWS, ["Feature"], MON_8AM + 20)[0], [("arrive", "work")])

    def test_lunch_nap_at_work_is_not(self):
        s = at_work(12 * H)
        step(s, ROWS, ["Feature"], 12 * H, "sleep")
        self.assertEqual(step(s, ROWS, [], 12 * H + 1800, "wake"), ([], 12 * H + 1800 + LEAVE_HOLD))
        self.assertEqual(step(s, ROWS, ["Feature"], 12 * H + 1810), ([], None))
        self.assertEqual(here(s), ["work"])

    def test_once_per_arrival(self):
        s = {}
        step(s, ROWS, ["Koti"], 0)
        step(s, ROWS, [], 10)
        step(s, ROWS, [], 10 + LEAVE_HOLD)          # left home
        events, _ = step(s, ROWS, ["Feature"], 3 * H)
        self.assertEqual(events, [("arrive", "work")])
        self.assertEqual(step(s, ROWS, ["Feature"], 3 * H + 60), ([], None))   # unlock, another check: nothing

    def test_back_soon_after_leaving_is_not_arriving(self):
        s = at_work(0)
        step(s, ROWS, [], 100)
        self.assertEqual(step(s, ROWS, [], 100 + LEAVE_HOLD)[0], [("leave", "work")])
        self.assertEqual(step(s, ROWS, ["Feature"], 100 + 1800), ([], None))   # out for lunch, 30 min
        step(s, ROWS, [], 4 * H)
        step(s, ROWS, [], 4 * H + LEAVE_HOLD)
        self.assertEqual(step(s, ROWS, ["Feature"], 4 * H + ARRIVE_GAP + 1)[0], [("arrive", "work")])

    def test_new_place_is_taken_as_it_is(self):
        s = {}
        self.assertEqual(step(s, [WORK], ["Feature"], 0), ([], None))   # `places add work` at work: no arrival
        self.assertEqual(here(s), ["work"])
        self.assertEqual(step(s, ROWS, ["Feature", "Koti"], 10), ([], None))   # home added there later: the same
        self.assertEqual(sorted(here(s)), ["home", "work"])

    def test_first_arrival_at_a_place_never_seen(self):
        s = {}
        step(s, ROWS, [], 0)                       # both known, neither here
        self.assertEqual(step(s, ROWS, ["Koti 5G"], 60)[0], [("arrive", "home")])


class Leaving(unittest.TestCase):
    def test_blip_under_hold_is_not_leaving(self):
        s = at_work(0)
        self.assertEqual(step(s, ROWS, [], 100), ([], 100 + LEAVE_HOLD))
        self.assertEqual(step(s, ROWS, ["Feature"], 100 + LEAVE_HOLD - 10), ([], None))
        self.assertEqual(step(s, ROWS, ["Feature"], 100 + LEAVE_HOLD), ([], None))   # the timer, late: nothing

    def test_leaving_after_hold_by_the_timer(self):
        s = at_work(0)
        step(s, ROWS, [], 100)
        self.assertEqual(step(s, ROWS, [], 100 + LEAVE_HOLD - 1), ([], 100 + LEAVE_HOLD))
        self.assertEqual(step(s, ROWS, [], 100 + LEAVE_HOLD), ([("leave", "work")], None))
        self.assertEqual(step(s, ROWS, [], 100 + LEAVE_HOLD + 60), ([], None))   # once
        self.assertEqual(here(s), [])

    def test_waking_at_home_leaves_work(self):
        s = at_work(FRI_5PM)
        step(s, ROWS, ["Feature"], FRI_5PM, "sleep")
        events, due = step(s, ROWS, ["Koti"], MON_8AM - 2 * H, "wake")
        self.assertEqual(events, [("arrive", "home")])
        self.assertEqual(due, MON_8AM - 2 * H + LEAVE_HOLD)   # work: the network has its time to come up first
        self.assertEqual(step(s, ROWS, ["Koti"], due)[0], [("leave", "work")])

    def test_timer_at_waking_before_the_wake_signal(self):
        # The Wi-Fi went just before the sleep (NM takes it down), and the leave timer fires as the computer wakes,
        # before net-watch tells the wake: the state is still asleep, so it counts as the wake, not as a leaving
        s = at_work(FRI_5PM)
        step(s, ROWS, [], FRI_5PM)
        step(s, ROWS, [], FRI_5PM + 5, "sleep")
        self.assertEqual(step(s, ROWS, [], MON_8AM), ([], MON_8AM + LEAVE_HOLD))
        self.assertEqual(step(s, ROWS, [], MON_8AM + 1, "wake"), ([], MON_8AM + 1 + LEAVE_HOLD))
        self.assertEqual(step(s, ROWS, ["Feature"], MON_8AM + 30)[0], [("arrive", "work")])

    def test_login_after_a_shutdown_elsewhere(self):
        s = at_work(FRI_5PM)                       # shut down at work: no sleep check
        events, due = step(s, ROWS, ["Koti"], MON_8AM, "wake")
        self.assertEqual(events, [("arrive", "home")])
        self.assertEqual(step(s, ROWS, ["Koti"], due)[0], [("leave", "work")])


class Places(unittest.TestCase):
    def test_two_places_one_after_the_other(self):
        s = {}
        step(s, ROWS, ["Koti"], 0)
        self.assertEqual(step(s, ROWS, [], 7 * H), ([], 7 * H + LEAVE_HOLD))
        self.assertEqual(step(s, ROWS, ["Feature"], 7 * H + 60), ([("arrive", "work")], 7 * H + LEAVE_HOLD))
        self.assertEqual(step(s, ROWS, ["Feature"], 7 * H + LEAVE_HOLD), ([("leave", "home")], None))
        self.assertEqual(here(s), ["work"])

    def test_one_ssid_in_two_places(self):
        rows = [{"name": "work", "wifi": ["eduroam", "Feature"]}, {"name": "campus", "wifi": ["eduroam"]}]
        s = {}
        step(s, rows, [], 0)
        self.assertEqual(step(s, rows, ["eduroam"], 60)[0], [("arrive", "work"), ("arrive", "campus")])

    def test_removed_place_leaves_the_state_quietly(self):
        s = at_work(0)
        step(s, ROWS, [], 100)
        self.assertEqual(step(s, [HOME], [], 100 + LEAVE_HOLD), ([], None))
        self.assertEqual(sorted(s["places"]), ["home"])

    def test_roaming_between_a_places_networks(self):
        s = {}
        step(s, ROWS, ["Koti"], 0)
        self.assertEqual(step(s, ROWS, ["Koti 5G"], 60), ([], None))

    def test_broken_state_is_a_fresh_one(self):
        s = {"places": "nonsense", "asleep": False}
        self.assertEqual(step(s, ROWS, ["Feature"], 0), ([], None))
        self.assertEqual(here(s), ["work"])


if __name__ == "__main__":
    unittest.main()
