#!/usr/bin/env python3
"""Which pasted files the writing window attaches (#3304): `python3 plugins/mail/lib/clipfiles_test.py`. Files' ⌘C
and Nautilus offer gnome-copied-files and uri-list beside the text; only readable local files are attached, folders
are named apart, and a browser's links or a file that is gone leave the paste to be text."""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clipfiles  # noqa: E402


def board(offers):
    """A stand-in for wl-paste: {type: content}."""
    def paste(*args):
        if args == ("--list-types",):
            return "\n".join(offers)
        return offers[args[1]]
    return paste


class ClipFiles(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.a = self.dir / "with space ä.txt"
        self.a.write_text("a")
        self.b = self.dir / "b.pdf"
        self.b.write_text("b")
        self.folder = self.dir / "photos"
        self.folder.mkdir()

    def uri(self, p):
        return "file://" + quote(str(p))

    def test_files_copy_offers_nautilus_type_first(self):
        offers = {"x-special/gnome-copied-files": "copy\n" + "\n".join(self.uri(p) for p in (self.a, self.b)),
                  "text/uri-list": "file:///elsewhere\r\n", "text/plain": "ignored"}
        self.assertEqual(clipfiles.read(board(offers)), {"files": [str(self.a), str(self.b)], "folders": []})

    def test_cut_and_uri_list_with_comments(self):
        self.assertEqual(clipfiles.paths_of("cut\n" + self.uri(self.a)), [str(self.a)])
        text = "# from a browser\r\n" + self.uri(self.b) + "\r\nfile://localhost" + quote(str(self.a)) + "\r\n"
        self.assertEqual(clipfiles.read(board({"text/uri-list": text})),
                         {"files": [str(self.b), str(self.a)], "folders": []})

    def test_folder_named_apart(self):
        text = self.uri(self.a) + "\r\n" + self.uri(self.folder) + "\r\n"
        self.assertEqual(clipfiles.read(board({"text/uri-list": text})),
                         {"files": [str(self.a)], "folders": [str(self.folder)]})

    def test_text_web_links_and_missing_files_attach_nothing(self):
        none = {"files": [], "folders": []}
        self.assertEqual(clipfiles.read(board({"text/plain": "/some/path"})), none)
        self.assertEqual(clipfiles.read(board({"text/uri-list": "https://example.org/a.pdf\r\n"})), none)
        self.assertEqual(clipfiles.read(board({"text/uri-list": "file://otherhost/a\r\n"})), none)
        self.assertEqual(clipfiles.read(board({"text/uri-list": self.uri(self.dir / "gone.txt")})), none)

    @unittest.skipIf(os.geteuid() == 0, "root reads every file")
    def test_unreadable_file_left_out(self):
        self.b.chmod(0)
        self.assertEqual(clipfiles.sorted_out([str(self.b)]), {"files": [], "folders": []})

    def test_no_wl_paste(self):
        def broken(*args):
            raise FileNotFoundError("wl-paste")
        self.assertEqual(clipfiles.read(broken), {"files": [], "folders": []})


if __name__ == "__main__":
    unittest.main()
