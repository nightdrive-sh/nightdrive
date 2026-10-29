#!/usr/bin/env python3
"""The folders Claude can use (#1849): `python3 config/mcp/folders_test.py`. Runs `nightdrive files` (and wallpaper
set's refusal) in a home of its own, with Finnish folder names (Downloads is ~/Lataukset), as Claude's tools run it
(NIGHTDRIVE_MCP and the options run.environment gives), and access.py's levels and list against a file of its own."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent / "hypr/scripts"
sys.path.insert(0, str(HERE))

import access  # noqa: E402


class Files(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve()
        for d in ("Lataukset/sub", "Asiakirjat", "Kuvat", "Työpöytä", "Projects", ".ssh"):
            (self.home / d).mkdir(parents=True)
        (self.home / ".config").mkdir()
        (self.home / ".config/user-dirs.dirs").write_text(
            'XDG_DOWNLOAD_DIR="$HOME/Lataukset"\nXDG_DOCUMENTS_DIR="$HOME/Asiakirjat"\n'
            'XDG_PICTURES_DIR="$HOME/Kuvat"\nXDG_DESKTOP_DIR="$HOME/Työpöytä"\n')
        for f in ("Lataukset/a.txt", "Lataukset/sub/b.txt", "Projects/secret.txt", ".ssh/id"):
            (self.home / f).write_text("x")
        (self.home / "Lataukset/out").symlink_to(self.home / "Projects/secret.txt")      # a link out
        (self.home / "Projects/in").symlink_to(self.home / "Lataukset/a.txt")            # a link in
        (self.home / "Lataukset/dir").mkdir()
        (self.home / "Lataukset/dir/ok.txt").write_text("x")

    def tearDown(self):
        self.tmp.cleanup()

    def run_files(self, *args, folders=None, own=True, script="files"):
        """`files ARGS` as the user (folders None) or as Claude with this list, as the tool's own area's choice
        (own) or from options_from (Ferry's, the wallpaper's); (exit status, stdout, stderr)."""
        env = {k: v for k, v in os.environ.items() if not k.startswith(("XDG_", "NIGHTDRIVE_MCP"))}
        env["HOME"] = str(self.home)
        if folders is not None:
            env["NIGHTDRIVE_MCP"] = "1"
            chosen = {"folders": folders} if folders != "missing" else {}
            env["NIGHTDRIVE_MCP_OPTIONS"] = json.dumps(chosen if own else {"secrets": False})
            env["NIGHTDRIVE_MCP_OPTIONS_FROM"] = json.dumps({} if own else {"apps-files": chosen})
        cmd = [sys.executable, "-I", str(SCRIPTS / script)] if script == "files" else [str(SCRIPTS / script)]
        p = subprocess.run(cmd + list(args), env=env, capture_output=True, text=True, timeout=30)
        return p.returncode, p.stdout, p.stderr

    def path(self, rel):
        return str(self.home / rel)

    def assert_refused(self, result, why="outside"):
        status, _, err = result
        self.assertNotEqual(status, 0)
        self.assertIn(why, err)

    NORMAL = ["Downloads", "Documents", "Pictures", "Desktop"]

    def test_your_own_use_has_no_folder_limit(self):
        status, out, _ = self.run_files("check", self.path("Projects/secret.txt"))
        self.assertEqual((status, out.strip()), (0, self.path("Projects/secret.txt")))

    def test_allowed_by_localized_name(self):
        for own in (True, False):
            status, out, err = self.run_files("check", "--json", self.path("Lataukset/a.txt"), folders=self.NORMAL,
                                              own=own)
            self.assertEqual(status, 0, err)
            self.assertEqual(json.loads(out)["files"], [self.path("Lataukset/a.txt")])

    def test_outside_refused_with_where_to_change(self):
        status, _, err = self.run_files("check", self.path("Projects/secret.txt"), folders=self.NORMAL)
        self.assertNotEqual(status, 0)
        self.assertIn("outside the folders Claude may use (~/Lataukset, ~/Asiakirjat, ~/Kuvat, ~/Työpöytä)", err)
        self.assertIn("Settings › Claude › Access › Apps and files", err)

    def test_outside_refused_whether_it_exists_or_not(self):
        for rel in ("Projects/nope.txt", "Projects/no/such/folder.txt", "Projects/secret.txt"):
            self.assert_refused(self.run_files("open", self.path(rel), folders=self.NORMAL))

    def test_link_out_of_an_allowed_folder(self):
        self.assert_refused(self.run_files("check", self.path("Lataukset/out"), folders=self.NORMAL))
        self.assert_refused(self.run_files("open", self.path("Lataukset/out"), folders=self.NORMAL))

    def test_link_into_an_allowed_folder(self):
        self.assert_refused(self.run_files("check", self.path("Projects/in"), folders=self.NORMAL))
        self.assert_refused(self.run_files("open", self.path("Projects/in"), folders=self.NORMAL))

    def test_link_out_inside_a_folder_sent(self):
        (self.home / "Lataukset/dir/out").symlink_to(self.home / "Projects/secret.txt")
        self.assert_refused(self.run_files("check", self.path("Lataukset/dir"), folders=self.NORMAL))
        (self.home / "Lataukset/dir/out").unlink()
        self.assertEqual(self.run_files("check", self.path("Lataukset/dir"), folders=self.NORMAL)[0], 0)

    def test_allowed_folder_by_a_link_in_the_list(self):
        """An entry that is a link counts where it leads: ~/Projects/in-dir → ~/Lataukset/sub."""
        (self.home / "Projects/in-dir").symlink_to(self.home / "Lataukset/sub")
        status, out, err = self.run_files("check", self.path("Lataukset/sub/b.txt"), folders=["~/Projects/in-dir"])
        self.assertEqual(status, 0, err)
        self.assert_refused(self.run_files("check", self.path("Lataukset/a.txt"), folders=["~/Projects/in-dir"]))

    def test_hidden_never_even_with_whole_home(self):
        self.assertEqual(self.run_files("check", self.path("Projects/secret.txt"), folders=["~"])[0], 0)
        self.assert_refused(self.run_files("check", self.path(".ssh/id"), folders=["~"]), "hidden")

    def test_none_without_the_list(self):
        for folders in ([], "missing"):
            self.assert_refused(self.run_files("check", self.path("Lataukset/a.txt"), folders=folders),
                                "Claude may use none")
        self.assert_refused(self.run_files("check", self.path("Lataukset/a.txt"), folders="missing", own=False),
                            "Claude may use none")

    def test_trash_inside_but_not_the_folder_itself(self):
        status, _, err = self.run_files("trash", "--check", self.path("Projects/secret.txt"), folders=["~/Projects"])
        self.assertEqual(status, 0, err)
        self.assert_refused(self.run_files("trash", "--check", self.path("Projects"), folders=["~/Projects"]))
        self.assert_refused(self.run_files("trash", "--check", self.path("Projects/secret.txt"), folders=self.NORMAL))

    def test_recent_only_allowed(self):
        def names(folders):
            status, out, err = self.run_files("recent", "--json", folders=folders)
            self.assertEqual(status, 0, err)
            return sorted(f["name"] for f in json.loads(out)["files"])
        self.assertEqual(names(self.NORMAL), ["a.txt", "b.txt", "ok.txt"])
        self.assertEqual(names(["~/Lataukset/sub"]), ["b.txt"])
        self.assertEqual(names(["~/Projects"]), [])
        self.assertEqual(names([]), [])

    def test_folders_offered(self):
        status, out, err = self.run_files("folders", "--json")
        self.assertEqual(status, 0, err)
        rows = {r["item"]: r["path"] for r in json.loads(out)}
        self.assertEqual(rows["Downloads"], self.path("Lataukset"))
        self.assertEqual(rows["~/Projects"], self.path("Projects"))
        self.assertEqual(rows["~"], str(self.home))
        self.assertNotIn("~/Lataukset", rows)   # offered once, by its name
        self.assertNotIn("~/.ssh", rows)

    def test_hard_link_to_a_key(self):
        """A hard link in Downloads to ~/.ssh/id is the key itself, and resolve() doesn't tell (#1864)."""
        os.link(self.home / ".ssh/id", self.home / "Lataukset/id.txt")
        os.link(self.home / ".ssh/id", self.home / "Lataukset/dir/id.txt")   # in a folder sent
        for folders in (self.NORMAL, ["~"]):
            for args in (("check", self.path("Lataukset/id.txt")), ("check", self.path("Lataukset/dir")),
                         ("open", self.path("Lataukset/id.txt"))):
                with self.subTest(folders=folders, args=args):
                    self.assert_refused(self.run_files(*args, folders=folders), "hard link")
        # Nor through a symbolic link to it, nor as a wallpaper
        (self.home / "Lataukset/sub/to-id").symlink_to(self.home / "Lataukset/id.txt")
        self.assert_refused(self.run_files("check", self.path("Lataukset/sub/to-id"), folders=self.NORMAL),
                            "hard link")
        img = self.home / "Lataukset/x.png"
        os.link(self.home / ".ssh/id", img)
        (self.home / ".local/share/wallpapers").mkdir(parents=True)
        status, _, err = self.run_files("set", str(img), folders=self.NORMAL, own=False, script="wallpaper")
        self.assertNotEqual(status, 0)
        self.assertIn("hard link", err)
        self.assertFalse((self.home / "Kuvat/Wallpapers/x.png").exists())
        # Trashing moves just the one name; your own use isn't limited
        self.assertEqual(self.run_files("trash", "--check", self.path("Lataukset/id.txt"), folders=self.NORMAL)[0], 0)
        self.assertEqual(self.run_files("check", self.path("Lataukset/id.txt"))[0], 0)

    def test_wallpaper_by_content(self):
        """A key renamed .png in Downloads isn't copied into Pictures as a wallpaper (#1866)."""
        (self.home / ".local/share/wallpapers").mkdir(parents=True)
        for name, data in (("key.png", b"-----BEGIN OPENSSH PRIVATE KEY-----\n"), ("x.webp", b"RIFF\0\0\0\0WAVE"),
                           ("empty.jpg", b"")):
            img = self.home / "Lataukset" / name
            img.write_bytes(data)
            status, _, err = self.run_files("set", str(img), folders=self.NORMAL, own=False, script="wallpaper")
            self.assertNotEqual(status, 0)
            self.assertIn("its content isn't jpg, png or webp", err)
            self.assertFalse((self.home / "Kuvat/Wallpapers" / name).exists())

    def test_wallpaper_from_outside_refused(self):
        """Only the refusal: an allowed one would change the real wallpaper."""
        img = self.home / "Projects/x.png"
        img.write_text("x")
        (self.home / ".local/share/wallpapers").mkdir(parents=True)   # the script's own, as link.sh makes it
        status, _, err = self.run_files("set", str(img), folders=self.NORMAL, own=False, script="wallpaper")
        self.assertNotEqual(status, 0)
        self.assertIn("outside the folders Claude may use", err)
        self.assertFalse((self.home / "Kuvat/Wallpapers/x.png").exists())


