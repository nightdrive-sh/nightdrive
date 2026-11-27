#!/usr/bin/env python3
"""A message's To, Cc and Bcc split into people and said short (addresses.js, #3716):
`python3 plugins/mail/app/addresses_test.py`. A comma in a quoted name or inside <…> doesn't end an address, and a
"Lastname, Firstname" name reads first name first, so the short line's commas only separate people.

addresses.js is QML's JavaScript, so it runs in Quickshell (offscreen) and its results are read back here."""

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
import "%s" as A
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const out = { split: {}, summary: {} }
            for (const [name, list] of Object.entries(%s)) out.split[name] = A.split(list)
            for (const [name, names] of Object.entries(%s)) out.summary[name] = A.summary(names)
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

# Made-up names and addresses
SPLIT = {
    "empty": "",
    "one": "Aino Virtanen <aino@example.com>",
    "bare": "bob@example.com",
    "angle_only": "<bob@example.com>",
    "quoted_comma": '"Virtanen, Aino" <aino@example.com>, Bob <bob@example.com>',
    "escaped_quote": '"Odd \\"Q, x\\" Name" <odd@example.org>,  , pek@example.net',
    "comma_in_angle": "Odd <a,b@example.org>",
    "group": "undisclosed-recipients:;",
}
SUMMARY = {
    "none": [],
    "one": ["Anna"],
    "two": ["Anna", "Pekka"],
    "three": ["Anna", "Pekka", "Liisa"],
    "five": ["Anna", "Pekka", "Liisa", "Ville", "Aino"],
}


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Addresses(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            # sender.js beside it, as addresses.js imports it by its relative path
            for f in ("addresses.js", "sender.js"):
                shutil.copy(HERE / f, tmp)
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((Path(tmp) / "addresses.js").as_uri(), json.dumps(SPLIT), json.dumps(SUMMARY)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("addresses.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def people(self, case):
        return [(p["name"], p["address"]) for p in self.out["split"][case]]

    def test_nothing(self):
        self.assertEqual(self.people("empty"), [])

    def test_name_and_address(self):
        self.assertEqual(self.people("one"), [("Aino Virtanen", "aino@example.com")])

    def test_address_alone_is_its_own_name(self):
        self.assertEqual(self.people("bare"), [("bob@example.com", "bob@example.com")])
        self.assertEqual(self.people("angle_only"), [("bob@example.com", "bob@example.com")])

    def test_comma_in_a_quoted_name_isnt_a_separator_and_reads_first_name_first(self):
        self.assertEqual(self.people("quoted_comma"), [("Aino Virtanen", "aino@example.com"), ("Bob", "bob@example.com")])

    def test_escaped_quote_and_empty_parts(self):
        self.assertEqual(self.people("escaped_quote"),
                         [('Odd "Q, x" Name', "odd@example.org"), ("pek@example.net", "pek@example.net")])

    def test_comma_inside_angle_brackets(self):
        self.assertEqual(self.people("comma_in_angle"), [("Odd", "a,b@example.org")])

    def test_empty_group_is_a_name_alone(self):
        self.assertEqual(self.people("group"), [("undisclosed-recipients", "")])

    def test_summary(self):
        s = self.out["summary"]
        self.assertEqual(s["none"], "")
        self.assertEqual(s["one"], "Anna")
        self.assertEqual(s["two"], "Anna and Pekka")
        self.assertEqual(s["three"], "Anna, Pekka and Liisa")
        self.assertEqual(s["five"], "Anna, Pekka and 3 more")


if __name__ == "__main__":
    unittest.main()
