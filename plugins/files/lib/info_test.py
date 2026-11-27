#!/usr/bin/env python3
"""File info (info.py, I in Files): what it says of a file, a folder and a link, that the executable switch sets x
wherever r is and takes every x off, that its undo puts the exact mode back, and that it refuses a folder, a link and
a file of someone else's. Works only on files it wrote in a throwaway folder."""
import os, stat, sys, tempfile, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import info  # noqa: E402
from fsops import Refused  # noqa: E402


def mode(p):
    return stat.S_IMODE(os.lstat(p).st_mode)


class InfoTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.file = self.dir / "run.sh"
        self.file.write_text("#!/bin/sh\necho hi\n")
        os.chmod(self.file, 0o640)

    def tearDown(self):
        self.tmp.cleanup()

    def test_file(self):
        d = info.info(self.file)
        self.assertEqual(d["mode"], "640")
        self.assertEqual(d["text"], "-rw-r-----")
        self.assertEqual(d["perms"]["owner"], {"read": True, "write": True, "run": False})
        self.assertEqual(d["perms"]["group"], {"read": True, "write": False, "run": False})
        self.assertEqual(d["perms"]["others"], {"read": False, "write": False, "run": False})
        self.assertTrue(d["mine"])
        self.assertTrue(d["can_switch"])
        self.assertFalse(d["executable"])
        self.assertFalse(d["dir"])
        self.assertEqual(d["size"], len("#!/bin/sh\necho hi\n"))

    def test_folder_counts_and_has_no_switch(self):
        (self.dir / "sub").mkdir()
        (self.dir / "sub" / "a").write_bytes(b"12345")
        d = info.info(self.dir)
        self.assertTrue(d["dir"])
        self.assertFalse(d["can_switch"])
        self.assertFalse(d["executable"])          # a folder's x is "may go in", not "runs"
        self.assertEqual((d["size"], d["files"], d["complete"]), (len(self.file.read_text()) + 5, 2, True))

    def test_folder_walk_stops_in_time(self):
        for i in range(3):
            (self.dir / f"d{i}").mkdir()
        total, files, complete = info.folder_size(self.dir, limit=-1)
        self.assertFalse(complete)

    def test_link_has_no_switch(self):
        link = self.dir / "link"
        link.symlink_to(self.file)
        d = info.info(link)
        self.assertEqual(d["link"], str(self.file))
        self.assertFalse(d["can_switch"])
        with self.assertRaises(Refused):
            info.set_executable(link, True)
        self.assertEqual(mode(self.file), 0o640)    # not changed through the link

    def test_broken_link(self):
        link = self.dir / "gone"
        link.symlink_to(self.dir / "nothing")
        self.assertEqual(info.info(link)["link"], str(self.dir / "nothing"))

    def test_on_off_and_undo(self):
        d = info.set_executable(self.file, True)
        self.assertEqual(mode(self.file), 0o750)    # x where r is: the owner and group, not others
        self.assertTrue(d["executable"])
        self.assertEqual(d["undo"], ["set-mode", str(self.file), "640"])
        info.set_mode(self.file, "640")
        self.assertEqual(mode(self.file), 0o640)
        os.chmod(self.file, 0o755)
        info.set_executable(self.file, False)
        self.assertEqual(mode(self.file), 0o644)

    def test_unreadable_file_still_runs_for_owner(self):
        os.chmod(self.file, 0o200)
        info.set_executable(self.file, True)
        self.assertEqual(mode(self.file), 0o300)

    def test_refuses_folder_and_bad_mode(self):
        with self.assertRaises(Refused):
            info.set_executable(self.dir, True)
        with self.assertRaises(Refused):
            info.set_mode(self.file, "17777")

    @unittest.skipUnless(os.getuid() != 0 and os.path.exists("/etc/hostname"), "needs a file of root's, run as a user")
    def test_refuses_another_users_file(self):
        self.assertFalse(info.info("/etc/hostname")["can_switch"])
        with self.assertRaises(Refused):
            info.set_executable("/etc/hostname", True)


if __name__ == "__main__":
    unittest.main()
