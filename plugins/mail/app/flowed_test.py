#!/usr/bin/env python3
"""How Mail joins a format=flowed text's lines (#3321): `python3 plugins/mail/app/flowed_test.py`.
app/flowed.js (the read view, run in Quickshell offscreen) joins a soft break's lines, and only those, and keeps quotes,
signatures and fixed lines as they are; lib/flowed.py says which messages' header has format=flowed (and DelSp)."""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from email.message import EmailMessage
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lib"))

import flowed  # noqa: E402

RUNNER = """
import QtQuick
import Quickshell
import "%s" as Flowed
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const out = {}
            for (const [name, c] of Object.entries(%s)) out[name] = [Flowed.unflow(c[0], c[1]), Flowed.maybe(c[0])]
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

CASES = {
    # name: (text, delsp, what unflow() makes of it, what maybe() says)
    "paragraph": ("One line that \ngoes on here \nand ends.\nNext line.", False,
                  "One line that goes on here and ends.\nNext line.", True),
    # DelSp=yes: the wrap added a space (Gmail's breaks between words end in two)
    "delsp": ("Pitkä sana tai  \nlause loppuu.\nkatkää \nsanan", True,
              "Pitkä sana tai lause loppuu.\nkatkääsanan", True),
    # (a flowed sender stuffs a line that begins with a space: "    code()" is sent with five)
    "fixed_kept": ("- one\n- two\nhttps://example.com/a\n     code()", False,
                   "- one\n- two\nhttps://example.com/a\n    code()", False),
    "paragraphs": ("First \npara.\n\nSecond \npara.", False, "First para.\n\nSecond para.", True),
    "quote": ("> Quoted text \n> goes on.\n>> Deeper \n>> too.\nMine.", False,
              "> Quoted text goes on.\n>> Deeper too.\nMine.", True),
    # A soft break before a change of depth is a hard one
    "depth_change": ("> ends soft \nnot quoted", False, "> ends soft \nnot quoted", True),
    "quote_blank": (">\n> a", False, ">\n> a", False),
    "signature": ("Thanks, \nMe\n-- \nName \nCompany", False, "Thanks, Me\n-- \nName Company", True),
    "signature_only": ("Hi\n-- \nName", False, "Hi\n-- \nName", False),
    # Space-stuffing: a line that began with a space, "From" or ">" got one more; it goes
    "stuffed": ("Text \n From here on\n >not a quote", False, "Text From here on\n>not a quote", True),
    "crlf": ("a \r\nb\r\n", False, "a b\n", True),
    "soft_last": ("ends soft ", False, "ends soft ", False),
    "empty": ("", False, "", False),
}


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Script(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            cases = {k: [v[0], v[1]] for k, v in CASES.items()}
            shell.write_text(RUNNER % ((HERE / "flowed.js").as_uri(), json.dumps(cases)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("flowed.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def test_unflow(self):
        for name, (_, _, want, _) in CASES.items():
            with self.subTest(name):
                self.assertEqual(self.out[name][0], want)

    def test_maybe(self):
        for name, (_, _, _, want) in CASES.items():
            with self.subTest(name):
                self.assertEqual(self.out[name][1], want)


def message(params, alternative=False, attached_first=False):
    msg = EmailMessage()
    msg["Subject"] = "test"
    if attached_first:
        msg.set_content("intro")
        msg.add_attachment("notes \nflowed", subtype="plain", filename="notes.txt", params={"format": "flowed"})
        return msg
    msg.set_content("Line \nnext\n")
    for k, v in params.items():
        msg.set_param(k, v)
    if alternative:
        msg.add_alternative("<p>Line next</p>", subtype="html")
    return msg


class Header(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def path(self, msg, name="m"):
        p = Path(self.dir.name) / name
        p.write_bytes(msg.as_bytes())
        return str(p)

    def test_flowed_and_delsp(self):
        self.assertIs(flowed.flowed(self.path(message({"format": "flowed", "delsp": "yes"}))), True)
        self.assertIs(flowed.flowed(self.path(message({"format": "Flowed"}))), False)

    def test_not_flowed(self):
        self.assertIsNone(flowed.flowed(self.path(message({}))))
        self.assertIsNone(flowed.flowed(self.path(message({"format": "fixed"}))))

    def test_in_multipart_alternative(self):
        self.assertIs(flowed.flowed(self.path(message({"format": "flowed"}, alternative=True))), False)

    def test_attached_text_doesnt_count(self):
        self.assertIsNone(flowed.flowed(self.path(message({}, attached_first=True))))

    def test_command(self):
        a = self.path(message({"format": "flowed", "delsp": "yes"}), "a")
        b = self.path(message({}), "b")
        run = subprocess.run([sys.executable, "-I", str(HERE.parent / "lib" / "flowed.py"),
                              "id-a", a, "id-b", b, "id-c", str(Path(self.dir.name) / "missing")],
                             capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(run.stdout), {"id-a": True})


if __name__ == "__main__":
    unittest.main()
