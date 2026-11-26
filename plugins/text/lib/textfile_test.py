#!/usr/bin/env python3
"""Tests for textfile.py: what reads as text, and that a save keeps links, modes, line ends and others' changes."""
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import textfile  # noqa: E402

SCRIPT = os.path.join(HERE, "textfile.py")


def run(*args, stdin=b""):
    return subprocess.run([sys.executable, "-I", SCRIPT, *args], input=stdin, capture_output=True)


class TextFileTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def file(self, name, data):
        path = os.path.join(self.dir, name)
        with open(path, "wb") as f:
            f.write(data)
        return path

    def test_read_gives_text_and_md5(self):
        path = self.file("a.txt", "hei\nmaailma\n".encode())
        out = json.loads(run("read", path).stdout)
        self.assertEqual(out["text"], "hei\nmaailma\n")
        self.assertEqual(out["md5"], textfile.md5("hei\nmaailma\n"))
        self.assertFalse(out["crlf"])
        self.assertTrue(out["writable"])

    def test_refuses_binary_and_other_encodings(self):
        for data in (b"\x89PNG\0\0", "ä".encode("latin-1"), b"\xef\xbb\xbfbom"):
            r = run("read", self.file("x", data))
            self.assertEqual(r.returncode, 2, data)
            self.assertIn(b"Can't open", r.stderr)

    def test_crlf_round_trip(self):
        path = self.file("w.csv", b"a,b\r\n1,2\r\n")
        out = json.loads(run("read", path).stdout)
        self.assertEqual(out["text"], "a,b\n1,2\n")
        self.assertTrue(out["crlf"])
        r = run("write", path, "--expect", out["md5"], "--crlf", stdin=b"a,b\n1,3\n")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(open(path, "rb").read(), b"a,b\r\n1,3\r\n")

    def test_write_through_a_link_keeps_the_link_and_mode(self):
        target = self.file("script.sh", b"echo 1\n")
        os.chmod(target, 0o755)
        link = os.path.join(self.dir, "link.sh")
        os.symlink(target, link)
        r = run("write", link, stdin=b"echo 2\n")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.islink(link))
        self.assertEqual(open(target, "rb").read(), b"echo 2\n")
        self.assertEqual(stat.S_IMODE(os.stat(target).st_mode), 0o755)
        self.assertEqual([n for n in os.listdir(self.dir) if n.endswith(".tmp")], [])

    def test_expect_refuses_a_file_changed_meanwhile(self):
        path = self.file("a.txt", b"one\n")
        r = run("write", path, "--expect", textfile.md5("zero\n"), stdin=b"mine\n")
        self.assertEqual(r.returncode, 3)
        self.assertEqual(open(path, "rb").read(), b"one\n")

    def test_md5_refuses_a_cut_stdin(self):
        path = self.file("a.txt", b"one\n")
        r = run("write", path, "--md5", textfile.md5("whole text\n"), stdin=b"whole")
        self.assertEqual(r.returncode, 1)
        self.assertEqual(open(path, "rb").read(), b"one\n")

    def test_new_never_over_a_file(self):
        path = os.path.join(self.dir, "n.txt")
        self.assertEqual(json.loads(run("new", path).stdout)["text"], "")
        os.chmod(path, 0o644)
        with open(path, "w") as f:
            f.write("kept")
        self.assertEqual(run("new", path).returncode, 3)
        self.assertEqual(open(path).read(), "kept")


if __name__ == "__main__":
    unittest.main()
