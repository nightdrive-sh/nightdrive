#!/usr/bin/env python3
"""`files picker on|off|status` (picker-setup): on makes the user's portal folder (the system's .portal files linked,
Files' own, the desktop's choice of backends with FileChooser=nightdrive;gtk over it, the user's own choice kept), the
portal's drop-in and the backend's D-Bus service, and starts the portal again; a portal that doesn't come back with a
FileChooser puts it all back; off takes it away. Runs in a throwaway home with stand-ins for systemctl and gdbus, so the
desktop's portal is never touched."""
import json, os, shutil, subprocess, tempfile, unittest
from pathlib import Path

SETUP = Path(__file__).resolve().parent / "picker-setup"


class PickerSetup(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.data, self.config, self.bin = self.tmp / "data", self.tmp / "config", self.tmp / "bin"
        system = self.tmp / "system"
        (system / "portals").mkdir(parents=True)
        for name in ("gtk", "hyprland"):
            (system / "portals" / f"{name}.portal").write_text(f"[portal]\nDBusName=x.{name}\n")
        (system / "hyprland-portals.conf").write_text("[preferred]\ndefault=hyprland;gtk\n")
        self.bin.mkdir()
        self.log = self.tmp / "systemctl.log"
        self.fake("systemctl", f'echo "$*" >> {self.log}; [ "$3" = MainPID ] && echo 0; true')
        self.hypr = self.tmp / "hyprctl.log"
        self.fake("hyprctl", f'echo "$*" >> {self.hypr}')
        self.chooser(True)
        self.env = dict(os.environ, HOME=str(self.tmp), XDG_DATA_HOME=str(self.data), XDG_CONFIG_HOME=str(self.config),
                        PATH=f"{self.bin}:{os.environ['PATH']}", PICKER_SYSTEM_PORTALS=str(system),
                        HYPRLAND_INSTANCE_SIGNATURE="test")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def fake(self, name, body):
        f = self.bin / name
        f.write_text("#!/bin/bash\n" + body + "\n")
        f.chmod(0o755)

    def chooser(self, offered):
        """gdbus as the portal would answer: with a FileChooser, or without one (a portal that came back broken)"""
        self.fake("gdbus", "echo 'interface org.freedesktop.portal.FileChooser {'" if offered else "exit 1")

    def run_setup(self, *args, ok=True):
        p = subprocess.run([str(SETUP), *args], env=self.env, capture_output=True, text=True, timeout=30)
        if ok:
            self.assertEqual(p.returncode, 0, p.stderr)
        return p

    def test_on_and_off(self):
        self.run_setup("on")
        portals = self.data / "nightdrive" / "portals"
        self.assertTrue((portals / "gtk.portal").is_symlink())
        self.assertIn("FileChooser", (portals / "nightdrive.portal").read_text())
        conf = (portals / "hyprland-portals.conf").read_text()
        self.assertEqual(conf, "[preferred]\norg.freedesktop.impl.portal.FileChooser=nightdrive;gtk\ndefault=hyprland;gtk\n")
        dropin = self.config / "systemd/user/xdg-desktop-portal.service.d/nightdrive-picker.conf"
        self.assertIn(f"XDG_DESKTOP_PORTAL_DIR={portals}", dropin.read_text())
        service = self.data / "dbus-1/services/org.freedesktop.impl.portal.desktop.nightdrive.service"
        self.assertIn(str(SETUP.parent / "portal.py"), service.read_text())
        self.assertIn("--user restart xdg-desktop-portal.service", self.log.read_text())
        self.assertEqual(json.loads(self.run_setup("status", "--json").stdout)["picker"], "on")
        self.assertIn('hl.env("GDK_DEBUG", "portals") hl.env("GTK_USE_PORTAL", "1")', self.hypr.read_text())

        self.log.unlink()
        self.run_setup("off")
        self.assertFalse(portals.exists() or dropin.exists() or service.exists())
        self.assertIn("restart", self.log.read_text())
        self.assertIn('hl.env("GDK_DEBUG", "")', self.hypr.read_text().splitlines()[-1])
        self.assertIn("Off", self.run_setup("status").stdout)

    def test_off_when_off_leaves_the_portal_be(self):
        self.run_setup("off")
        self.assertFalse(self.log.exists())

    def test_the_users_own_choice_is_kept(self):
        own = self.config / "xdg-desktop-portal"
        own.mkdir(parents=True)
        (own / "hyprland-portals.conf").write_text(
            "[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.FileChooser=kde\n")
        self.run_setup("on")
        conf = (self.data / "nightdrive/portals/hyprland-portals.conf").read_text()
        self.assertEqual(conf, "[preferred]\norg.freedesktop.impl.portal.FileChooser=nightdrive;gtk\ndefault=gtk\n")

    def test_a_portal_that_doesnt_come_back_is_put_back(self):
        self.chooser(False)
        p = self.run_setup("on", ok=False)
        self.assertEqual(p.returncode, 1)
        self.assertIn("put back", p.stderr)
        self.assertFalse((self.data / "nightdrive/portals").exists())
        self.assertFalse((self.config / "systemd/user/xdg-desktop-portal.service.d/nightdrive-picker.conf").exists())
        self.assertEqual(self.log.read_text().count("restart"), 2)


if __name__ == "__main__":
    unittest.main()
