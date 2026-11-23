#!/usr/bin/env python3
"""results_add (#2243): `python3 config/mcp/results_test.py`. What a card may say (types, its file one this
conversation downloaded and of the right kind, an http(s) source, the licence "unknown" when not given, clean text),
that cards land whole in the conversation's results.json, one per file or page, and that the tool is a read of the
core area, which even Strict allows."""

import contextlib
import io
import json
import os
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "web"))

import download  # noqa: E402
import registry  # noqa: E402
import results  # noqa: E402


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


PNG = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(b"\x00\x00")) + chunk(b"IEND", b""))
OGG = b"OggS" + b"\x00" * 24 + b"\x01vorbis" + b"\x00" * 30
PDF = b"%PDF-1.7\n" + b"\x00" * 60
SOURCE = "https://freesound.org/people/someone/sounds/123/"


class Results(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = Path(self.tmp.name) / "ask"
        self.folder = self.state / "3f1c-run" / "files"
        self.folder.mkdir(parents=True)
        for name, data in (("engine.ogg", OGG), ("lake.png", PNG), ("manual.pdf", PDF)):
            (self.folder / name).write_bytes(data)
        self.patches = [mock.patch.object(download, "STATE", self.state),
                        mock.patch.dict(os.environ, {download.ENV: str(self.folder)})]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def add(self, **args):
        out, err = io.StringIO(), io.StringIO()
        code = 0
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                mock.patch("sys.stdin", io.StringIO(json.dumps(args))):
            try:
                results.main(["add"])
            except SystemExit as e:
                code = e.code
        return code, out.getvalue(), err.getvalue()

    def cards(self):
        path = self.folder.parent / results.NAME
        return json.loads(path.read_text())["cards"] if path.exists() else []

    def test_sound_card(self):
        code, out, err = self.add(type="sound", title="Engine sputter", url=SOURCE, file="engine.ogg",
                                  licence="CC0", author="someone", note="4 s, loops")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out), {"card": 1, "cards": 1})
        card = self.cards()[0]
        self.assertEqual({k: card[k] for k in ("n", "type", "title", "url", "file", "mime", "size", "licence",
                                               "author", "note")},
                         {"n": 1, "type": "sound", "title": "Engine sputter", "url": SOURCE, "file": "engine.ogg",
                          "mime": "audio/ogg", "size": len(OGG), "licence": "CC0", "author": "someone",
                          "note": "4 s, loops"})
        self.assertIn("added", card)

    def test_page_card_and_unknown_licence(self):
        code, _, err = self.add(type="page", title="Free engine sounds", url="https://example.org/engines")
        self.assertEqual(code, 0, err)
        card = self.cards()[0]
        self.assertEqual(card["licence"], results.UNKNOWN)
        self.assertNotIn("file", card)
        self.assertNotIn("author", card)

    def test_cards_are_numbered_in_order(self):
        self.add(type="image", title="Lake", url=SOURCE, file="lake.png")
        self.add(type="file", title="Manual", url=SOURCE, file="manual.pdf")
        code, out, _ = self.add(type="page", title="Source", url=SOURCE)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {"card": 3, "cards": 3})
        self.assertEqual([(c["n"], c["type"]) for c in self.cards()], [(1, "image"), (2, "file"), (3, "page")])

    def test_file_must_be_of_the_cards_kind(self):
        for kind, name in (("sound", "lake.png"), ("image", "engine.ogg"), ("image", "manual.pdf")):
            code, _, err = self.add(type=kind, title="x", url=SOURCE, file=name)
            self.assertEqual(code, 1, (kind, name))
            self.assertIn("not", err)
        self.assertEqual(self.cards(), [])

    def test_type_is_read_from_the_file_not_its_name(self):
        (self.folder / "fake.png").write_bytes(b"#!/bin/sh\necho hi\n")
        code, _, err = self.add(type="image", title="x", url=SOURCE, file="fake.png")
        self.assertEqual(code, 1)
        self.assertIn("isn't a file a card can show", err)

    def test_file_must_be_this_conversations_download(self):
        outside = Path(self.tmp.name) / "secret.png"
        outside.write_bytes(PNG)
        (self.folder / "link.png").symlink_to(outside)
        (self.folder / ".part-x").write_bytes(PNG)
        for name in ("../../secret.png", "/etc/passwd", "link.png", ".part-x", "missing.png", "", 5):
            code, _, err = self.add(type="image", title="x", url=SOURCE, file=name)
            self.assertEqual(code, 1, name)
        self.assertEqual(self.cards(), [])

    def test_downloads_need_a_file_and_pages_none(self):
        self.assertEqual(self.add(type="sound", title="x", url=SOURCE)[0], 1)
        self.assertEqual(self.add(type="page", title="x", url=SOURCE, file="lake.png")[0], 1)

    def test_bad_arguments(self):
        for args in ({"type": "video", "title": "x", "url": SOURCE},
                     {"type": "page", "title": "  ", "url": SOURCE},
                     {"type": "page", "title": "x", "url": "file:///etc/passwd"},
                     {"type": "page", "title": "x", "url": "javascript:alert(1)"},
                     {"type": "page", "title": "x"},
                     {"type": "page", "title": ["x"], "url": SOURCE},
                     {"type": "page", "title": "x", "url": SOURCE, "path": "/etc"}):
            code, _, _ = self.add(**args)
            self.assertEqual(code, 1, args)
        self.assertEqual(self.cards(), [])

    def test_text_is_cleaned_and_cut(self):
        title = "Engine‮3pm.exe\n\x1b[31mred " + "x" * 300
        code, _, err = self.add(type="page", title=title, url=SOURCE, licence="CC\tBY 4.0")
        self.assertEqual(code, 0, err)
        card = self.cards()[0]
        self.assertNotRegex(card["title"], r"[‮\n\x1b]")
        self.assertEqual(len(card["title"]), results.LIMITS["title"])
        self.assertTrue(card["title"].endswith("…"))
        self.assertEqual(card["licence"], "CC BY 4.0")

    def test_one_card_per_file_or_page(self):
        self.assertEqual(self.add(type="image", title="Lake", url=SOURCE, file="lake.png")[0], 0)
        code, _, err = self.add(type="file", title="Lake again", url=SOURCE, file="lake.png")
        self.assertEqual(code, 1)
        self.assertIn("already", err)
        self.assertEqual(self.add(type="page", title="Its page", url=SOURCE)[0], 0)   # the source page is another
        self.assertEqual(self.add(type="page", title="Its page again", url=SOURCE)[0], 1)
        self.assertEqual(len(self.cards()), 2)

    def test_at_most_cards_max(self):
        with mock.patch.object(results, "CARDS_MAX", 2):
            self.add(type="page", title="a", url=SOURCE + "a")
            self.add(type="page", title="b", url=SOURCE + "b")
            code, _, err = self.add(type="page", title="c", url=SOURCE + "c")
        self.assertEqual(code, 1)
        self.assertIn("2 cards", err)

    def test_a_broken_results_file_starts_over(self):
        (self.folder.parent / results.NAME).write_text("{not json")
        self.assertEqual(self.add(type="page", title="a", url=SOURCE)[0], 0)
        self.assertEqual(len(self.cards()), 1)

    def test_only_in_ask_claude(self):
        with mock.patch.dict(os.environ, {download.ENV: ""}):
            code, _, err = self.add(type="page", title="a", url=SOURCE)
        self.assertEqual(code, 1)
        self.assertIn("only in Ask Claude", err)
        with mock.patch.dict(os.environ, {download.ENV: str(Path(self.tmp.name) / "elsewhere")}):
            self.assertEqual(self.add(type="page", title="a", url=SOURCE)[0], 1)
        self.assertFalse((Path(self.tmp.name) / results.NAME).exists())


class Tool(unittest.TestCase):
    def test_a_read_of_the_core_area(self):
        spec = json.loads((HERE / "tools" / "results.json").read_text())["tools"][0]
        self.assertIsNone(registry.problem(spec, None))
        self.assertEqual((spec["name"], spec["class"], spec["area"]), ("results_add", "read", "nightdrive"))
        self.assertEqual(spec["inputSchema"]["properties"]["type"]["enum"], list(results.TYPES))


if __name__ == "__main__":
    unittest.main()
