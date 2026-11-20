#!/usr/bin/env python3
"""Ask Claude's answers as Markdown (AskClaudeMarkdown.js, #3272): `python3 config/quickshell/askclaude_markdown_test.py`.
While an answer streams in, its half-written last line is made whole (an open ** closed, a lone "#" or "-" left out,
a link's text alone until its address is there), so nothing flashes raw and then jumps; a finished answer is left as
it is. Its look: small headings, code blocks on a background, no #tag links.

The .js is QML's JavaScript, so it runs in Quickshell (offscreen), as kit/markdown_test.py does."""

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
import "%s" as Md
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const theme = { primary: "#0000ff", accent: "#00ff00", border: "#808080", dim: "#808080", title: "#ffffff", card: "#111111" }
            const out = { ready: {}, html: {} }
            for (const [name, md] of Object.entries(%s)) {
                out.ready[name] = Md.ready(md)
                out.html[name] = Md.html(md, theme, 15, false)
            }
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

CASES = {
    "bold_open": "Done:\n**Fil",
    "bold_just_opened": "Look at **",
    "bold_closed": "**Files:** two",
    "italic_open": "an *ital",
    "code_open": "run `nightdrive che",
    "list_marker": "Files:\n-",
    "heading_marker": "Intro\n##",
    "link_open": "see [the docs](https://night",
    "fence_open": "```sh\nnightdrive restart",
    "fence_closing": "```sh\nnightdrive restart\n``",
    "list_star": "* item with **bo",
    "snake": "a snake_case name",
    "heading": "# Title\n\ntext",
    "fence": "```\ncode\n```",
    "tag": "on #dev now",
}


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class AskClaudeMarkdown(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "AskClaudeMarkdown.js").as_uri(), json.dumps(CASES)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("AskClaudeMarkdown.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def ready(self, name):
        return self.out["ready"][name]

    def test_open_marks_are_closed(self):
        self.assertEqual(self.ready("bold_open"), "Done:\n**Fil**")
        self.assertEqual(self.ready("italic_open"), "an *ital*")
        self.assertEqual(self.ready("code_open"), "run `nightdrive che`")
        self.assertEqual(self.ready("list_star"), "* item with **bo**")

    def test_a_mark_with_no_text_yet_waits(self):
        self.assertEqual(self.ready("bold_just_opened"), "Look at ")
        self.assertEqual(self.ready("list_marker"), "Files:\n")
        self.assertEqual(self.ready("heading_marker"), "Intro\n")

    def test_link_shows_its_text_until_the_address_is_there(self):
        self.assertEqual(self.ready("link_open"), "see the docs")

    def test_open_code_block_is_left_alone_but_a_half_fence(self):
        self.assertEqual(self.ready("fence_open"), "```sh\nnightdrive restart")
        self.assertEqual(self.ready("fence_closing"), "```sh\nnightdrive restart")

    def test_whole_text_is_unchanged(self):
        self.assertEqual(self.ready("bold_closed"), "**Files:** two")
        self.assertEqual(self.ready("snake"), "a snake_case name")

    def test_look(self):
        html = self.out["html"]
        self.assertIn("font-size:18px", html["heading"])    # the answer's 15 px + 3, not a note's 22
        self.assertIn('bgcolor="#111111"', html["fence"])
        self.assertIn("white-space:pre-wrap", html["fence"])   # a long line wraps in the card (#3274)
        self.assertNotIn("tag:", html["tag"])


if __name__ == "__main__":
    unittest.main()
