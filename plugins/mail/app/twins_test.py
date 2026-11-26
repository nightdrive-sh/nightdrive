#!/usr/bin/env python3
"""A draft with a twin says so (twins.js, #3625): `python3 plugins/mail/app/twins_test.py`. A thread had two drafts
answering one message; the user sent one, then the one left behind, and the sender got two versions.

twins.js is QML's JavaScript, so it runs in Quickshell (offscreen) and its answers are read back here."""

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
import "%s" as Twins
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const c = %s, out = {}
            for (const k in c.cases) {
                const q = c.cases[k], t = Twins.twins(c.thread, q.parent, q.self)
                out[k] = { drafts: t.drafts.map(m => m.id), sent: t.sent ? t.sent.id : null,
                           warning: Twins.warning(t, ts => "at " + ts) }
            }
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""


def msg(id, ts, parent="", draft=False, sent=False):
    return {"id": id, "timestamp": ts, "parent": parent, "draft": draft, "sent": sent}


# The thread of #3624 and #3625: Pinja asks; Claude's drafts at 10:08 and 10:57 answer her; one goes at 10:59.
THREAD = [
    msg("pinja", 100),
    msg("draft-1008", 200, "pinja", draft=True),
    msg("draft-1057", 300, "pinja", draft=True),
    msg("sent-1059", 400, "pinja", sent=True),
    msg("pinja-2", 500, "sent-1059"),
    msg("draft-other", 600, "pinja-2", draft=True),
]
CASES = {
    "left_behind": {"parent": "pinja", "self": "draft-1008"},     # the draft opened after one was sent
    "new_reply": {"parent": "pinja", "self": ""},                 # r on Pinja's message again
    "alone": {"parent": "pinja-2", "self": "draft-other"},
    "not_a_reply": {"parent": "", "self": "x"},
}


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Twins(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "twins.js").as_uri(), json.dumps({"thread": THREAD, "cases": CASES})))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("twins.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def test_a_draft_left_after_its_reply_was_sent(self):
        o = self.out["left_behind"]
        self.assertEqual((o["drafts"], o["sent"]), (["draft-1057"], "sent-1059"))
        self.assertIn("already answered", o["warning"])
        self.assertIn("at 400", o["warning"])

    def test_a_new_reply_to_a_message_with_drafts(self):
        o = self.out["new_reply"]
        self.assertEqual(o["drafts"], ["draft-1008", "draft-1057"])
        self.assertIn("already answered", o["warning"])

    def test_a_draft_alone(self):
        self.assertEqual(self.out["alone"], {"drafts": [], "sent": None, "warning": ""})

    def test_not_a_reply(self):
        self.assertEqual(self.out["not_a_reply"]["warning"], "")


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class DraftsOnly(unittest.TestCase):
    """Two drafts and nothing sent: the count, not a reply's time."""

    def test_count(self):
        thread = [msg("p", 1), msg("d1", 2, "p", draft=True), msg("d2", 3, "p", draft=True), msg("d3", 4, "p", draft=True)]
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "twins.js").as_uri(), json.dumps(
                {"thread": thread, "cases": {"one": {"parent": "p", "self": "d1"}, "none": {"parent": "p", "self": ""}}})))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        out = json.loads(re.search(r"RESULT (\{.*\})", run.stdout + run.stderr).group(1))
        self.assertEqual(out["one"]["warning"], "2 other drafts answer the same message: send only one")
        self.assertEqual(out["none"]["warning"], "3 other drafts answer the same message: send only one")


if __name__ == "__main__":
    unittest.main()
