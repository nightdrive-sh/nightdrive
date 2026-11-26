#!/usr/bin/env python3
"""The disks in Files' sidebar from UDisks2: `python3 plugins/files/lib/udisks_test.py`. A stick mounted under
/run/media is a row with its folder that can be unmounted, one not mounted a row to mount, the system's own partitions
(/, /boot, the EFI one) aren't rows, a disk without a label is named by its size; without UDisks2 there are none.
And a folder in a mounted network drive isn't looked at (#3707): finding it would make the drive connect."""
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import places  # noqa: E402
import udisks  # noqa: E402

B = "/org/freedesktop/UDisks2/block_devices/"
D = "/org/freedesktop/UDisks2/drives/"


def block(dev, drive, label="", system=False, ignore=False, usage="filesystem", size=0):
    return {"Device": list(dev.encode()) + [0], "PreferredDevice": dev.encode() + b"\0", "IdUsage": usage,
            "IdLabel": label, "HintName": "", "HintSystem": system, "HintIgnore": ignore, "Size": size,
            "Drive": D + drive}


def fs(*points):
    return {"MountPoints": [p.encode() + b"\0" for p in points]}


OBJECTS = {
    D + "ssd": {udisks.DRIVE: {"Removable": False, "Ejectable": False, "ConnectionBus": ""}},
    D + "stick": {udisks.DRIVE: {"Removable": True, "Ejectable": True, "ConnectionBus": "usb", "CanPowerOff": True}},
    B + "nvme0n1p4": {udisks.BLOCK: block("/dev/nvme0n1p4", "ssd", "EFI", system=True, ignore=True),
                      udisks.FS: fs("/boot/efi")},
    B + "nvme0n1p6": {udisks.BLOCK: block("/dev/nvme0n1p6", "ssd", "fedora", system=True), udisks.FS: fs("/home", "/")},
    B + "nvme0n1p7": {udisks.BLOCK: block("/dev/nvme0n1p7", "ssd", system=True), udisks.FS: fs()},
    B + "nvme0n1": {udisks.BLOCK: block("/dev/nvme0n1", "ssd", system=True, usage="")},
    B + "sda1": {udisks.BLOCK: block("/dev/sda1", "stick", "STICK"), udisks.FS: fs("/run/media/me/STICK")},
    B + "sda2": {udisks.BLOCK: block("/dev/sda2", "stick", size=1_500_000_000), udisks.FS: fs()},
    B + "sda3": {udisks.BLOCK: block("/dev/sda3", "stick", usage="crypto")},
}


class Disks(unittest.TestCase):
    def test_rows(self):
        self.assertEqual([{k: v for k, v in r.items() if k != "object"} for r in udisks.rows(OBJECTS, "/home/me")], [
            {"name": "STICK", "path": "/run/media/me/STICK", "device": "/dev/sda1", "glyph": "usb", "unmount": True},
            {"name": "1.5 GB Volume", "path": "", "device": "/dev/sda2", "glyph": "usb", "unmount": False}])

    def test_without_udisks(self):
        with mock.patch.object(udisks, "_bus", lambda: None):
            self.assertEqual(udisks.devices(), [])

    def test_unmount_powers_the_stick_off(self):
        calls = []
        with mock.patch.object(udisks, "objects", lambda: OBJECTS), \
             mock.patch.object(udisks, "_call", lambda obj, iface, method: calls.append((obj, method)) or ("/x",)):
            self.assertEqual(udisks.unmount("/run/media/me/STICK"), {"unmounted": "/run/media/me/STICK"})
            self.assertEqual(udisks.mount("/dev/sda2"), {"path": "/x"})
            with self.assertRaises(places.trash.Refused):
                udisks.unmount("/home")
        self.assertEqual(calls, [(B + "sda1", "Unmount"), (D + "stick", "PowerOff"), (B + "sda2", "Mount")])


class NetworkFolders(unittest.TestCase):
    def test_a_folder_in_a_network_drive_isnt_looked_at(self):
        with tempfile.TemporaryDirectory() as tmp:
            drive = os.path.join(tmp, "Storage/Photos")
            with mock.patch.object(Path, "is_dir", side_effect=AssertionError("looked at")):
                self.assertFalse(places.missing(drive + "/2024", {drive: "Photos"}))
                self.assertFalse(places.missing(drive, {drive: "Photos"}))
            self.assertTrue(places.missing(os.path.join(tmp, "gone"), {drive: "Photos"}))
            self.assertFalse(places.missing(tmp, {drive: "Photos"}))


if __name__ == "__main__":
    unittest.main()
