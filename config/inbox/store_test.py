#!/usr/bin/env python3
"""Tests for store.py: a message's folder, read and archived, update and its undo, ids typed short."""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import store  # noqa: E402

SENDER = {"kind": "app", "app": "Test"}


def no_files(dest, existing):
    return list(existing)


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["XDG_DATA_HOME"] = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def post(self, title="Hello", body="Text"):
        return store.create(title, body, SENDER, None, [], no_files)

    def test_create_writes_a_folder_with_the_message(self):
        msg = self.post()
        path = store.root() / msg["id"] / "message.json"
        data = json.loads(path.read_text())
        self.assertEqual((data["title"], data["body"], data["read"], data["v"]), ("Hello", "Text", None, 1))
        self.assertNotIn("archived", data)
        self.assertFalse(msg["archived"])
        self.assertRegex(msg["id"], store.ID)

    def test_no_temporary_folders_are_left(self):
        self.post()
        self.assertEqual([p.name for p in store.root().iterdir() if p.name.startswith(".new-")], [])

    def test_a_failed_attach_leaves_nothing(self):
        def broken(dest, existing):
            raise store.InboxError("no")
        with self.assertRaises(store.InboxError):
            store.create("x", "", SENDER, None, [], broken)
        self.assertEqual(store.messages(), [])
        self.assertEqual([p.name for p in store.root().iterdir() if not p.name.startswith(".lock")], [])

    def test_newest_first_and_an_update_comes_back_to_the_top(self):
        a = self.post("A")
        b = self.post("B")
        self._age(a["id"], "2026-01-01T00:00:00+02:00")
        self._age(b["id"], "2026-01-02T00:00:00+02:00")
        self.assertEqual([m["title"] for m in store.messages()], ["B", "A"])
        store.update(a["id"], lambda m, p: m.update(body="more"))
        self.assertEqual([m["title"] for m in store.messages()], ["A", "B"])

    def _age(self, mid, stamp):
        path = store.folder(mid)
        msg = store.load(path)
        msg["at"] = msg["updated"] = stamp
        store.save(path, msg)

    def test_read_and_unread(self):
        mid = self.post()["id"]
        first = store.set_read(mid)["read"]
        self.assertTrue(first)
        self.assertEqual(store.set_read(mid)["read"], first, "reading again keeps when it was first read")
        self.assertIsNone(store.set_read(mid, False)["read"])

    def test_archive_and_back(self):
        mid = self.post()["id"]
        self.assertTrue(store.set_archived(mid)["archived"])
        self.assertEqual(store.messages(), [])
        self.assertEqual([m["id"] for m in store.messages(True)], [mid])
        self.assertEqual(store.resolve(mid), mid, "an archived one is still found by its id")
        self.assertFalse(store.set_archived(mid, False)["archived"])
        self.assertEqual([m["id"] for m in store.messages()], [mid])

    def test_update_makes_it_unread_and_revert_undoes_it(self):
        mid = self.post()["id"]
        store.set_read(mid)

        def change(msg, path):
            (path / "new.txt").write_text("x")
            msg["body"] = "Changed"
            msg["attachments"] = msg["attachments"] + [{"name": "new.txt", "type": "text/plain", "size": 1}]
        msg, rev = store.update(mid, change)
        self.assertEqual((msg["body"], msg["read"], rev), ("Changed", None, 1))
        back = store.revert(mid, rev)
        self.assertEqual((back["body"], back["attachments"]), ("Text", []))
        self.assertFalse((store.folder(mid) / "new.txt").exists(), "the update's file goes with it")
        with self.assertRaises(store.InboxError):
            store.revert(mid, rev)

    def test_a_short_id_finds_one_and_only_one(self):
        mid = self.post()["id"]
        self.assertEqual(store.resolve(mid[-4:]), mid)
        self.assertEqual(store.resolve(mid[:15]), mid)
        with self.assertRaises(store.InboxError):
            store.resolve("nope")

    def test_a_broken_message_does_not_hide_the_rest(self):
        self.post("Good")
        bad = store.root() / "20260101-000000-dead"
        bad.mkdir()
        (bad / "message.json").write_text("{")
        self.assertEqual([m["title"] for m in store.messages()], ["Good"])

    def test_delete(self):
        mid = self.post()["id"]
        store.delete(mid)
        self.assertIsNone(store.folder(mid))
        with self.assertRaises(store.InboxError):
            store.delete(mid)

    def test_root_follows_xdg_data_home(self):
        self.assertEqual(store.root(), Path(self.tmp.name) / "nightdrive" / "inbox")


if __name__ == "__main__":
    unittest.main()
