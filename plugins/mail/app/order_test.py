#!/usr/bin/env python3
"""A thread's messages by date (order.js, #3622): `python3 plugins/mail/app/order_test.py`.
notmuch's reply tree put a late reply to an early message in the middle; Mail shows them oldest first, the newest last
and open, without a draft deleted to Trash. lib/browse.py's by_date (nightmail thread, Claude's mail_thread) does the
same and is checked against the same thread.

order.js is QML's JavaScript, so it runs in Quickshell (offscreen) and its answers are read back here."""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lib"))
import browse  # noqa: E402

RUNNER = """
import QtQuick
import Quickshell
import "%s" as Order
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const c = %s, out = {}
            const mark = list => list.map(m => Object.assign({}, m, { gone: Order.deletedDraft(m.tags, m.filename) }))
            for (const k in c.threads) {
                const o = Order.order(mark(c.threads[k]))
                out[k] = { ids: o.map(m => m.id), gone: o.some(m => "gone" in m), newest: Order.newest(o) }
            }
            out.single = Order.deletedDraft(["draft"], "/m/a/Trash/new/1")
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""


def msg(id, ts, tags=(), files=("/m/a/INBOX/cur/x",), draft=False):
    return {"id": id, "timestamp": ts, "tags": list(tags), "filename": list(files), "draft": draft}


# The case in #3622 in notmuch's tree order: Pinja's reply (13:22) to Jari's 10:59 came before Jari's 11:13, and a
# draft deleted at 10:11 sat among them.
TREE = [
    msg("pinja-fri", 100),
    msg("jari-fri", 200, ["sent"]),
    msg("draft-deleted", 300, ["draft"], ["/m/a/Trash/cur/d"]),
    msg("jari-1059", 400, ["sent"]),
    msg("pinja-1322", 600, ["inbox"]),
    msg("jari-1113", 500, ["sent"]),
]
THREADS = {
    "tree": TREE,
    # A draft still being written (in Drafts) stays, after the newest real message
    "open_draft": [msg("a", 100), msg("d", 300, ["draft"], ["/m/a/Drafts/cur/d"], draft=True), msg("b", 200)],
    # A draft with a copy outside Trash isn't deleted
    "draft_copy": [msg("a", 100), msg("d", 200, ["draft"], ["/m/a/Trash/cur/d", "/m/a/Archive/cur/d"])],
    # Opened in Trash, a deleted draft alone still shows itself
    "only_deleted": [msg("d", 100, ["draft"], ["/m/a/Trash/cur/d"])],
    # A message and its reply in the same second keep the tree's order
    "same_second": [msg("q", 100), msg("r", 100), msg("p", 50)],
    "empty": [],
}
WANT = {
    "tree": ["pinja-fri", "jari-fri", "jari-1059", "jari-1113", "pinja-1322"],
    "open_draft": ["a", "b", "d"],
    "draft_copy": ["a", "d"],
    "only_deleted": ["d"],
    "same_second": ["p", "q", "r"],
    "empty": [],
}


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Order(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "order.js").as_uri(), json.dumps({"threads": THREADS})))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("order.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def test_by_date_oldest_first(self):
        for k, want in WANT.items():
            self.assertEqual(self.out[k]["ids"], want, k)

    def test_the_mark_is_taken_off(self):
        self.assertFalse(any(v["gone"] for k, v in self.out.items() if k in WANT))

    def test_newest_is_the_last_that_isnt_a_draft(self):
        self.assertEqual(self.out["tree"]["newest"], 4)
        self.assertEqual(self.out["open_draft"]["newest"], 1)
        self.assertEqual(self.out["empty"]["newest"], -1)

    def test_one_filename_as_a_string(self):
        self.assertTrue(self.out["single"])


class Browse(unittest.TestCase):
    """nightmail thread gives Claude the same order."""

    def test_same_order_as_the_window(self):
        for k, want in WANT.items():
            self.assertEqual([m["id"] for m in browse.by_date(THREADS[k])], want, k)


if __name__ == "__main__":
    unittest.main()
