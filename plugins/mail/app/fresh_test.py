#!/usr/bin/env python3
"""When the open thread is read again after the list (fresh.js, #3612), and which new messages are
marked read (#3615): `python3 plugins/mail/app/fresh_test.py`.
A reply sent or a message a sync brought changes the thread's row (total, timestamp), and then its messages are read
again; a tag alone (read, replied) doesn't, nor does another thread in the open one's place.

fresh.js is QML's JavaScript, so it runs in Quickshell (offscreen) and its answers are read back here."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent

RUNNER = """
import QtQuick
import Quickshell
import "%s" as Fresh
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const c = %s, out = {}
            for (const k in c) out[k] = Fresh.changed(c[k][0], c[k][1])
            const a = %s
            for (const k in a) out["arrived_" + k] = Fresh.arrived(a[k][0], a[k][1])
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

ROW = {"thread": "0000000000001a2b", "timestamp": 1764060000, "total": 2, "matched": 1, "tags": ["inbox", "unread"]}


def row(**change):
    return dict(ROW, **change)


CASES = {
    "reply_sent": [ROW, row(total=3, timestamp=1764063600, tags=["inbox", "replied", "sent"])],
    # A message the sync brought into the thread from someone else
    "sync_brought": [ROW, row(total=3, timestamp=1764063600)],
    # A message deleted (or a draft dropped) in it: fewer on show
    "one_less": [ROW, row(total=1)],
    "read_only": [ROW, row(tags=["inbox"])],
    "same": [ROW, row()],
    "other_thread": [ROW, row(thread="00000000000000ff", total=5)],
    "none_before": [None, ROW],
    "none_after": [ROW, None],
}

# Messages on show before and after a refresh (#3615): which new ones are marked read
OLD = [{"id": "a@x", "tags": ["inbox"]}, {"id": "b@x", "tags": ["inbox", "unread"]}]
ARRIVED = {
    "new_unread": [OLD, OLD + [{"id": "c@x", "tags": ["inbox", "unread"]}]],
    "new_read": [OLD, OLD + [{"id": "c@x", "tags": ["inbox", "sent"]}]],
    # b was marked unread by the user and stays so
    "nothing_new": [OLD, OLD],
    "none_before": [None, OLD],
    "none_after": [OLD, None],
}


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Fresh(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "fresh.js").as_uri(), json.dumps(CASES), json.dumps(ARRIVED)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("fresh.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def test_a_reply_sent_shows(self):
        self.assertTrue(self.out["reply_sent"])

    def test_a_message_the_sync_brought_shows(self):
        self.assertTrue(self.out["sync_brought"])

    def test_a_message_gone_goes(self):
        self.assertTrue(self.out["one_less"])

    def test_tags_alone_read_nothing_again(self):
        self.assertFalse(self.out["read_only"])
        self.assertFalse(self.out["same"])

    def test_another_thread_is_opened_not_refreshed(self):
        self.assertFalse(self.out["other_thread"])

    def test_no_thread_open(self):
        self.assertFalse(self.out["none_before"])
        self.assertFalse(self.out["none_after"])

    def test_a_new_unread_message_is_marked_read(self):
        self.assertEqual(self.out["arrived_new_unread"], ["c@x"])

    def test_one_marked_unread_by_hand_stays_unread(self):
        self.assertEqual(self.out["arrived_new_read"], [])
        self.assertEqual(self.out["arrived_nothing_new"], [])

    def test_no_messages_before_or_after(self):
        self.assertEqual(self.out["arrived_none_before"], ["b@x"])
        self.assertEqual(self.out["arrived_none_after"], [])


if __name__ == "__main__":
    unittest.main()
