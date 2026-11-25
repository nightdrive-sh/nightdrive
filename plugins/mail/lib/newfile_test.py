#!/usr/bin/env python3
"""Saving an attachment without asking (#3627): `python3 plugins/mail/lib/newfile_test.py`. Nothing in the folder is
overwritten: a name taken gets " (2)", " (3)" …, several at once with the same name each get their own, and a save
that fails halfway leaves nothing behind."""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import newfile  # noqa: E402


class Numbered(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_free_name_kept(self):
        self.assertEqual(newfile.create(self.dir, "invoice.pdf", b"a").name, "invoice.pdf")

    def test_taken_gets_a_number_and_nothing_is_overwritten(self):
        (self.dir / "invoice.pdf").write_bytes(b"mine")
        (self.dir / "invoice (2).pdf").write_bytes(b"mine too")
        path = newfile.create(self.dir, "invoice.pdf", b"new")
        self.assertEqual(path.name, "invoice (3).pdf")
        self.assertEqual((self.dir / "invoice.pdf").read_bytes(), b"mine")
        self.assertEqual((self.dir / "invoice (2).pdf").read_bytes(), b"mine too")

    def test_no_extension_and_two_dots(self):
        (self.dir / "README").write_bytes(b"")
        (self.dir / "a.tar.gz").write_bytes(b"")
        self.assertEqual(newfile.create(self.dir, "README", b"").name, "README (2)")
        self.assertEqual(newfile.create(self.dir, "a.tar.gz", b"").name, "a.tar (2).gz")

    def test_several_with_one_name(self):
        paths = newfile.write_all(self.dir, [("scan.jpg", b"1"), ("scan.jpg", b"2"), ("scan.jpg", b"3")])
        self.assertEqual([p.name for p in paths], ["scan.jpg", "scan (2).jpg", "scan (3).jpg"])
        self.assertEqual([p.read_bytes() for p in paths], [b"1", b"2", b"3"])

    def test_not_runnable(self):
        path = newfile.create(self.dir, "run.sh", b"#!/bin/sh\n")
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o644 & ~current_umask())

    def test_a_symlink_is_not_written_through(self):
        target = self.dir / "elsewhere"
        target.write_bytes(b"keep")
        (self.dir / "x.txt").symlink_to(target)
        self.assertEqual(newfile.create(self.dir, "x.txt", b"new").name, "x (2).txt")
        self.assertEqual(target.read_bytes(), b"keep")

    def test_all_or_none(self):
        real = newfile.create
        calls = []

        def failing(folder, name, data):
            calls.append(name)
            if len(calls) == 2:
                raise OSError("disk full")
            return real(folder, name, data)
        with mock.patch.object(newfile, "create", failing), self.assertRaises(OSError):
            newfile.write_all(self.dir, [("a.txt", b"1"), ("b.txt", b"2")])
        self.assertEqual(list(self.dir.iterdir()), [])


def current_umask():
    mask = os.umask(0)
    os.umask(mask)
    return mask


if __name__ == "__main__":
    unittest.main()
