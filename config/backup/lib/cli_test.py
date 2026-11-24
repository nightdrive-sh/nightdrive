#!/usr/bin/env python3
"""Tests for `nightdrive backup` (cli.py, conf.py, restic.py): settings, when a run is due or stale, the repository out
of reach, and a whole setup, backup and restore against a local repository when restic is installed."""
import contextlib
import io
import os
import shutil
import socket
import sys
import tempfile
import time
import unittest

# A home of its own before conf.py reads it, so a run by hand never touches the person's real backup
TMP = tempfile.mkdtemp(prefix="backup-test-")
os.environ["HOME"] = os.path.join(TMP, "home")
for var in ("XDG_CONFIG_HOME", "XDG_STATE_HOME"):
    os.environ.pop(var, None)
os.environ["NIGHTDRIVE_BACKUP_NO_TIMER"] = "1"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cli  # noqa: E402
import conf  # noqa: E402
import restic  # noqa: E402

HOME = os.environ["HOME"]


def stamp(hours_ago):
    return time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(time.time() - hours_ago * 3600))


def quiet(fn, *args):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = fn(*args)
    return code, out.getvalue() + err.getvalue()


class Settings(unittest.TestCase):
    def test_paths_and_keep(self):
        cfg = conf.parse("# c\nrepository = sftp:box:/m\npath = ~\npath = /srv/data\nkeep-daily = 3\n")
        self.assertEqual(cfg["path"], ["~", "/srv/data"])
        self.assertEqual(cfg["keep-daily"], 3)

    def test_unknown_key_is_an_error(self):
        # A typo such as "paths" would otherwise leave a folder out of every backup without a word
        with self.assertRaises(ValueError):
            conf.parse("repository = x\npaths = ~/Work\n")
        with self.assertRaises(ValueError):
            conf.parse("keep-daily = many\n")

    def test_defaults(self):
        path = os.path.join(TMP, "defaults.conf")
        with open(path, "w") as f:
            f.write("repository = sftp:storage-backup:/my machine\n")
        cfg = conf.load(path)
        self.assertEqual(cfg["path"], [HOME])
        self.assertEqual(cfg["keep-yearly"], conf.KEEP["keep-yearly"])
        # The repository quoted for the shell restic runs the command in
        self.assertEqual(cfg["password-cmd"],
                         "secret-tool lookup service nightdrive-backup repository 'sftp:storage-backup:/my machine'")

    def test_render_parses_back(self):
        cfg = conf.parse(conf.render("/mnt/disk/repo", ["~", "/srv"], "op read op://x"))
        self.assertEqual((cfg["repository"], cfg["password-cmd"], cfg["path"]),
                         ("/mnt/disk/repo", "op read op://x", ["~", "/srv"]))


class Commands(unittest.TestCase):
    def test_every_help_prints(self):
        # A bare % in a help ("default 5%") is a format error to argparse: Python 3.14 raises it as the parser is built,
        # so every command failed, and only Whole (skipped without restic, as in CI) went through main()
        for cmd in ([], ["setup"], ["run"], ["status"], ["snapshots"], ["check"], ["restore"], ["timer"]):
            with self.subTest(cmd=cmd), self.assertRaises(SystemExit) as e:
                quiet(cli.main, cmd + ["--help"])
            self.assertEqual(e.exception.code, 0)


class Timing(unittest.TestCase):
    def test_due(self):
        self.assertTrue(cli.due({}))
        self.assertFalse(cli.due({"last_ok": stamp(2)}))
        self.assertTrue(cli.due({"last_ok": stamp(cli.DUE_HOURS + 1)}))

    def test_stale_counts_from_setup(self):
        self.assertFalse(cli.stale({"setup": stamp(1)}))
        self.assertTrue(cli.stale({"setup": stamp(cli.STALE_DAYS * 24 + 1)}))
        self.assertFalse(cli.stale({"setup": stamp(500), "last_ok": stamp(1)}))


class Reachable(unittest.TestCase):
    def test_local_disk_not_mounted(self):
        with self.assertRaises(restic.Offline):
            restic.reachable({"repository": os.path.join(TMP, "no-disk", "repo")})
        restic.reachable({"repository": os.path.join(TMP, "repo-here")})

    def test_host_out_of_reach(self):
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()                          # a port nothing listens on: refused at once
        with self.assertRaises(restic.Offline):
            restic.reachable({"repository": "sftp://u@127.0.0.1:%d//backup" % port}, timeout=2)

    def test_rclone_left_to_restic(self):
        restic.reachable({"repository": "rclone:jotta:backup"})


@unittest.skipUnless(shutil.which("restic"), "restic isn't installed")
class Whole(unittest.TestCase):
    def setUp(self):
        shutil.rmtree(HOME, ignore_errors=True)
        os.makedirs(os.path.join(HOME, "docs"))
        os.makedirs(os.path.join(HOME, ".cache", "app"))
        with open(os.path.join(HOME, "docs", "a.txt"), "w") as f:
            f.write("hello")
        with open(os.path.join(HOME, ".cache", "app", "junk"), "w") as f:
            f.write("junk")
        self.repo = tempfile.mkdtemp(dir=TMP) + "/repo"

    def setup(self, *extra):
        return quiet(cli.main, ["setup", self.repo, "--password-cmd", "echo test-password"] + list(extra))

    def test_backup_and_restore(self):
        code, out = self.setup()
        self.assertEqual(code, 0, out)
        code, out = quiet(cli.main, ["run"])
        self.assertEqual(code, 0, out)
        st = conf.read_status()
        self.assertEqual(st["state"], "ok")
        self.assertTrue(st["last_prune"] and st["last_check"])
        # The timer's run the same hour does nothing
        self.assertEqual(cli.run_backup(only_if_due=True).get("skipped"), "not due")
        target = os.path.join(TMP, "restored-%d" % os.getpid())
        code, out = quiet(cli.main, ["restore", "latest", target])
        self.assertEqual(code, 0, out)
        root = target + HOME
        with open(os.path.join(root, "docs", "a.txt")) as f:
            self.assertEqual(f.read(), "hello")
        self.assertFalse(os.path.exists(os.path.join(root, ".cache")), "the default excludes leave caches out")
        # Restoring over files is refused: into an empty folder only
        self.assertEqual(quiet(cli.main, ["restore", "latest", target])[0], 1)

    def test_setup_again_uses_the_repository(self):
        self.assertEqual(self.setup()[0], 0)
        code, out = self.setup()
        self.assertEqual(code, 0, out)
        self.assertIn("Using the repository", out)

    def test_wrong_password_for_an_existing_one(self):
        self.assertEqual(self.setup()[0], 0)
        code, out = quiet(cli.main, ["setup", self.repo, "--password-cmd", "echo wrong", "--existing"])
        self.assertEqual(code, 1, out)

    def test_out_of_reach_is_quiet_until_stale(self):
        self.assertEqual(self.setup()[0], 0)
        shutil.rmtree(os.path.dirname(self.repo))      # the disk holding it is gone
        code, out = quiet(cli.main, ["run", "--quiet"])
        self.assertEqual((code, out), (0, ""))
        self.assertEqual(conf.read_status()["state"], "offline")
        st = conf.read_status()
        st["setup"] = stamp(cli.STALE_DAYS * 24 + 1)
        conf.write_status(st)
        code, out = quiet(cli.main, ["run", "--quiet"])
        self.assertEqual(code, 1)
        self.assertIn("No backup in", out)


if __name__ == "__main__":
    try:
        unittest.main()
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
