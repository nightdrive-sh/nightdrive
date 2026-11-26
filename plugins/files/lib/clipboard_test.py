#!/usr/bin/env python3
"""What Files' ⌘C / y and ⌘X / x offer on the clipboard (#3304): `python3 plugins/files/lib/clipboard_test.py`. The
files for file browsers (Nautilus's type with copy or cut, a uri-list), and the paths as text for a terminal or a
text field, one a line; and the Wayland strings the helper writes and reads."""

import sys
import unittest
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import clipboard  # noqa: E402

PATHS = ["/home/u/a b/c d.txt", "/home/u/ä#%.pdf", "/home/u/-dash"]


class Offers(unittest.TestCase):
    def test_types_in_order(self):
        d = clipboard.payloads(PATHS)
        self.assertEqual(list(d)[:2], ["x-special/gnome-copied-files", "text/uri-list"])
        for t in ("text/plain", "text/plain;charset=utf-8", "UTF8_STRING", "STRING", "TEXT"):
            self.assertIn(t, d)

    def test_files_for_file_browsers(self):
        d = clipboard.payloads(PATHS)
        lines = d["x-special/gnome-copied-files"].decode().split("\n")
        self.assertEqual(lines[0], "copy")
        self.assertEqual([unquote(u[len("file://"):]) for u in lines[1:]], PATHS)
        self.assertFalse(any(" " in u or "#" in u for u in lines[1:]))
        uris = d["text/uri-list"].decode()
        self.assertTrue(uris.endswith("\r\n"))
        self.assertEqual(uris.split("\r\n")[:-1], lines[1:])
        self.assertTrue(clipboard.payloads(PATHS, cut=True)["x-special/gnome-copied-files"].startswith(b"cut\n"))

    def test_paths_as_text_one_a_line(self):
        d = clipboard.payloads(PATHS)
        self.assertEqual(d["text/plain"].decode(), "\n".join(PATHS))
        self.assertEqual(clipboard.payloads(PATHS[:1])["text/plain"], PATHS[0].encode())   # no newline to run it

    def test_wire_strings(self):
        for s in ("", "a", "abc", "abcd", "text/plain;charset=utf-8", "ä"):
            b = clipboard._string(s)
            self.assertEqual(len(b) % 4, 0)
            self.assertEqual(clipboard._read_string(b + b"tail", 0), (s, len(b)))

    def test_usage(self):
        self.assertEqual(clipboard.main(["copy"]), 2)
        self.assertEqual(clipboard.main(["paste", "/x"]), 2)


if __name__ == "__main__":
    unittest.main()
