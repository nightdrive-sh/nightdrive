#!/usr/bin/env python3
"""Claude's unsure mark (AskClaudeUnsure.js, #3154): `python3 config/quickshell/askclaude_unsure_test.py`.
A dictated request's answer that begins with the mark is one Claude wasn't sure of: it is told by the mark first (after
any blank space), never by one further in, and shown without it.

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
            const out = { mark: Unsure.MARK, unsure: {}, strip: {} }
            for (const [name, text] of Object.entries(%s)) {
                out.unsure[name] = Unsure.unsure(text)
                out.strip[name] = Unsure.strip(text)
            }
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


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class AskClaudeUnsure(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % (JS.as_uri(), json.dumps(CASES)))
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


if __name__ == "__main__":
    unittest.main()
