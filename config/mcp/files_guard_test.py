#!/usr/bin/env python3
"""What Claude's file tools leave alone whatever its folders (#1883): `python3 config/mcp/files_guard_test.py`. With
Open's folders (the whole home), files_trash doesn't reach the mail store, the notes, the projects, any mail folder or
git repository; files_open doesn't open what does something as it opens (a web page, an SVG, a playlist); and neither
`files` nor `wallpaper set` tells whether a hidden file exists, or where a link leads. Runs copies of the scripts in a
home of its own, next to a `windows` stand-in that leaves a mark, so nothing opens on the desktop."""

import gzip
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent / "hypr/scripts"
OPEN = ["~"]   # levels.py: Open's folders


class Guard(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name).resolve()
        self.home, self.bin = root / "home", root / "scripts"
        self.bin.mkdir()
        for name in ("files", "files_rules.py", "files_move.py", "wallpaper"):
            shutil.copy(SCRIPTS / name, self.bin / name)
        self.opened = root / "opened"
        windows = self.bin / "windows"
        windows.write_text(f"#!/bin/sh\necho \"$@\" >> {self.opened}\n")
        windows.chmod(windows.stat().st_mode | stat.S_IXUSR)
        for f in ("Downloads/a.txt", "Mail/acct/INBOX/cur/1:2,S", "Mail/acct/INBOX/new/.keep", "Mail/acct/INBOX/tmp/.k",
                  "Notes/plan.md", "Projects/app/main.c", "code/tool/x.py", "code/tool/.git/HEAD",
                  "Maildata/acct/INBOX/cur/1:2,S", "Maildata/acct/INBOX/new/.k", "Maildata/acct/INBOX/tmp/.k",
                  "Downloads/repo/.git/HEAD", "Downloads/repo/README", ".ssh/id_rsa", ".ssh/real/key"):
            (self.home / f).parent.mkdir(parents=True, exist_ok=True)
            (self.home / f).write_text("x")
        (self.home / "Downloads/to-notes").symlink_to(self.home / "Notes")
        (self.home / "Downloads/page.html").write_text("<html><img src='https://example.com/x.png'></html>")
        (self.home / "Downloads/pic.svg").write_text("<svg xmlns='http://www.w3.org/2000/svg'/>")
        (self.home / "Downloads/notes.txt").write_text("plain text")
        # What passes OPENABLE's image/ and audio/ by its prefix but does something as it opens: an .svgz, playlists
        # whose player fetches their addresses
        (self.home / "Downloads/pic.svgz").write_bytes(gzip.compress(b"<svg xmlns='http://www.w3.org/2000/svg'/>"))
        (self.home / "Downloads/list.m3u").write_text("#EXTM3U\nhttps://example.com/a.mp3\n")
        (self.home / "Downloads/list.pls").write_text("[playlist]\nFile1=https://example.com/a.mp3\n")

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, *args, folders=OPEN, script="files"):
        env = {k: v for k, v in os.environ.items() if not k.startswith(("XDG_", "NIGHTDRIVE_MCP", "NOTES_DIR"))}
        env["HOME"] = str(self.home)
        if folders is not None:
            env["NIGHTDRIVE_MCP"] = "1"
            env["NIGHTDRIVE_MCP_OPTIONS"] = json.dumps({"folders": folders} if script == "files" else {})
            env["NIGHTDRIVE_MCP_OPTIONS_FROM"] = json.dumps({} if script == "files" else {"apps-files": {"folders": folders}})
        cmd = [sys.executable, "-I", str(self.bin / script)] if script == "files" else [str(self.bin / script)]
        p = subprocess.run(cmd + list(args), env=env, capture_output=True, text=True, timeout=30)
        return p.returncode, p.stdout, p.stderr

    def p(self, rel):
        return str(self.home / rel)

    # --- trash ---

    def assert_guarded(self, rel, why):
        status, out, err = self.run_script("trash", "--check", self.p(rel))
        self.assertNotEqual(status, 0, out)
        self.assertIn(f"is in {why}: Claude doesn't move anything there to the trash", err)

    def test_trash_never_reaches_the_mail_store(self):
        self.assert_guarded("Mail/acct/INBOX/cur/1:2,S", "a mail folder")   # the nearest says it
        self.assert_guarded("Mail/acct", "your mail")
        self.assert_guarded("Mail", "your mail")

    def test_trash_never_reaches_notes_or_projects(self):
        self.assert_guarded("Notes/plan.md", "your notes")
        self.assert_guarded("Notes", "your notes")
        self.assert_guarded("Projects/app/main.c", "your projects")

    def test_trash_never_reaches_a_repository_or_a_mail_folder_elsewhere(self):
        self.assert_guarded("code/tool/x.py", "a git repository")
        self.assert_guarded("Downloads/repo", "a git repository")       # the repository itself
        self.assert_guarded("Maildata/acct/INBOX/cur/1:2,S", "a mail folder")
        self.assert_guarded("Maildata/acct/INBOX", "a mail folder")

    def test_trash_in_downloads_and_a_link_to_notes_go(self):
        # The link moves, not what it leads to
        status, out, err = self.run_script("trash", "--check", self.p("Downloads/a.txt"), self.p("Downloads/to-notes"))
        self.assertEqual(status, 0, err)
        self.assertIn("a.txt", json.loads(out)["To the trash"])

    def test_home_in_git_doesnt_guard_everything(self):
        (self.home / ".git").mkdir()
        status, _, err = self.run_script("trash", "--check", self.p("Downloads/a.txt"))
        self.assertEqual(status, 0, err)

    def test_your_own_trash_isnt_guarded(self):
        status, _, err = self.run_script("trash", "--check", self.p("Notes/plan.md"), folders=None)
        self.assertEqual(status, 0, err)

    def test_notes_dir_elsewhere_is_guarded(self):
        (self.home / "Documents/MyNotes").mkdir(parents=True)
        (self.home / "Documents/MyNotes/a.md").write_text("x")
        env_notes = str(self.home / "Documents/MyNotes")
        p = subprocess.run([sys.executable, "-I", str(self.bin / "files"), "trash", "--check",
                            self.p("Documents/MyNotes/a.md")], capture_output=True, text=True, timeout=30,
                           env={"PATH": os.environ["PATH"], "HOME": str(self.home), "NIGHTDRIVE_MCP": "1",
                                "NIGHTDRIVE_MCP_OPTIONS": json.dumps({"folders": OPEN}), "NOTES_DIR": env_notes})
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("is in your notes", p.stderr)

    # --- open ---

    def test_open_refuses_what_acts_as_it_opens(self):
        for name in ("page.html", "pic.svg", "pic.svgz", "list.m3u", "list.pls"):
            status, _, err = self.run_script("open", self.p(f"Downloads/{name}"))
            self.assertNotEqual(status, 0, name)
            self.assertIn("Claude doesn't open it", err)
        self.assertFalse(self.opened.exists())

    def test_open_plain_text_still_opens(self):
        status, _, err = self.run_script("open", self.p("Downloads/notes.txt"))
        self.assertEqual(status, 0, err)
        self.assertIn("--file", self.opened.read_text())

    def test_you_can_open_a_web_page(self):
        status, _, err = self.run_script("open", self.p("Downloads/page.html"), folders=None)
        self.assertEqual(status, 0, err)

    # --- whether something exists ---

    def test_hidden_gets_one_answer_whether_there_or_not(self):
        answers = set()
        for rel in (".ssh/id_rsa", ".ssh/nothing", ".ssh/real/key", ".ssh/none/key", ".nothing/key"):
            for cmd in (("check",), ("trash", "--check"), ("open",)):
                status, _, err = self.run_script(*cmd, self.p(rel))
                self.assertNotEqual(status, 0)
                answers.add(err.replace(self.p(rel), "PATH"))
        self.assertEqual(answers, {"PATH: only files in your home folder, and none hidden (settings, keys, the trash).\n"})

    def test_wallpaper_tells_nothing_of_a_hidden_file(self):
        (self.home / ".local/share/wallpapers").mkdir(parents=True)
        answers = set()
        for rel in (".ssh/id_rsa", ".ssh/id_ed25519", ".ssh/real/key.png", ".ssh/none/key.png"):
            status, _, err = self.run_script("set", self.p(rel), script="wallpaper")
            self.assertNotEqual(status, 0)
            answers.add(err.replace(self.p(rel), "PATH"))
        self.assertEqual(len(answers), 1, answers)
        self.assertIn("none hidden", answers.pop())

    def test_wallpaper_doesnt_say_where_a_link_leads(self):
        (self.home / ".local/share/wallpapers").mkdir(parents=True)
        (self.home / "Downloads/bg.png").symlink_to(self.home / ".ssh/id_rsa")
        status, _, err = self.run_script("set", self.p("Downloads/bg.png"), script="wallpaper")
        self.assertNotEqual(status, 0)
        self.assertNotIn(".ssh", err)
        self.assertNotIn("id_rsa", err)


if __name__ == "__main__":
    unittest.main()
