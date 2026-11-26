#!/usr/bin/env python3
"""sync-apps' renaming (#3317): Nautilus is "Files (Nautilus)" and out of the Apps list while Nightdrive's Files is
installed, pinned with ⌃Enter it stays listed, and without Files it is Nautilus's own entry again. Runs the script as the
desktop does, in a throwaway home with its own system folder (SYNC_APPS_SYS_DIRS)."""
import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "sync-apps")
NAUTILUS = """[Desktop Entry]
Name[fi]=Tiedostot
Name=Files
Keywords=folder;manager;nautilus;
Exec=nautilus --new-window %U
Icon=org.gnome.Nautilus
Type=Application
MimeType=inode/directory;

[Desktop Action new-window]
Name=New Window
Exec=nautilus --new-window
"""


class SyncAppsRename(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.sys = os.path.join(self.home, "sys")
        self.apps = os.path.join(self.home, ".local/share/applications")
        os.makedirs(self.sys)
        os.makedirs(self.apps)
        with open(os.path.join(self.sys, "org.gnome.Nautilus.desktop"), "w") as f:
            f.write(NAUTILUS)
        self.override = os.path.join(self.apps, "org.gnome.Nautilus.desktop")
        self.ours = os.path.join(self.apps, "nightdrive-files.desktop")

    def tearDown(self):
        self.tmp.cleanup()

    def run_it(self):
        env = {"HOME": self.home, "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "SYNC_APPS_SYS_DIRS": self.sys}
        subprocess.run([sys.executable, "-I", SCRIPT], env=env, check=True, capture_output=True)

    def keys(self):
        with open(self.override) as f:
            text = f.read().split("\n[Desktop Action")[0]
        return text, dict(l.split("=", 1) for l in text.splitlines() if "=" in l and not l.startswith("#"))

    def files_installed(self):
        with open(self.ours, "w") as f:
            f.write("[Desktop Entry]\nName=Files\nExec=files %U\nType=Application\n")

    def test_without_files_nautilus_is_itself(self):
        # Nautilus is on apps-allow.txt: no override at all, its own entry shows
        self.run_it()
        self.assertFalse(os.path.exists(self.override))

    def test_with_files_renamed_and_searchable_only(self):
        self.files_installed()
        self.run_it()
        text, k = self.keys()
        self.assertEqual(k["Name"], "Files (Nautilus)")
        self.assertNotIn("Name[fi]", text, "a localized name would bring the old one back")
        self.assertEqual(k.get("NoDisplay"), "true")
        self.assertEqual(k.get("X-Nightdrive-Renamed"), "true")
        with open(self.override) as f:
            self.assertIn("Name=New Window", f.read(), "the actions keep their own names")

    def test_pinned_stays_listed_under_the_new_name(self):
        self.files_installed()
        state = os.path.join(self.home, ".local/state/nightdrive")
        os.makedirs(state)
        with open(os.path.join(state, "apps.json"), "w") as f:
            json.dump({"shown": ["org.gnome.Nautilus.desktop"]}, f)
        self.run_it()
        _, k = self.keys()
        self.assertEqual(k["Name"], "Files (Nautilus)")
        self.assertNotIn("NoDisplay", k)

    def test_files_removed_gives_the_name_back(self):
        self.files_installed()
        self.run_it()
        os.remove(self.ours)
        self.run_it()
        self.assertFalse(os.path.exists(self.override))

    def test_users_own_file_wins(self):
        self.files_installed()
        with open(self.override, "w") as f:
            f.write("[Desktop Entry]\nName=Files\nExec=my-nautilus\nType=Application\n")
        self.run_it()
        _, k = self.keys()
        self.assertEqual((k["Name"], k["Exec"]), ("Files", "my-nautilus"))


if __name__ == "__main__":
    unittest.main()
