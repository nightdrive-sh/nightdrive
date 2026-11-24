#!/usr/bin/env python3
"""Network Drives' list, command and state: `python3 plugins/netdrive/lib/drives_test.py`. Adding refuses what can't be
mounted safely (a drive inside another, outside home, both or neither kind), the mount command keeps every timeout
and the circuit breaker, an ssh drive hides its keys and a read-only one says so; the state comes from systemd and
/proc/self/mounts (never the folder), and the top bar speaks only of trouble. No rclone, FUSE or network needed."""
import json
import os
import csv
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import drives  # noqa: E402
import mountcmd  # noqa: E402
import state  # noqa: E402


class Home(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve()
        self.env = mock.patch.dict(os.environ, {"HOME": str(self.home), "XDG_RUNTIME_DIR": str(self.home / "run")})
        self.env.start()
        for k in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            os.environ.pop(k, None)

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()


class Drives(Home):
    def test_add_and_remove(self):
        self.assertEqual(drives.load(), [])
        drives.init()
        self.assertEqual(json.loads(drives.config_file().read_text()), {"drives": []})
        d = drives.add("Files", ssh="storage-files")
        self.assertEqual(d, {"name": "Files", "ssh": "storage-files", "path": "~/Storage/Files"})
        drives.add("Photos", ssh="storage-photos", read_only=True)
        drives.add("Jotta", remote="jotta:Sync", path="~/Jotta drive")
        self.assertEqual([d["name"] for d in drives.load()], ["Files", "Photos", "Jotta"])
        self.assertEqual(drives.mountpoint(drives.get("Jotta")), str(self.home / "Jotta drive"))
        self.assertTrue(drives.get("Photos")["read_only"])
        drives.remove("Photos")
        self.assertEqual([d["name"] for d in drives.load()], ["Files", "Jotta"])

    def test_refused(self):
        drives.add("Files", ssh="storage-files")
        cases = [dict(name="bad name", ssh="h"), dict(name="X"), dict(name="X", ssh="h", remote="r:"),
                 dict(name="X", remote="no-colon"), dict(name="X", ssh="h; rm -rf ~"),
                 dict(name="Files", ssh="h"),                                   # taken
                 dict(name="X", ssh="h", path="/mnt/x"),                        # outside home
                 dict(name="X", ssh="h", path="~/Storage/Files/inner"),         # inside another
                 dict(name="X", ssh="h", path="~/Storage")]                     # holding another
        for c in cases:
            with self.subTest(c), self.assertRaises(drives.Refused):
                drives.add(**c)
        with self.assertRaises(drives.Refused):
            drives.remove("Nope")

    def test_broken_file_is_not_overwritten(self):
        drives.config_file().parent.mkdir(parents=True)
        drives.config_file().write_text("{not json")
        with self.assertRaises(drives.Refused):
            drives.add("Files", ssh="h")
        self.assertEqual(drives.config_file().read_text(), "{not json")


class Command(Home):
    def test_ssh_drive(self):
        d = {"name": "Files", "ssh": "storage-files", "path": "~/Storage/Files"}
        cmd = mountcmd.argv(d)
        self.assertEqual(cmd[:4], ["rclone", "mount", ":sftp:", str(self.home / "Storage/Files")])
        flag = lambda name: cmd[cmd.index(name) + 1]  # noqa: E731
        self.assertEqual(flag("--vfs-cache-mode"), "full")
        self.assertEqual(flag("--low-level-retries"), "1")
        self.assertEqual(flag("--contimeout"), f"{mountcmd.CONNECT_TIMEOUT}s")
        self.assertEqual(flag("--disable"), "About")                  # df never asks the server
        self.assertEqual(flag("--dir-cache-time"), mountcmd.DIR_CACHE)
        self.assertEqual(flag("--exclude"), "/.ssh/**")
        self.assertEqual(flag("--cache-dir"), str(self.home / ".cache/netdrive/Files"))
        self.assertEqual(flag("--rc-addr"), "unix://" + str(self.home / "run/netdrive/Files.sock"))
        self.assertNotIn("--read-only", cmd)
        ssh = next(csv.reader([flag("--sftp-ssh")], delimiter=" "))
        self.assertEqual(ssh[:2], [mountcmd.BREAKER, str(self.home / "run/netdrive/Files.down")])
        self.assertEqual(ssh[2], "ssh")
        self.assertEqual(ssh[-1], "storage-files")
        for o in ("BatchMode=yes", f"ConnectTimeout={mountcmd.CONNECT_TIMEOUT}",
                  f"ServerAliveInterval={mountcmd.ALIVE_INTERVAL}", f"ServerAliveCountMax={mountcmd.ALIVE_COUNT}"):
            self.assertIn(o, ssh)
        self.assertTrue(os.access(mountcmd.BREAKER, os.X_OK))

    def test_other_remote_read_only(self):
        d = {"name": "Jotta", "remote": "jotta:Sync", "read_only": True}
        cmd = mountcmd.argv(d)
        self.assertEqual(cmd[2:4], ["jotta:Sync", str(self.home / "Storage/Jotta")])
        self.assertIn("--read-only", cmd)
        self.assertNotIn("--sftp-ssh", cmd)
        self.assertNotIn("--exclude", cmd)

    def test_space_list(self):
        """rclone reads --sftp-ssh like a CSV line split on spaces: a home with a space in it must survive"""
        args = ["/home/my name/x", 'say "hi"', "-o", "HostKeyAlias=[h]:23", ""]
        self.assertEqual(next(csv.reader([mountcmd.space_list(args)], delimiter=" ")), args)

    def test_ssh_root(self):
        self.assertEqual(mountcmd.remote({"name": "X", "ssh": "h", "root": "photos"}), ":sftp:photos")

    def test_wait_for_backs_off(self):
        pauses, answers = [], iter([False, False, False, False, False, False, True])
        with mock.patch.object(mountcmd, "reachable", lambda t: next(answers)):
            mountcmd.wait_for(("h", 23), sleep=pauses.append)
        self.assertEqual(pauses, [2, 4, 8, 16, 32, mountcmd.WAIT_MAX])


class State(Home):
    MOUNTS = ("sysfs /sys sysfs rw 0 0\n"
              ":sftp: {home}/Storage/Files fuse.rclone rw,nosuid,nodev 0 0\n"
              "netdrive:Photos {home}/Storage/My\\040Photos fuse.rclone ro 0 0\n")

    def test_mounts(self):
        m = state.mounts(self.MOUNTS.format(home=self.home))
        self.assertEqual(m[f"{self.home}/Storage/Files"], "fuse.rclone")
        self.assertEqual(m[f"{self.home}/Storage/My Photos"], "fuse.rclone")

    def rows(self, units, uploads=None):
        ds = [{"name": "Files", "ssh": "a"}, {"name": "Photos", "ssh": "b", "path": "~/Storage/My Photos",
                                                "read_only": True}]
        m = state.mounts(self.MOUNTS.format(home=self.home))
        with mock.patch.object(state, "rc", lambda d, method, params=None: uploads):
            return [state.describe(d, units.get(d["name"], {}), m) for d in ds]

    def test_all_well(self):
        on = {"ActiveState": "active", "UnitFileState": "enabled"}
        rows = self.rows({"Files": on, "Photos": on})
        self.assertEqual([r["state"] for r in rows], ["mounted", "mounted"])
        self.assertIsNone(state.summary(rows))
        self.assertEqual(state.line(rows), "Files mounted; Photos mounted.")

    def test_uploads_and_trouble(self):
        on = {"ActiveState": "active", "UnitFileState": "enabled"}
        rows = self.rows({"Files": on, "Photos": on}, uploads={"diskCache": {"uploadsQueued": 2,
                                                                             "uploadsInProgress": 1}})
        self.assertEqual(state.summary(rows), ("cloud-upload", "6", "pulse"))
        waiting = {"ActiveState": "activating", "UnitFileState": "enabled", "StatusText": "Waiting for h"}
        rows = self.rows({"Files": waiting, "Photos": on})
        self.assertEqual(rows[0]["state"], "connecting")
        self.assertEqual(rows[0]["detail"], "Waiting for h")
        self.assertEqual(state.summary(rows), ("cloud-off", "", "warning"))
        failed = {"ActiveState": "failed", "Result": "exit-code", "UnitFileState": "enabled"}
        self.assertEqual(state.summary(self.rows({"Files": failed, "Photos": on})), ("cloud-off", "", "critical"))

    def test_turned_off_is_fine(self):
        on = {"ActiveState": "active", "UnitFileState": "enabled"}
        off = {"ActiveState": "inactive", "UnitFileState": "disabled"}
        mounts = state.mounts(self.MOUNTS.format(home=self.home))
        rows = [state.describe({"name": "Other", "ssh": "c"}, off, mounts),
                *self.rows({"Files": on, "Photos": on})]
        self.assertEqual(rows[0]["state"], "off")
        self.assertIsNone(state.summary(rows))
        # Mounted with its service gone: a leftover mount
        self.assertEqual(self.rows({"Files": off, "Photos": on})[0]["state"], "stale")

    def test_no_drives(self):
        self.assertIn("netdrive add", state.line([]))


if __name__ == "__main__":
    unittest.main()
