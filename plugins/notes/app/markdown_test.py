#!/usr/bin/env python3
"""How Notes reads lists (Markdown.js, #2056): `python3 plugins/notes/app/markdown_test.py`. A numbered list goes on
counting after a list nested in it (it started again at 1), lists nest at several levels, bullets and numbers mixed,
task boxes keep their order for TaskBoxes.qml, a blank line between items keeps one list, and "7." starts at 7. A
#tag is a link to its notes, where lib/tags.py reads one (#2016).

Markdown.js is QML's JavaScript, so it runs in Quickshell (offscreen): the HTML it makes is read back here as an
outline of what Qt shows, and the bug's case is also checked against Qt's own numbering (its document as Markdown)."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from html.parser import HTMLParser
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Each case's HTML, and Qt's own Markdown of it (a TextEdit's document switched from rich text to Markdown)
RUNNER = """
import QtQuick
import Quickshell
import "%s" as Markdown
ShellRoot {
    TextEdit { id: edit; textFormat: TextEdit.RichText }
    Timer {
        running: true; interval: 1
        onTriggered: {
            const c = { primary: Qt.rgba(0, 0, 1, 1), accent: "green", line: "gray", dim: "gray", title: "white" }
            const out = {}
            for (const [name, md] of Object.entries(%s)) {
                const html = Markdown.html(md, c)
                edit.textFormat = TextEdit.RichText
                edit.text = html
                edit.textFormat = TextEdit.MarkdownText
                out[name] = { html: html, qt: edit.text }
            }
            console.warn("RESULT " + JSON.stringify(out))
            Qt.quit()
        }
    }
}
"""

CASES = {
    # The bug: "3." after a nested list was drawn as 1.
    "nested": "1. First\n2. Second\n   - a\n   - b\n3. Third",
    "levels": ("1. One\n   - bullet\n     1. deep\n     2. deeper\n        - deepest\n   - bullet two\n"
               "2. Two\n   1. sub\n   2. sub two\n3. Three"),
    "boxes": "- [ ] first\n  - [x] nested done\n    1. [ ] numbered box\n- [ ] last",
    "two_spaces": "1. One\n  - two spaces nest too\n2. Two",
    "tab": "- top\n\t- under a tab\n- next",
    "blank": "1. a\n\n2. b\n\n3. c",
    "start": "Text\n\n7. seven\n8. eight",
    "kinds": "1. one\n2. two\n- bullet\n- bullet",
    "back_out": "- a\n  - b\n    - c\n- d",
    "continued": "1. item\n   more of it\n2. next",
    "paragraph_ends": "1. a\n2. b\n\nAfter\n\n1. new",
    # #2016: tags as lib/tags.py reads them
    "tags": "#idea and #työ/koti, task #2016, page#part, `#code`, [#in a link](https://a.b/#x) (#paren)",
}


class Outline(HTMLParser):
    """The HTML's lists as lines: "1. text" or "- text", two spaces a level; an <ol>'s items numbered from its start,
    as Qt numbers them (a list's items count on whatever is nested between them)."""

    def __init__(self):
        super().__init__()
        self.lines, self.lists = [], []

    def handle_starttag(self, tag, attrs):
        if tag in ("ol", "ul"):
            self.lists.append([tag, int(dict(attrs).get("start", 1)) - 1])
        elif tag == "li":
            kind = self.lists[-1]
            kind[1] += 1
            marker = f"{kind[1]}." if kind[0] == "ol" else "-"
            self.lines.append("  " * (len(self.lists) - 1) + marker + " ")
        elif tag == "br" and self.lists:
            self.lines[-1] += " / "

    def handle_endtag(self, tag):
        if tag in ("ol", "ul"):
            self.lists.pop()

    def handle_data(self, data):
        if self.lists and self.lines:          # an item's text, or the newlines between tags
            self.lines[-1] += data
        elif data.strip():
            self.lines.append(data)


def outline(html):
    parser = Outline()
    parser.feed(html)
    # Each line's indent kept, its text's spaces as one
    return [re.match(r" *", line).group() + " ".join(line.split()) for line in parser.lines]


@unittest.skipUnless(shutil.which("qs"), "needs Quickshell (qs)")
class Lists(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as tmp:
            shell = Path(tmp) / "shell.qml"
            shell.write_text(RUNNER % ((HERE / "Markdown.js").as_uri(), json.dumps(CASES)))
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", NO_COLOR="1")
            run = subprocess.run(["qs", "-p", str(shell)], env=env, capture_output=True, text=True, timeout=30)
        log = run.stdout + run.stderr
        found = re.search(r"RESULT (\{.*\})", log)
        if not found:
            raise AssertionError("Markdown.js didn't run:\n" + log)
        cls.out = json.loads(found.group(1))

    def lines(self, name):
        return outline(self.out[name]["html"])

    def test_numbering_goes_on_after_a_nested_list(self):
        self.assertEqual(self.lines("nested"), ["1. First", "2. Second", "  - a", "  - b", "3. Third"])
        # Qt's own numbers, where the bug was: its Markdown writes the top level's as they are drawn
        qt = re.findall(r"^(\d+)\.\s+(\w+)", self.out["nested"]["qt"], re.M)
        self.assertEqual(qt, [("1", "First"), ("2", "Second"), ("3", "Third")])

    def test_several_levels_mixed(self):
        self.assertEqual(self.lines("levels"), [
            "1. One", "  - bullet", "    1. deep", "    2. deeper", "      - deepest", "  - bullet two",
            "2. Two", "  1. sub", "  2. sub two", "3. Three"])

    def test_task_boxes_nested(self):
        self.assertEqual(self.lines("boxes"), [
            "- ☐ first", "  - ☑ nested done", "    1. ☐ numbered box", "- ☐ last"])
        # In the order ListEdit.boxes counts them, which a click ticks by (TaskBoxes.qml)
        self.assertEqual(re.findall(r'href="box:(\d+)"', self.out["boxes"]["html"]), ["0", "1", "2", "3"])

    def test_two_spaces_nest_under_a_number(self):
        self.assertEqual(self.lines("two_spaces"), ["1. One", "  - two spaces nest too", "2. Two"])

    def test_tab_nests(self):
        self.assertEqual(self.lines("tab"), ["- top", "  - under a tab", "- next"])

    def test_blank_lines_keep_one_list(self):
        self.assertEqual(self.lines("blank"), ["1. a", "2. b", "3. c"])

    def test_list_starts_at_its_first_number(self):
        self.assertEqual(self.lines("start"), ["Text", "7. seven", "8. eight"])

    def test_kind_changing_starts_a_new_list(self):
        self.assertEqual(self.lines("kinds"), ["1. one", "2. two", "- bullet", "- bullet"])
        self.assertEqual(self.out["kinds"]["html"].count("<ul>"), 1)

    def test_back_out_several_levels(self):
        self.assertEqual(self.lines("back_out"), ["- a", "  - b", "    - c", "- d"])

    def test_indented_line_continues_its_item(self):
        self.assertEqual(self.lines("continued"), ["1. item / more of it", "2. next"])

    def test_paragraph_ends_the_list(self):
        self.assertEqual(self.lines("paragraph_ends"), ["1. a", "2. b", "After", "1. new"])

    def test_hash_tags_are_links(self):
        self.assertEqual(re.findall(r'href="tag:([^"]+)"', self.out["tags"]["html"]), ["idea", "työ/koti", "paren"])

    def test_tags_balance(self):
        for name, result in self.out.items():
            html = result["html"]
            for tag in ("ol", "ul", "li"):
                opened = len(re.findall(rf"<{tag}[ >]", html))
                self.assertEqual(opened, html.count(f"</{tag}>"), f"{name}: <{tag}>")


if __name__ == "__main__":
    unittest.main()
