"""Nightdrive Inbox in Companion (inbox.py): the real inbox command on a throwaway store, read and changed as the page
does it, its files given only from their own message, and the made-up messages of the demo.

    python3 config/companion/lib/inbox_test.py
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inbox  # noqa: E402


class StoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir="/tmp")
        self.old = os.environ.get("XDG_DATA_HOME")
        os.environ["XDG_DATA_HOME"] = os.path.join(self.tmp.name, "data")
        self.pic = os.path.join(self.tmp.name, "shot one.png")
        with open(self.pic, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n" + b"0" * 32)

    def tearDown(self):
        if self.old is None:
            os.environ.pop("XDG_DATA_HOME", None)
        else:
            os.environ["XDG_DATA_HOME"] = self.old
        self.tmp.cleanup()

    def post(self, title, *args):
        p = subprocess.run([sys.executable, inbox.CLI, "post", title, "--app", "Test", "--json", *args],
                           capture_output=True, text=True, check=True)
        return json.loads(p.stdout)["id"]

    def test_count_list_and_show(self):
        box = inbox.Inbox()
        self.assertEqual(box.state()["unread"], 0)
        mid = self.post("Have a look", "--body", "**Done**", "--attach", self.pic)
        self.post("Another")
        st = box.state()
        self.assertEqual((st["unread"], st["total"]), (2, 2))
        got = box.list()
        # newest first; posted within one second here, so either order
        self.assertEqual(sorted(m["title"] for m in got["messages"]), ["Another", "Have a look"])
        row = next(m for m in got["messages"] if m["id"] == mid)
        self.assertEqual(row["attachments"], 1)
        self.assertNotIn("folder", row)
        msg = box.show(mid)
        self.assertEqual(msg["body"], "**Done**")
        self.assertEqual(msg["attachments"][0]["url"], f"/api/inbox/{mid}/files/shot%20one.png")
        self.assertNotIn(self.tmp.name, str(msg))     # no path of the computer reaches the page

    def test_read_and_archive_change_the_stamp(self):
        box = inbox.Inbox()
        mid = self.post("Read me")
        first = box.state()
        box.show(mid, mark_read=True)
        second = box.state()
        self.assertNotEqual(first["stamp"], second["stamp"])
        self.assertEqual(second["unread"], 0)
        box.read(mid, unread=True)
        self.assertEqual(box.state()["unread"], 1)
        box.archive(mid)
        self.assertEqual(box.state()["total"], 0)
        box.archive(mid, undo=True)
        self.assertEqual(box.state()["total"], 1)

    def test_files_only_its_own(self):
        box = inbox.Inbox()
        mid = self.post("Pic", "--attach", self.pic)
        path, ctype = box.file(mid, "shot one.png")
        self.assertTrue(path.startswith(os.environ["XDG_DATA_HOME"]))
        self.assertEqual(ctype, "image/png")
        for name in ("message.json", "../" + mid + "/message.json", "nope.png"):
            with self.assertRaises(inbox.InboxError):
                box.file(mid, name)

    def test_ids_are_checked_before_the_command(self):
        box = inbox.Inbox()
        for bad in ("--all", "../x", "a3f1", "", None):
            with self.assertRaises(inbox.InboxError):
                box.read(bad)
        with self.assertRaises(inbox.InboxError):
            box.show("20261120-101500-ffff")       # well formed, not there: the command says so


class DemoTest(unittest.TestCase):
    def test_read_and_archive_in_memory(self):
        box = inbox.Demo()
        st = box.state()
        self.assertEqual(st["unread"], 2)
        mid = box.list()["messages"][0]["id"]
        self.assertTrue(box.show(mid)["attachments"][0]["url"].endswith("icon.png"))
        box.show(mid, mark_read=True)
        self.assertEqual(box.state()["unread"], 1)
        box.archive(mid)
        self.assertEqual(len(box.list()["messages"]), 2)
        self.assertNotEqual(box.state()["stamp"], st["stamp"])
        path, _ = box.file(mid, "icon.png")
        self.assertTrue(os.path.isfile(path))


if __name__ == "__main__":
    unittest.main()
