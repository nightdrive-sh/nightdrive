#!/usr/bin/env python3
"""A save while writing (#3660) never brings back a draft that left Drafts elsewhere: `python3
plugins/mail/lib/autosave_test.py`. The writing window saves every few seconds over its last copy (draft_id); when
that copy was sent, thrown away or replaced by Claude meanwhile, a new copy would be a second draft of one message
(#3625). ⌘S, the user's own save, still saves it."""

import sys
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import compose  # noqa: E402


class Autosave(unittest.TestCase):
    def save(self, f, files, after_sync=()):
        filed, dropped = [], []
        with mock.patch.object(compose, "files_of", lambda mid: list(files)), \
                mock.patch.object(compose, "reindexed", lambda mid: list(after_sync)), \
                mock.patch.object(compose, "account", lambda aid: {"drafts": "a/Drafts"}), \
                mock.patch.object(compose, "build", lambda acc, f: {"Message-ID": "<new@x.y>"}), \
                mock.patch.object(compose, "file_in", lambda folder, msg, tags: filed.append(folder)), \
                mock.patch.object(compose, "drop", lambda mid: dropped.append(mid)):
            return compose.draft(f), filed, dropped

    def test_over_its_copy(self):
        r, filed, dropped = self.save({"draft_id": "old@x.y", "autosave": True}, ["/m/a/Drafts/cur/1"])
        self.assertEqual((r.get("id"), filed, dropped), ("new@x.y", ["a/Drafts"], ["old@x.y"]))

    def test_copy_gone(self):
        r, filed, dropped = self.save({"draft_id": "old@x.y", "autosave": True}, [])
        self.assertTrue(r.get("gone"))
        self.assertEqual((filed, dropped), ([], []))

    def test_copy_renamed_by_a_sync(self):
        r, filed, _ = self.save({"draft_id": "old@x.y", "autosave": True}, [], after_sync=["/m/a/Drafts/cur/1,S"])
        self.assertEqual((r.get("id"), filed), ("new@x.y", ["a/Drafts"]))

    def test_first_copy(self):
        r, filed, _ = self.save({"draft_id": "", "autosave": True}, [])
        self.assertEqual((r.get("id"), filed), ("new@x.y", ["a/Drafts"]))

    def test_own_save_always(self):
        r, filed, _ = self.save({"draft_id": "old@x.y"}, [])
        self.assertEqual((r.get("id"), filed), ("new@x.y", ["a/Drafts"]))


if __name__ == "__main__":
    unittest.main()
