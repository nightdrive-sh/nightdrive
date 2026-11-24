#!/usr/bin/env python3
"""Network Drives in Files' sidebar: `python3 plugins/files/lib/netdrives_test.py`. A drive is known by its mount's
device (netdrive:NAME), each one the plugin has is a row (a cloud while mounted, one to mount while not), Gio's own row
for it is left out, and mounting or ejecting one runs the plugin's command. Without the command there are none."""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import netdrives  # noqa: E402
import places  # noqa: E402
import trash  # noqa: E402

MOUNTS = ("sysfs /sys sysfs rw 0 0\n"
          "netdrive:Files {home}/Storage/Files fuse.rclone rw,nosuid,nodev 0 0\n"
          "/dev/sdb1 /run/media/me/STICK vfat rw 0 0\n")


class NetDrives(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve()
        self.env = mock.patch.dict(os.environ, {"HOME": str(self.home)})
        self.env.start()
        self.calls = self.home / "calls"
        drives = [{"name": "Files", "path": f"{self.home}/Storage/Files"},
                  {"name": "Photos", "path": f"{self.home}/Storage/Photos"}]
        (self.home / ".local/bin").mkdir(parents=True)
        cmd = self.home / ".local/bin/netdrive"
        cmd.write_text("#!/bin/sh\necho \"$@\" >> '%s'\n[ \"$1\" = list ] && echo '%s'\nexit 0\n"
                       % (self.calls, json.dumps({"drives": drives})))
        cmd.chmod(0o755)

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def test_mounted(self):
        self.assertEqual(netdrives.mounted(MOUNTS.format(home=self.home)), {f"{self.home}/Storage/Files": "Files"})

    def test_rows_and_actions(self):
        text = MOUNTS.format(home=self.home)
        real = netdrives.mounted
        with mock.patch.object(netdrives, "mounted", lambda t=None: real(text)), \
             mock.patch.object(places, "local_devices", lambda: []):
            rows = places.devices()
            self.assertEqual(rows, [
                {"name": "Files", "path": f"{self.home}/Storage/Files", "device": "netdrive:Files", "glyph": "cloud",
                 "unmount": True},
                {"name": "Photos", "path": "", "device": "netdrive:Photos", "glyph": "cloud-off", "unmount": False}])
            self.assertEqual(places.unmount(f"{self.home}/Storage/Files"),
                             {"unmounted": f"{self.home}/Storage/Files", "said": "Files disconnected"})
            self.assertEqual(places.mount("netdrive:Files"), {"path": f"{self.home}/Storage/Files"})
        self.assertEqual(self.calls.read_text().split("\n")[1:3], ["stop Files", "start Files"])

    def test_mount_gives_up(self):
        with mock.patch.object(netdrives, "MOUNT_WAIT", 0.5), \
             mock.patch.object(netdrives, "mounted", lambda t=None: {}), self.assertRaises(trash.Refused):
            netdrives.mount("netdrive:Photos")

    def test_without_the_plugin(self):
        (self.home / ".local/bin/netdrive").unlink()
        self.assertEqual(netdrives.rows(), [])


if __name__ == "__main__":
    unittest.main()
