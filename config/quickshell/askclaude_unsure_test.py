#!/usr/bin/env python3
"""Claude's unsure mark (AskClaudeUnsure.js, #3154): `python3 config/quickshell/askclaude_unsure_test.py`.
A dictated request's answer that begins with the mark is one Claude wasn't sure of: it is told by the mark first (after
any blank space), never by one further in, and shown without it. look() (#3155) says when a finished request opens
Ask Claude's toast large: a dictated one that Claude marked unsure or that ended in an error, never a typed one.

The .js is QML's JavaScript, so it runs in Quickshell (offscreen), as askclaude_markdown_test.py does."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
JS = HERE / "AskClaudeUnsure.js"
MARK = re.search(r'^var MARK = "(.*)"$', JS.read_text(), re.M).group(1)

RUNNER = """
import QtQuick
import Quickshell
import "%s" as Unsure
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const out = { mark: Unsure.MARK, unsure: {}, strip: {}, look: {} }
            for (const [name, text] of Object.entries(%s)) {
                out.unsure[name] = Unsure.unsure(text)
                out.strip[name] = Unsure.strip(text)
            }
            for (const [name, c] of Object.entries(%s))
                out.look[name] = Unsure.look(c.entries, c.dictated, c.unsure)
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

CASES = {
    "marked": MARK + " Kuulin \"hyper land\": tarkoititko Hyprlandin asetuksia?",
    "marked_after_space": "\n  " + MARK + " Mikä lista?",
    "mark_alone": MARK,
    "plain": "Muistutus lisätty huomiseksi klo 9.",
    "mark_inside": "Lisäsin tehtävän " + MARK + " Ideat-listaan.",
    "empty": "",
}

YOU = {"kind": "you", "text": "lisää tehtävä hyper landin asetukset"}
DONE = {"kind": "text", "text": "Tehtävä lisätty."}
ERROR = {"kind": "error", "text": "Claude couldn't answer"}
STEP_FAILED = {"kind": "step", "id": "1", "state": "error", "text": "Adding a task"}
LOOK = {
    "dictated_done": {"entries": [YOU, DONE], "dictated": True, "unsure": False},
    "dictated_unsure": {"entries": [YOU, DONE], "dictated": True, "unsure": True},
    "dictated_error": {"entries": [YOU, ERROR], "dictated": True, "unsure": False},
    "dictated_step_failed_then_done": {"entries": [YOU, STEP_FAILED, DONE], "dictated": True, "unsure": False},
    "error_in_an_earlier_request": {"entries": [YOU, ERROR, YOU, DONE], "dictated": True, "unsure": False},
    "typed_error": {"entries": [YOU, ERROR], "dictated": False, "unsure": False},
    "typed_unsure": {"entries": [YOU, DONE], "dictated": False, "unsure": True},
    "error_before_any_request": {"entries": [ERROR], "dictated": True, "unsure": False},
    "nothing": {"entries": [], "dictated": True, "unsure": False},
}


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class AskClaudeUnsure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % (JS.as_uri(), json.dumps(CASES), json.dumps(LOOK)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("AskClaudeUnsure.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def test_the_mark_is_the_one_ask_claude_reads(self):
        self.assertEqual(self.out["mark"], MARK)
        self.assertTrue(MARK.isascii() and MARK.strip() == MARK != "")

    def test_an_answer_that_begins_with_it_is_unsure(self):
        for name in ("marked", "marked_after_space", "mark_alone"):
            self.assertTrue(self.out["unsure"][name], name)

    def test_one_further_in_or_none_is_not(self):
        for name in ("plain", "mark_inside", "empty"):
            self.assertFalse(self.out["unsure"][name], name)

    def test_it_is_shown_without_the_mark(self):
        self.assertEqual(self.out["strip"]["marked"], "Kuulin \"hyper land\": tarkoititko Hyprlandin asetuksia?")
        self.assertEqual(self.out["strip"]["marked_after_space"], "Mikä lista?")
        self.assertEqual(self.out["strip"]["mark_alone"], "")
        self.assertEqual(self.out["strip"]["mark_inside"], CASES["mark_inside"])

    def test_a_dictation_claude_was_unsure_of_or_that_failed_needs_a_look(self):
        self.assertEqual(self.out["look"]["dictated_unsure"], "unsure")
        self.assertEqual(self.out["look"]["dictated_error"], "error")
        self.assertEqual(self.out["look"]["error_before_any_request"], "error")

    def test_one_that_went_well_keeps_the_small_card(self):
        for name in ("dictated_done", "dictated_step_failed_then_done", "error_in_an_earlier_request", "nothing"):
            self.assertEqual(self.out["look"][name], "", name)

    def test_a_typed_request_never_opens_it(self):
        for name in ("typed_error", "typed_unsure"):
            self.assertEqual(self.out["look"][name], "", name)


if __name__ == "__main__":
    unittest.main()