class Levels(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.file = Path(self.tmp.name) / "claude-access.json"

    def tearDown(self):
        self.tmp.cleanup()

    def folders(self):
        return access.load(self.file).option("apps-files", "folders")

    def test_level_presets(self):
        for level, want in (("strict", []), ("normal", ["Downloads", "Documents", "Pictures", "Desktop"]),
                            ("open", ["~"])):
            access.set_level(level, self.file)
            self.assertEqual(self.folders(), want)
        self.assertNotIn("options", json.loads(self.file.read_text()))

    def test_add_and_remove(self):
        access.set_level("normal", self.file)
        access.set_option("apps-files", "folders", "add", "~/Projects", path=self.file)
        self.assertEqual(self.folders(), ["Downloads", "Documents", "Pictures", "Desktop", "~/Projects"])
        access.set_option("apps-files", "folders", "remove", "Desktop", path=self.file)
        access.set_option("apps-files", "folders", "remove", "~/Projects", path=self.file)
        self.assertEqual(self.folders(), ["Downloads", "Documents", "Pictures"])
        for bad in ("~/.ssh", "/etc", "~/a/../b", "Lataukset"):
            with self.assertRaises(ValueError):
                access.set_option("apps-files", "folders", "add", bad, path=self.file)

    def test_broken_list_is_none(self):
        self.file.write_text(json.dumps({"version": 2, "level": "open",
                                         "options": {"apps-files": {"folders": ["~", "~/.ssh"]}}}))
        self.assertEqual(self.folders(), [])


if __name__ == "__main__":
    unittest.main()
