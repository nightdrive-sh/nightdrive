#!/usr/bin/env python3
"""The displays' arrangement (#1800): `python3 config/hypr/scripts/arrange_layout_test.py`. A dropped screen lands
beside another, never on it, level with it when close; one cut off by a move comes back; the arrow keys swap two."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from arrange_layout import connected, move, overlaps, place_side, settle, step, touches  # noqa: E402


def scr(sid, x, y, w, h):
    return {"id": sid, "x": x, "y": y, "w": w, "h": h}


def at(screens):
    return {s["id"]: (s["x"], s["y"]) for s in screens}


# Two 4K displays at 1.5 side by side, and a MacBook's panel at 2 under the first, centred (as `display side below`)
DESK = [scr("HDMI", 0, 0, 2560, 1440), scr("DP", 2560, 0, 2560, 1440), scr("eDP", 524, 1440, 1512, 982)]


class Drop(unittest.TestCase):
    def test_lands_beside_never_on(self):
        moved = move(DESK, "eDP", 3000, 300)            # dropped over DP: below it, nearest
        self.assertEqual(at(moved)["eDP"][1], 1440)
        self.assertEqual(len(connected(moved)), 1)

    def test_snaps_level_with_neighbour(self):
        out = at(move(DESK, "eDP", 5150, 40))           # off DP's right edge, nearly level with its top
        self.assertEqual(out["eDP"], (5120, 0))

    def test_centre_snap(self):
        out = at(move(DESK, "eDP", 2560 + 524 + 30, 1500))
        self.assertEqual(out["eDP"], (2560 + 524, 1440))

    def test_keeps_a_stretch_to_cross(self):
        out = move(DESK, "eDP", -1600, 1500)            # far off HDMI's bottom left corner
        e = next(s for s in out if s["id"] == "eDP")
        h = next(s for s in out if s["id"] == "HDMI")
        self.assertTrue(touches(e, h))

    def test_swap_by_drag_keeps_all_joined(self):
        out = move(DESK, "HDMI", 5200, 0)               # HDMI dropped past DP: the laptop under it is cut off, comes back
        self.assertEqual(len(connected(out)), 1)
        o = at(out)
        self.assertLess(o["DP"][0], o["HDMI"][0])

    def test_top_left_is_origin(self):
        out = at(move(DESK, "eDP", -1600, 0))
        self.assertEqual(min(x for x, _ in out.values()), 0)
        self.assertEqual(min(y for _, y in out.values()), 0)

    def test_alone(self):
        self.assertEqual(at(move([scr("A", 0, 0, 100, 100)], "A", 50, 50)), {"A": (0, 0)})


class Virtual(unittest.TestCase):
    # As a desk had it: a tablet, a phone and a Mac not connected, under and between the displays
    def desk(self):
        soft = lambda *a: dict(scr(*a), soft=True)   # noqa: E731
        return [scr("HDMI", 3000, 949, 2560, 1440), scr("DP", 440, 0, 2560, 1440), scr("eDP", 3524, 2389, 1512, 982),
                soft("IPAD", 5560, 1750, 1180, 820), soft("IPHONE", 2560, 1682, 440, 956),
                soft("MAC", 0, 1440, 2560, 1440)]

    def test_never_holds_a_display_out_of_line(self):
        o = at(place_side(self.desk(), "DP", "left", "HDMI"))
        self.assertEqual(o["DP"][1], o["HDMI"][1])
        self.assertEqual(o["DP"], (0, 0))
        self.assertEqual(o["HDMI"], (2560, 0))

    def test_gives_way_outwards(self):
        out = place_side(self.desk(), "DP", "left", "HDMI")
        for s in out:
            for t in out:
                if s is not t:
                    self.assertFalse(overlaps(s, t), (s["id"], t["id"]))
        self.assertEqual(len(connected(out)), 1)

    def test_moving_one_never_moves_a_display(self):
        desk = place_side(self.desk(), "DP", "left", "HDMI")
        before = {i: xy for i, xy in at(desk).items() if i in ("HDMI", "DP", "eDP")}
        for x, y in ((9000, 5000), (-4000, 3000), (2600, 300), (100, -900)):
            out = at(move(desk, "IPHONE", x, y))
            self.assertEqual({i: out[i] for i in before}, before, (x, y))

    def test_drop_ignores_it(self):
        o = at(move(self.desk(), "DP", 440, 949))
        self.assertEqual(o["DP"][1], o["HDMI"][1])


class Settle(unittest.TestCase):
    def test_grown_display_stays_on_its_side(self):
        # DP at 1.5 left of the main HDMI, then set to scale 1: 3840 wide, over HDMI's left part
        out = at(settle([scr("DP", 0, 0, 3840, 2160), scr("HDMI", 2560, 0, 2560, 1440)], "HDMI"))
        self.assertEqual(out, {"DP": (0, 0), "HDMI": (3840, 0)})

    def test_shrunk_display_closes_the_gap(self):
        out = at(settle([scr("HDMI", 0, 0, 1920, 1080), scr("DP", 2560, 0, 2560, 1440)], "HDMI"))
        self.assertEqual(out["DP"], (1920, 0))

    def test_unchanged_stays(self):
        self.assertEqual(at(settle(DESK, "HDMI")), at(DESK))


class Keys(unittest.TestCase):
    def test_right_swaps_same_size(self):
        two = DESK[:2]
        o = at(step(two, "HDMI", "right"))
        self.assertEqual(o, {"DP": (0, 0), "HDMI": (2560, 0)})

    def test_laptop_slides_along(self):
        o = at(step(DESK, "eDP", "right"))
        self.assertEqual(o["eDP"][1], 1440)
        self.assertGreater(o["eDP"][0], 524)

    def test_nowhere_to_go_stays(self):
        one = [scr("A", 0, 0, 100, 100)]
        self.assertEqual(at(step(one, "A", "left")), {"A": (0, 0)})


class Side(unittest.TestCase):
    def test_below_one(self):
        o = at(place_side(DESK, "eDP", "below", "DP"))
        self.assertEqual(o["eDP"], (2560 + 524, 1440))

    def test_beside_the_desk(self):
        ipad = scr("IPAD", 0, 0, 1180, 820)
        o = at(place_side(DESK + [ipad], "IPAD", "right"))
        self.assertEqual(o["IPAD"][0], 5120)
        self.assertEqual(len(connected(place_side(DESK + [ipad], "IPAD", "right"))), 1)


if __name__ == "__main__":
    unittest.main()
