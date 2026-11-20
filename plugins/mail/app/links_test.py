#!/usr/bin/env python3
"""How Mail finds links in a plain-text message (links.js, #2224): `python3 plugins/mail/app/links_test.py`.
A URL in parentheses or at the end of a sentence leaves the ")" and "." out, a Wikipedia address keeps its own
parentheses, a Markdown link [text](url) shows its text as the link, and an address alone in brackets [url] shows
without them (#3321).

links.js is QML's JavaScript, so it runs in Quickshell (offscreen) and its HTML is read back here."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from html import unescape
from pathlib import Path

HERE = Path(__file__).resolve().parent

RUNNER = """
import QtQuick
import Quickshell
import "%s" as Links
ShellRoot {
    Timer {
        running: true; interval: 1
        onTriggered: {
            const out = {}
            for (const [name, text] of Object.entries(%s)) out[name] = Links.rich(text, "green", "gray")
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

WIKI = "https://en.wikipedia.org/wiki/Heat_(1995_film)"
ISSUE = "https://github.com/anthropics/claude-code/issues/96288"
CASES = {
    # The task's case: GitHub's issue as a Markdown link, then a full stop
    "markdown": f"[#96288]({ISSUE}).",
    "parens": "Read this (https://example.com/page) first.",
    "parens_stop": "As said (https://example.com/a).",
    "wiki": f"The film {WIKI} is long.",
    "wiki_parens": f"(see {WIKI})",
    "wiki_markdown": f"[Heat]({WIKI}).",
    "stop": "Go to https://example.com/x.",
    "punctuation": "https://a.example/1, https://b.example/2; https://c.example/3! Really https://d.example/4?",
    "query": "https://example.com/s?q=a&b=c.",
    "quoted": "> earlier https://example.com/q.",
    "tags": 'Look <b>here</b> "https://example.com/z"',
    "two": "[one](https://one.example) and [two](https://two.example/(x))",
    "broken_markdown": "[text](https://example.com/open",
    # A newsletter's text made from HTML (#3321): the address alone in brackets
    "bracketed": "Docs: Variants \u2192 [https://www.sketch.com/docs/components-and-styles/variants/]",
    "bracketed_stop": "Download the latest version [https://example.com/dl/]. Or not.",
    "bracketed_two": "Privacy [https://example.com/p] | Unsubscribe [https://example.com/u?id=1&x=2]",
    "bracketed_text": "[see https://example.com/b]",
    "bracketed_markdown": "[https://shown.example](https://real.example)",
    "bracketed_quoted": "> Discord [https://discord.gg/abc] if",
    "bracketed_open": "[https://example.com/a](https://example.com/open",
}


def links(html):
    """Each <a> as (href, its text), unescaped."""
    return [(unescape(h), unescape(t)) for h, t in re.findall(r'<a href="([^"]*)"[^>]*>(.*?)</a>', html)]


def text(html):
    return unescape(re.sub(r"<[^>]+>", "", html))


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Links(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "links.js").as_uri(), json.dumps(CASES)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("links.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def test_markdown_link_shows_its_text(self):
        self.assertEqual(links(self.out["markdown"]), [(ISSUE, "#96288")])
        self.assertEqual(text(self.out["markdown"]), "#96288.")

    def test_url_in_parentheses(self):
        self.assertEqual(links(self.out["parens"]), [("https://example.com/page", "https://example.com/page")])
        self.assertEqual(text(self.out["parens"]), CASES["parens"])
        self.assertEqual(links(self.out["parens_stop"])[0][0], "https://example.com/a")

    def test_wikipedia_keeps_its_parentheses(self):
        self.assertEqual(links(self.out["wiki"])[0][0], WIKI)
        self.assertEqual(links(self.out["wiki_parens"])[0][0], WIKI)
        self.assertEqual(links(self.out["wiki_markdown"]), [(WIKI, "Heat")])

    def test_full_stop_at_the_end(self):
        self.assertEqual(links(self.out["stop"])[0][0], "https://example.com/x")
        self.assertEqual(text(self.out["stop"]), CASES["stop"])
        self.assertEqual(links(self.out["query"])[0][0], "https://example.com/s?q=a&b=c")

    def test_other_punctuation(self):
        self.assertEqual([h for h, _ in links(self.out["punctuation"])],
                         ["https://a.example/1", "https://b.example/2", "https://c.example/3", "https://d.example/4"])

    def test_quoted_line_is_faint_and_linked(self):
        self.assertTrue(self.out["quoted"].startswith('<span style="color:gray">'))
        self.assertEqual(links(self.out["quoted"])[0][0], "https://example.com/q")

    def test_text_is_escaped(self):
        self.assertNotIn("<b>", self.out["tags"])
        self.assertEqual(links(self.out["tags"])[0][0], "https://example.com/z")

    def test_several_markdown_links(self):
        self.assertEqual(links(self.out["two"]),
                         [("https://one.example", "one"), ("https://two.example/(x)", "two")])

    def test_unclosed_markdown_falls_back_to_the_url(self):
        self.assertEqual(links(self.out["broken_markdown"])[0][0], "https://example.com/open")

    def test_bracketed_address_loses_its_brackets(self):
        url = "https://www.sketch.com/docs/components-and-styles/variants/"
        self.assertEqual(links(self.out["bracketed"]), [(url, url)])
        self.assertEqual(text(self.out["bracketed"]), "Docs: Variants \u2192 " + url)
        self.assertEqual(text(self.out["bracketed_stop"]), "Download the latest version https://example.com/dl/. Or not.")
        self.assertEqual(links(self.out["bracketed_stop"])[0][0], "https://example.com/dl/")

    def test_several_bracketed_addresses(self):
        self.assertEqual([h for h, _ in links(self.out["bracketed_two"])],
                         ["https://example.com/p", "https://example.com/u?id=1&x=2"])
        self.assertEqual(text(self.out["bracketed_two"]),
                         "Privacy https://example.com/p | Unsubscribe https://example.com/u?id=1&x=2")

    def test_brackets_around_more_than_an_address_stay(self):
        # Only the address is linked: the "]" isn't part of it
        self.assertEqual(links(self.out["bracketed_text"]), [("https://example.com/b", "https://example.com/b")])
        self.assertEqual(text(self.out["bracketed_text"]), CASES["bracketed_text"])

    def test_markdown_link_with_an_address_as_its_text(self):
        self.assertEqual(links(self.out["bracketed_markdown"]), [("https://real.example", "https://shown.example")])

    def test_bracketed_in_a_quote(self):
        self.assertTrue(self.out["bracketed_quoted"].startswith('<span style="color:gray">'))
        self.assertEqual(text(self.out["bracketed_quoted"]), "> Discord https://discord.gg/abc if")

    def test_bracketed_before_an_unclosed_markdown_url(self):
        self.assertEqual(links(self.out["bracketed_open"])[0][0], "https://example.com/a")


if __name__ == "__main__":
    unittest.main()
