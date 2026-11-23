"""The manifest (manifest.py): what a scan sends, what it leaves out, and a fresh start with another Hub.

    python3 config/hub/lib/manifest_test.py
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import manifest as mf  # noqa: E402


def put(root, rel, text):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


class ScanTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def test_hidden_links_and_rejected_left_out(self):
        put(self.root, "home/a.ics", "a")
        put(self.root, "home/.a.ics.tmp", "half")       # Tasks' own temporary
        put(self.root, ".hidden/b.ics", "b")
        put(self.root, "top.txt", "t")
        os.symlink("/etc/hostname", os.path.join(self.root, "home", "link.ics"))
        got = mf.scan(self.root, lambda p: p.count("/") == 1)
        self.assertEqual(list(got), ["home/a.ics"])
        self.assertEqual(got["home/a.ics"], mf.data_hash(b"a"))

    def test_missing_root_is_empty(self):
        self.assertEqual(mf.scan(os.path.join(self.root, "none"), lambda p: True), {})


class ManifestTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["XDG_STATE_HOME"] = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def test_saved_and_read_again(self):
        m = mf.Manifest("tasks")
        self.assertTrue(m.start("hub-1"))
        m.set("l/a.ics", 3, "h1")
        m.cursor = 3
        m.save()
        again = mf.Manifest("tasks")
        self.assertFalse(again.start("hub-1"))
        self.assertEqual((again.cursor, again.get("l/a.ics")), (3, {"v": 3, "h": "h1"}))

    def test_another_hub_starts_empty(self):
        m = mf.Manifest("tasks")
        m.start("hub-1")
        m.set("l/a.ics", 3, "h1")
        m.cursor = 3
        self.assertTrue(m.start("hub-2"))
        self.assertEqual((m.cursor, m.entries), (0, {}))

    def test_pending(self):
        m = mf.Manifest("tasks")
        m.set("l/same.ics", 1, "s")
        m.set("l/edited.ics", 2, "old")
        m.set("l/gone.ics", 3, "g")
        m.set("l/deleted-before.ics", 4, None)      # a tombstone both agree on: not a deletion to send again
        local = {"l/same.ics": "s", "l/edited.ics": "new", "l/new.ics": "n"}
        self.assertEqual(m.pending(local), (["l/edited.ics", "l/new.ics"], ["l/gone.ics"]))

    def test_broken_file_starts_fresh(self):
        os.makedirs(os.path.join(self.tmp.name, "nightdrive/hub"))
        with open(os.path.join(self.tmp.name, "nightdrive/hub/tasks.json"), "w") as f:
            f.write('{"server": "hub-1", "files": {')
        m = mf.Manifest("tasks")
        self.assertTrue(m.start("hub-1"))


if __name__ == "__main__":
    unittest.main()
