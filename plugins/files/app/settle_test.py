#!/usr/bin/env python3
"""Which row Files picks once its rows change (Settle.js, #3415): `python3 plugins/files/app/settle_test.py`.
After a delete, a move away or another app's change the pick stays where the user was: the same file if it is still
there, else the next row still there in the place of those gone, else (they were at the end) the last one before
them; a file a change made (keep) wins. It used to go back to the top.

The .js is QML's JavaScript, so it runs in Quickshell (offscreen), as the Ask Claude tests do."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

JS = Path(__file__).resolve().parent / "Settle.js"

RUNNER = """
import QtQuick
import Quickshell
import "%s" as Settle
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const out = { place: {}, scroll: {} }
            for (const [name, c] of Object.entries(%s))
                out.place[name] = Settle.place(c.before, c.index, c.after, c.keep || "")
            for (const [name, c] of Object.entries(%s))
                out.scroll[name] = Settle.scrollBack(c[0], c[1], c[2])
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

ROWS = [f"/d/f{i}" for i in range(10)]          # f0 … f9


def without(*gone):
    return [p for p in ROWS if p.rsplit("f", 1)[1] not in {str(g) for g in gone}]


PLACE = {
    # The picked one deleted: the next row takes its place
    "picked_deleted": {"before": ROWS, "index": 4, "after": without(4)},
    # Marked 3–5 and picked on 5 (⇧↓ leaves the pick on the last marked): the row after them, f6
    "marked_run_deleted": {"before": ROWS, "index": 5, "after": without(3, 4, 5)},
    # Marked 3–5 and picked on 3: the same
    "marked_run_picked_first": {"before": ROWS, "index": 3, "after": without(3, 4, 5)},
    # The last rows deleted: the last one left
    "end_deleted": {"before": ROWS, "index": 9, "after": without(8, 9)},
    # Everything deleted: nothing to pick
    "all_deleted": {"before": ROWS, "index": 2, "after": []},
    # Marked rows elsewhere deleted, the pick not among them: it stays on its file
    "others_deleted": {"before": ROWS, "index": 7, "after": without(1, 2)},
    # Another app added files above the pick: the same file, further down
    "added_above": {"before": ROWS, "index": 4, "after": ["/d/a", "/d/b"] + ROWS},
    # A rename: the new name is picked (keep), wherever the order puts it
    "renamed": {"before": ROWS, "index": 2, "after": without(2) + ["/d/zz"], "keep": "/d/zz"},
    # keep not there yet (the folder not read again yet): the pick stays where it is
    "keep_not_yet": {"before": ROWS, "index": 2, "after": ROWS, "keep": "/d/new"},
    # A folder entered: nothing before, the first row (or the one asked for)
    "fresh": {"before": [], "index": -1, "after": ROWS},
    "fresh_keep": {"before": [], "index": -1, "after": ROWS, "keep": "/d/f6"},
    "fresh_empty": {"before": [], "index": -1, "after": []},
}

# y, top, room: the view's place kept within what the list has room for
SCROLL = {"kept": [300, -4, 2000], "past_the_end": [3000, -4, 2000], "above_the_top": [-50, -4, 2000],
          "shorter_than_the_view": [300, -4, -100]}


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Settle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % (JS.as_uri(), json.dumps(PLACE), json.dumps(SCROLL)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("Settle.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def picked(self, name):
        i = self.out["place"][name]
        return PLACE[name]["after"][i] if i >= 0 else None

    def test_after_a_delete_the_next_row_takes_its_place(self):
        self.assertEqual(self.picked("picked_deleted"), "/d/f5")
        self.assertEqual(self.picked("marked_run_deleted"), "/d/f6")
        self.assertEqual(self.picked("marked_run_picked_first"), "/d/f6")

    def test_deleted_from_the_end_the_last_row_is_picked(self):
        self.assertEqual(self.picked("end_deleted"), "/d/f7")

    def test_nothing_left_picks_nothing(self):
        self.assertEqual(self.out["place"]["all_deleted"], -1)
        self.assertEqual(self.out["place"]["fresh_empty"], -1)

    def test_the_picked_file_stays_picked_when_others_change(self):
        self.assertEqual(self.picked("others_deleted"), "/d/f7")
        self.assertEqual(self.picked("added_above"), "/d/f4")

    def test_a_file_a_change_made_is_picked(self):
        self.assertEqual(self.picked("renamed"), "/d/zz")
        self.assertEqual(self.picked("fresh_keep"), "/d/f6")

    def test_until_it_comes_the_pick_stays(self):
        self.assertEqual(self.picked("keep_not_yet"), "/d/f2")

    def test_a_folder_entered_starts_at_the_top(self):
        self.assertEqual(self.out["place"]["fresh"], 0)

    def test_the_view_stays_where_it_was_within_the_list(self):
        self.assertEqual(self.out["scroll"]["kept"], 300)
        self.assertEqual(self.out["scroll"]["past_the_end"], 1996)
        self.assertEqual(self.out["scroll"]["above_the_top"], -4)
        self.assertEqual(self.out["scroll"]["shorter_than_the_view"], -4)


if __name__ == "__main__":
    unittest.main()
