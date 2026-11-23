#!/usr/bin/env python3
"""Which files a draft takes as attachments (#3389): `python3 plugins/mail/lib/attach_test.py`. Runs in a home of its
own and a stand-in for /tmp, as Claude (NIGHTDRIVE_MCP with the folders Access gives) and as the user's own terminal."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
ROOT = Path(tempfile.mkdtemp()).resolve()
HOME, TMP = ROOT / "home", ROOT / "tmp"
os.environ["HOME"] = str(HOME)   # files_rules reads home as it is imported
sys.path.insert(0, str(HERE))

import attach  # noqa: E402

attach.TMP = TMP


def claude(folders):
    return mock.patch.dict(os.environ, {"NIGHTDRIVE_MCP": "1",
                                        "NIGHTDRIVE_MCP_OPTIONS_FROM": json.dumps({"apps-files": {"folders": folders}})})


def mine():
    return mock.patch.dict(os.environ, {k: "" for k in ("NIGHTDRIVE_MCP", "NIGHTDRIVE_MCP_OPTIONS_FROM")})


class Attach(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for f in ("Downloads/report.pdf", "Downloads/sub/pic.png", "Documents/cv.pdf", ".ssh/id_ed25519",
                  "Downloads/.env"):
            (HOME / f).parent.mkdir(parents=True, exist_ok=True)
            (HOME / f).write_text("x")
        for f in ("shot.png", "claude-1000/s/out.csv", ".hidden/a.txt", "dot/.b.txt"):
            (TMP / f).parent.mkdir(parents=True, exist_ok=True)
            (TMP / f).write_text("y")
        (TMP / "single.png").write_text("z")
        (TMP / "to-key").symlink_to(HOME / ".ssh/id_ed25519")
        (HOME / "Downloads/to-tmp").symlink_to(TMP / "single.png")
        os.link(TMP / "shot.png", TMP / "same.png")

    def refused(self, paths, words):
        with self.assertRaises((LookupError, SystemExit)) as cm:
            attach.files(paths)
        if isinstance(cm.exception, LookupError):
            self.assertIn(words, str(cm.exception))

    def test_files_in_claudes_folders_and_tmp(self):
        with claude(["Downloads"]):
            got = attach.files([str(HOME / "Downloads/report.pdf"), "~/Downloads/sub/pic.png",
                                str(TMP / "claude-1000/s/out.csv"), str(TMP / "single.png")])
        self.assertEqual([Path(p).name for p in got], ["report.pdf", "pic.png", "out.csv", "single.png"])

    def test_outside_claudes_folders(self):
        with claude(["Downloads"]):
            self.refused([str(HOME / "Documents/cv.pdf")], "")
        with claude([]):
            self.refused([str(HOME / "Downloads/report.pdf")], "")

    def test_the_users_own_terminal_isnt_held_to_the_folders(self):
        with mine():
            self.assertEqual(len(attach.files([str(HOME / "Documents/cv.pdf")])), 1)

    def test_hidden(self):
        with claude(["~"]):
            self.refused([str(HOME / ".ssh/id_ed25519")], "")
            self.refused([str(HOME / "Downloads/.env")], "")
            self.refused([str(TMP / ".hidden/a.txt")], "hidden")
            self.refused([str(TMP / "dot/.b.txt")], "hidden")

    def test_a_link_counts_where_it_leads(self):
        with claude(["~"]):
            self.refused([str(TMP / "to-key")], "")   # /tmp → ~/.ssh
            # ~/Downloads → /tmp: the file is the one in /tmp, under /tmp's rules
            self.assertEqual(attach.files([str(HOME / "Downloads/to-tmp")]), [str(TMP / "single.png")])

    def test_hard_link_folder_missing_relative(self):
        self.refused([str(TMP / "same.png")], "hard link")
        self.refused([str(TMP / "claude-1000")], "only files")
        self.refused([str(TMP / "nothing.png")], "doesn't exist")
        self.refused(["shot.png"], "absolute")
        with claude(["Downloads"]):
            self.refused([str(HOME / "Downloads/sub")], "folder")

    def test_how_many_and_how_much(self):
        self.refused([str(TMP / "single.png")] * (attach.FILES_MAX + 1), "At most")
        with mock.patch.object(attach, "TOTAL_MAX", 1):
            self.refused([str(TMP / "single.png"), str(TMP / "claude-1000/s/out.csv")], "at most")
        self.assertEqual(attach.files([]), [])
        self.assertEqual(attach.files(None), [])


if __name__ == "__main__":
    try:
        unittest.main()
    finally:
        import shutil
        shutil.rmtree(ROOT, ignore_errors=True)
