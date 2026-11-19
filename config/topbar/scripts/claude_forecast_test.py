#!/usr/bin/env python3
"""claude-forecast's estimate (#3256): `python3 config/topbar/scripts/claude_forecast_test.py`. When the weekly quota
runs out at this pace, from made-up histories: nothing with too little data, a straight line without earlier weeks, the
earlier weeks' shape steadying the start of a week, nothing when it lasts, and the history kept small. Everything runs in
a throwaway folder."""

import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("claude_forecast", os.path.join(HERE, "claude-forecast"))
fc = importlib.util.module_from_spec(importlib.util.spec_from_loader("claude_forecast", loader))
loader.exec_module(fc)

H = 3600
D = 86400
RESET = 1_800_000_000 // H * H   # this week's reset, on the hour
START = RESET - fc.WEEK


def week(reset, final, until=None, pace=None):
    """Hourly samples of a past or current week ending at reset; pace(h) is the share of final used by hour h
    (evenly by default), until stops it early (the current week)."""
    pace = pace or (lambda h: h / 168)
    start = reset - fc.WEEK
    end = until if until is not None else reset
    return [(start + h * H, round(final * pace(h), 1), reset) for h in range(169) if start + h * H <= end]


def daytime(h):
    """Use only 08–20 on weekdays (the week starts on a Monday 00:00), as people use it."""
    worked = 0
    for x in range(int(h)):
        day, hour = divmod(x, 24)
        if day < 5 and 8 <= hour < 20:
            worked += 1
    return worked / 60


class TooLittle(unittest.TestCase):
    def test_nothing_without_history(self):
        self.assertIsNone(fc.forecast([], START + 3 * D, 50, RESET))

    def test_nothing_until_this_week_spans_long_enough(self):
        now = START + 3 * D
        s = [(now - 2 * H, 40, RESET), (now, 50, RESET)]
        self.assertIsNone(fc.forecast(s, now, 50, RESET))

    def test_no_straight_line_early_in_the_week(self):
        # A heavy first day alone would say "runs out in a few days": too early to say without earlier weeks
        now = START + 1 * D
        s = week(RESET, 300, until=now)
        self.assertIsNone(fc.forecast(s, now, 43, RESET))

    def test_nothing_once_used_up_or_past_reset(self):
        s = week(RESET, 150, until=START + 5 * D)
        self.assertIsNone(fc.forecast(s, START + 5 * D, 100, RESET))
        self.assertIsNone(fc.forecast(s, RESET + H, 80, RESET))


class StraightLine(unittest.TestCase):
    def test_even_use_runs_out_on_time(self):
        # 60 % in three days runs out at five days
        now = START + 3 * D
        s = week(RESET, 140, until=now)
        end = fc.forecast(s, now, 60, RESET)
        self.assertAlmostEqual(end, START + 5 * D, delta=60)

    def test_lasts_until_reset(self):
        now = START + 3 * D
        s = week(RESET, 70, until=now)
        self.assertIsNone(fc.forecast(s, now, 30, RESET))


class Profile(unittest.TestCase):
    def history(self, final, pace=None, weeks=3):
        s = []
        for k in range(weeks, 0, -1):
            s += week(RESET - k * fc.WEEK, final, pace=pace)
        return s

    def test_lasts_like_earlier_weeks(self):
        s = self.history(70)
        now = START + 2 * D
        s += week(RESET, 70, until=now)
        self.assertIsNone(fc.forecast(s, now, 20, RESET))

    def test_heavier_than_usual_runs_out(self):
        # Usual weeks reach 90 %, this one is going at twice that: about half way through the week
        s = self.history(90)
        now = START + 2 * D
        s += week(RESET, 180, until=now)
        end = fc.forecast(s, now, round(180 * 48 / 168, 1), RESET)
        self.assertIsNotNone(end)
        self.assertGreater(end, now)
        self.assertLess(end, START + 5 * D)

    def test_quiet_night_and_weekend_do_not_swing_it(self):
        # Daytime-only weeks of 95 %: Monday evening's 19 % is just a usual Monday, not a pace of 19 % in 20 hours
        s = self.history(95, pace=daytime)
        now = START + 20 * H
        s += week(RESET, 95, until=now, pace=daytime)
        pct = round(95 * daytime(20), 1)
        self.assertIsNone(fc.forecast(s, now, pct, RESET))
        # ...where the straight line alone, without the earlier weeks, would run out on Thursday
        linear = now + (100 - pct) * (now - START) / pct
        self.assertLess(linear, RESET)

    def test_profile_runs_out_in_working_hours(self):
        # Daytime weeks of 150 %: it runs out on a weekday between 08 and 20, not at night
        s = self.history(150, pace=daytime)
        now = START + 1 * D + 10 * H
        s += week(RESET, 150, until=now, pace=daytime)
        end = fc.forecast(s, now, round(150 * daytime(34), 1), RESET)
        self.assertIsNotNone(end)
        day, hour = divmod((end - START) / H, 24)
        self.assertLess(day, 5)
        self.assertTrue(8 <= hour <= 20, hour)

    def test_partial_week_is_left_out(self):
        # History that began mid-week has no shape to give
        s = [x for x in week(RESET - fc.WEEK, 200) if x[0] >= RESET - fc.WEEK - 3 * D]
        self.assertIsNone(fc.profile(s, START + D))


class History(unittest.TestCase):
    def test_samples_on_change_or_hourly(self):
        s = fc.record([], START, 10, RESET + 0.4)
        s = fc.record(s, START + 120, 10, RESET)
        self.assertEqual(len(s), 1)
        s = fc.record(s, START + 240, 11, RESET)
        s = fc.record(s, START + 240 + H, 11, RESET)
        self.assertEqual(len(s), 3)
        self.assertEqual({r for _, _, r in s}, {RESET})

    def test_old_samples_dropped(self):
        old = [(START - 40 * D, 50.0, RESET - 6 * fc.WEEK)]
        s = fc.record(old, START, 1, RESET)
        self.assertEqual(len(s), 1)
        self.assertEqual(s[0][2], RESET)

    def test_annotate_writes_history_and_run_out(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "work.jsonl")
            now = START + 3 * D
            fc.save(path, week(RESET, 140, until=now - 120))
            iso = fc.datetime.fromtimestamp(RESET, fc.timezone.utc).isoformat()
            usage = {"account": "work", "windows": [{"key": "session", "percent": 5, "resetsAt": iso},
                                                    {"key": "weekly", "percent": 60, "resetsAt": iso}]}
            out = fc.annotate(json.loads(json.dumps(usage)), now, tmp)
            self.assertIn("runsOut", out["windows"][1])
            self.assertNotIn("runsOut", out["windows"][0])
            with open(path) as f:
                self.assertEqual(json.loads(f.readlines()[-1])["p"], 60)

    def test_annotate_leaves_errors_alone(self):
        with tempfile.TemporaryDirectory() as tmp:
            usage = {"account": "work", "error": "Usage request failed", "windows": []}
            self.assertEqual(fc.annotate(dict(usage), START, tmp), usage)
            self.assertEqual(os.listdir(tmp), [])


if __name__ == "__main__":
    unittest.main()
