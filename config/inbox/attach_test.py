#!/usr/bin/env python3
"""Tests for attach.py: which files may be attached, and how they are copied in."""
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import attach  # noqa: E402
from store import InboxError  # noqa: E402


class AttachTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve() / "home"
        (self.home / "shots").mkdir(parents=True)
        (self.home / ".ssh").mkdir()
        (self.home / ".ssh" / "id_ed25519").write_text("key")
        (self.home / "shots" / "a.png").write_bytes(b"\x89PNG")
        (self.home / "shots" / ".env").write_text("SECRET=1")
        self.patch = mock.patch.object(attach, "ROOTS", (self.home,))
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.tmp.cleanup()

    def test_a_file_in_home_relative_to_the_sender(self):
        self.assertEqual(attach.checked(["shots/a.png"], self.home), [self.home / "shots" / "a.png"])

    def test_hidden_files_and_folders_are_refused(self):
        for p in (".ssh/id_ed25519", "shots/.env"):
            with self.subTest(p=p), self.assertRaises(InboxError):
                attach.checked([p], self.home)

    def test_a_link_counts_where_it_points(self):
        (self.home / "shots" / "key.png").symlink_to(self.home / ".ssh" / "id_ed25519")
        with self.assertRaises(InboxError):
            attach.checked(["shots/key.png"], self.home)

    def test_outside_home_folders_and_missing_files(self):
        for p in ("/etc/hostname", "shots", "shots/none.png"):
            with self.subTest(p=p), self.assertRaises(InboxError):
                attach.checked([p], self.home)

    def test_size_and_count(self):
        with mock.patch.object(attach, "SIZE_MAX", 2), self.assertRaises(InboxError):
            attach.checked(["shots/a.png"], self.home)
        with self.assertRaises(InboxError):
            attach.checked(["shots/a.png"], self.home, already=attach.FILES_MAX)

    def test_copies_with_a_free_name(self):
        dest = Path(self.tmp.name) / "msg"
        dest.mkdir()
        files = attach.checked(["shots/a.png", "shots/a.png"], self.home)
        entries = attach.copier(files)(dest, [])
        self.assertEqual([e["name"] for e in entries], ["a.png", "a-2.png"])
        self.assertEqual(entries[0]["type"], "image/png")
        self.assertEqual((dest / "a-2.png").read_bytes(), b"\x89PNG")

    def test_reserved_names_are_not_overwritten(self):
        dest = Path(self.tmp.name) / "msg"
        dest.mkdir()
        self.assertEqual(attach.free_name(dest, "message.json", set()), "message-2.json")
        self.assertEqual(attach.free_name(dest, ".hidden", set()), "hidden")


if __name__ == "__main__":
    unittest.main()
