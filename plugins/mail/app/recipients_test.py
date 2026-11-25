#!/usr/bin/env python3
"""Where the address being typed in To or Cc starts (recipients.js, #3593): `python3 plugins/mail/app/recipients_test.py`.
A comma inside a quoted name ("Virtanen, Aino") or inside <…> doesn't end an address, so the completions search for
what is being typed and a completion keeps the names before it whole.

recipients.js is QML's JavaScript, so it runs in Quickshell (offscreen) and its results are read back here."""

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
import "%s" as R
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const out = {}
            for (const [name, text] of Object.entries(%s)) out[name] = [R.before(text), R.typed(text)]
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

# Made-up names and addresses
AINO = '"Virtanen, Aino" <aino@example.com>'
CASES = {
    "empty": "",
    "first": "liis",
    "after_plain": "bob@example.com, liis",
    "after_quoted_comma": AINO + ", liis",
    "after_two": AINO + ', "Mäkinen, Liisa" <liisa@example.com>, vil',
    "inside_quotes": '"Virtanen, Ai',
    "escaped_quote": '"Odd \\"Q, x\\" Name" <odd@example.org>, pek',
    "comma_in_angle": "Odd <a,b@example.org>, pek",
    "just_comma": AINO + ", ",
    "encoded": "=?utf-8?q?Nieminen=2C_Ville?= <ville@example.net>, kor",
}


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Typed(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "recipients.js").as_uri(), json.dumps(CASES)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("recipients.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def check(self, case, before, typed):
        self.assertEqual(self.out[case], [before, typed], case)

    def test_first_address(self):
        self.check("empty", "", "")
        self.check("first", "", "liis")

    def test_after_a_plain_address(self):
        self.check("after_plain", "bob@example.com,", "liis")

    def test_comma_in_a_quoted_name_isnt_a_separator(self):
        """The task's case: typing after "Lastname, Firstname" <addr> searched for Firstname" <addr>…"""
        self.check("after_quoted_comma", AINO + ",", "liis")
        self.check("after_two", AINO + ', "Mäkinen, Liisa" <liisa@example.com>,', "vil")

    def test_typing_a_quoted_name(self):
        """…and a completion then replaced only its second half."""
        self.check("inside_quotes", "", "virtanen, ai")

    def test_escaped_quote_and_angle_brackets(self):
        self.check("escaped_quote", '"Odd \\"Q, x\\" Name" <odd@example.org>,', "pek")
        self.check("comma_in_angle", "Odd <a,b@example.org>,", "pek")

    def test_encoded_word_has_no_bare_comma(self):
        self.check("encoded", "=?utf-8?q?Nieminen=2C_Ville?= <ville@example.net>,", "kor")

    def test_nothing_typed_yet(self):
        self.check("just_comma", AINO + ",", "")


if __name__ == "__main__":
    unittest.main()
