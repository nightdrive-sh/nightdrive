#!/usr/bin/env python3
"""How Mail tidies a plain-text message's blank lines (#3318): `python3 plugins/mail/app/blanks_test.py`.
Runs of blank lines (empty, NBSP, a newsletter's invisible preheader filler) become one, none at the start or end,
and nothing else changes. app/blanks.js (the read view, run in Quickshell offscreen) and lib/blanks.py (the reply's
quote) get the same cases and must agree."""

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

import blanks  # noqa: E402

RUNNER = """
import QtQuick
import Quickshell
import "%s" as Blanks
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const out = {}
            for (const [name, text] of Object.entries(%s)) out[name] = Blanks.tidy(text)
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

# A newsletter's preheader: what pads the inbox's preview line, drawn as nothing (made up, in the shape of a real one)
FILLER = "͏ \xa0 \xad" * 25
CASES = {
    # (text, what it tidies to)
    "newsletter": ("Also: sections, and more\n\n" + (FILLER + "\n") * 7 + "\nhttps://example.com/home/\n\n\xa0\n\n\n\n"
                   "\xa0\nHey you,\n\xa0\nOur update is out.\n\xa0\n\n\n\n\nIntroducing: Variants\n\nText.\n",
                   "Also: sections, and more\n\nhttps://example.com/home/\n\nHey you,\n\nOur update is out.\n\n"
                   "Introducing: Variants\n\nText."),
    "edges": ("\n \n​\nHello\n\n﻿\n", "Hello"),
    "one_blank_kept": ("a\n\nb\nc", "a\n\nb\nc"),
    "crlf": ("a\r\n\r\n\r\nb\r\n", "a\n\nb"),
    "signature": ("Thanks\n\n\n\n-- \nName", "Thanks\n\n-- \nName"),
    "quote": ("Yes.\n\n> one\n>\n>\n> two\n\n\n", "Yes.\n\n> one\n>\n>\n> two"),
    "indent_kept": ("    code\n      more  \n\n\n  x", "    code\n      more  \n\n  x"),
    "invisible_inside_kept": ("soft\xadhyphen and​zero", "soft\xadhyphen and​zero"),
    "all_blank": ("\n\xa0\n \n", ""),
    "empty": ("", ""),
}


class Python(unittest.TestCase):
    def test_cases(self):
        for name, (text, want) in CASES.items():
            with self.subTest(name):
                self.assertEqual(blanks.tidy(text), want)


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Qml(unittest.TestCase):
    def test_cases(self):
        texts = {name: text for name, (text, _) in CASES.items()}
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "blanks.js").as_uri(), json.dumps(texts)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("blanks.js didn't run:\n" + log)
        out = json.loads(found.group(1))
        for name, (_, want) in CASES.items():
            with self.subTest(name):
                self.assertEqual(out[name], want)


if __name__ == "__main__":
    unittest.main()
