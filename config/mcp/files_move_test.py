#!/usr/bin/env python3
"""Claude's files_mkdir, files_move and files_rename and their undo (#1995): `python3 config/mcp/files_move_test.py`.
The path rules both ways (what moves and where it goes): home only, nothing hidden, Claude's folders by where a link
really leads, none of the guarded places, never over another file, all or none; and move-back, which undoes all three,
keeping the same rules, so a pair edited by hand in the log can't move anything where a move couldn't. Runs copies
of the scripts in a home of its own."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE.parent / "hypr/scripts"
OPEN, NORMAL = ["~"], ["Downloads", "Documents"]   # levels.py's folders, Normal's in short


class Move(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name).resolve()
        self.home, self.bin, self.outside = root / "home", root / "scripts", root / "outside"
        self.bin.mkdir()
        for name in ("files", "files_rules.py", "files_move.py"):
            shutil.copy(SCRIPTS / name, self.bin / name)
        for f in ("Downloads/a.txt", "Downloads/b.pdf", "Downloads/sub/c.txt", "Documents/a.txt", "Documents/d.txt",
                  "Music/song.mp3", "Downloads/repo/.git/HEAD", "Downloads/repo/README", "Mail/acct/INBOX/cur/1",
                  "Mail/acct/INBOX/new/2", "Mail/acct/INBOX/tmp/3", ".ssh/id_rsa", "Notes/plan.md"):
            (self.home / f).parent.mkdir(parents=True, exist_ok=True)
            (self.home / f).write_text("x")
        self.outside.mkdir()
        (self.home / "Downloads/to-ssh").symlink_to(self.home / ".ssh")
        (self.home / "Downloads/to-outside").symlink_to(self.outside)
        (self.home / "Downloads/to-music").symlink_to(self.home / "Music")
        (self.home / "Downloads/to-docs").symlink_to(self.home / "Documents")

    def tearDown(self):
        self.tmp.cleanup()

    def files(self, *args, folders=OPEN):
        """files ARGS as Claude's tool runs it (folders=None: your own use); (exit status, stdout, stderr)."""
        env = {k: v for k, v in os.environ.items() if not k.startswith(("XDG_", "NIGHTDRIVE_MCP", "NOTES_DIR"))}
        env["HOME"] = str(self.home)
        if folders is not None:
            env["NIGHTDRIVE_MCP"] = "1"
            env["NIGHTDRIVE_MCP_OPTIONS"] = json.dumps({"folders": folders})
        p = subprocess.run([sys.executable, "-I", str(self.bin / "files"), *args], env=env, capture_output=True,
                           text=True, timeout=30)
        return p.returncode, p.stdout, p.stderr

    def ok(self, *args, folders=OPEN):
        code, out, err = self.files(*args, folders=folders)
        self.assertEqual(code, 0, err)
        return out

    def refused(self, *args, folders=OPEN, says=""):
        code, out, err = self.files(*args, folders=folders)
        self.assertNotEqual(code, 0, out)
        self.assertIn(says, err)
        return err

    def undo(self, answer, folders=OPEN):
        """The tool's undo, as apps-files.json's template fills it from the answer."""
        return self.files("move-back", "--made", answer["made"], "--", *answer["back"], folders=folders)

    def p(self, rel):
        return self.home / rel

    # --- mkdir ---------------------------------------------------------------------------------------------------

    def test_mkdir_and_its_undo(self):
        made = json.loads(self.ok("mkdir", "--json", "--", "~/Downloads/2026-11-02"))
        self.assertTrue(self.p("Downloads/2026-11-02").is_dir())
        self.assertEqual((made["what"], made["in"], made["back"]), ("2026-11-02", "~/Downloads", []))
        code, _, err = self.undo(made)
        self.assertEqual(code, 0, err)
        self.assertFalse(self.p("Downloads/2026-11-02").exists())

    def test_mkdir_undo_leaves_a_folder_with_files(self):
        made = json.loads(self.ok("mkdir", "--json", "--", "Downloads/new"))
        self.p("Downloads/new/mine.txt").write_text("the user's")
        code, _, err = self.undo(made)
        self.assertNotEqual(code, 0)
        self.assertIn("has files in it now", err)
        self.assertTrue(self.p("Downloads/new/mine.txt").exists())

    def test_mkdir_refuses(self):
        self.refused("mkdir", "--", "~/Downloads/.hidden", says="hidden")
        self.refused("mkdir", "--", "~/.config/x", says="none hidden")
        self.refused("mkdir", "--", "~/Downloads/to-ssh/x", says="none hidden")       # a link counts where it leads
        self.refused("mkdir", "--", "~/Downloads/to-outside/x", says="outside")
        self.refused("mkdir", "--", "~/Music/x", folders=NORMAL, says="outside the folders Claude may use")
        self.refused("mkdir", "--", "~/Downloads/to-music/x", folders=NORMAL, says="outside the folders")
        self.refused("mkdir", "--", "~/Downloads/a/b", says="doesn't exist")             # one level at a time
        self.refused("mkdir", "--", "~/Downloads/sub", says="exists already")
        self.refused("mkdir", "--", "~/Downloads/repo/x", says="a git repository")
        self.refused("mkdir", "--", "~/Mail/acct/x", says="your mail")
        self.refused("mkdir", "--", "~/Downloads/two\nlines", says="control character")
        self.refused("mkdir", "--", "/tmp/x", says="outside")
        self.assertFalse(self.p("Music/x").exists())

    # --- move ----------------------------------------------------------------------------------------------------

    def test_move_into_a_new_folder_and_back(self):
        """The request #1995 came from: a folder for today in Downloads, its files moved there, one Undo."""
        out = json.loads(self.ok("move", "--json", "--into", "~/Downloads/today", "--", "~/Downloads/a.txt",
                                 "~/Downloads/b.pdf"))
        self.assertEqual(sorted(os.listdir(self.p("Downloads/today"))), ["a.txt", "b.pdf"])
        self.assertEqual((out["what"], out["into"], out["made"]),
                         ("2 files", "~/Downloads/today", str(self.p("Downloads/today"))))
        code, _, err = self.undo(out)
        self.assertEqual(code, 0, err)
        self.assertTrue(self.p("Downloads/a.txt").exists() and self.p("Downloads/b.pdf").exists())
        self.assertFalse(self.p("Downloads/today").exists())

    def test_move_never_overwrites(self):
        err = self.refused("move", "--into", "~/Documents", "--", "~/Downloads/a.txt", "~/Downloads/b.pdf",
                           says="Already in ~/Documents: a.txt")
        self.assertIn("nothing is overwritten", err)
        self.assertEqual(self.p("Documents/a.txt").read_text(), "x")
        self.assertTrue(self.p("Downloads/b.pdf").exists())                              # all or none
        self.refused("move", "--into", "~/Music", "--", "~/Downloads/a.txt", "~/Documents/a.txt", says="a.txt")

    def test_move_keeps_to_the_rules_both_ways(self):
        self.refused("move", "--into", "~/Downloads/to-ssh", "--", "~/Downloads/a.txt", says="hidden")
        self.refused("move", "--into", "~/Downloads/to-outside", "--", "~/Downloads/a.txt", says="outside")
        self.refused("move", "--into", "~/Downloads/to-music", "--", "~/Downloads/a.txt", folders=NORMAL,
                     says="outside the folders")
        self.refused("move", "--into", "~/Music", "--", "~/Downloads/a.txt", folders=NORMAL, says="outside")
        self.refused("move", "--into", "~/Downloads", "--", "~/Music/song.mp3", folders=NORMAL, says="outside")
        self.refused("move", "--into", "~/Downloads", "--", "~/.ssh/id_rsa", says="none hidden")
        self.refused("move", "--into", "~/Downloads/repo", "--", "~/Downloads/a.txt", says="a git repository")
        self.refused("move", "--into", "~/Downloads", "--", "~/Downloads/repo/README", says="a git repository")
        self.refused("move", "--into", "~/Documents", "--", "~/Mail/acct/INBOX/cur/1", says="a mail folder")
        self.refused("move", "--into", "~/Mail/acct", "--", "~/Downloads/a.txt", says="your mail")
        self.refused("move", "--into", "~/Documents", "--", "~/Notes/plan.md", says="your notes")
        self.refused("move", "--into", "~/Documents", "--", "~/Downloads", says="home's own folders")
        self.refused("move", "--into", "~/Downloads/sub/deeper", "--", "~/Downloads/sub", says="into itself")
        self.refused("move", "--into", "~/Downloads", "--", "~/Downloads/a.txt", says="already")
        self.refused("move", "--into", "~/Downloads/.stash", "--", "~/Downloads/a.txt", says="hidden")
        self.assertTrue(self.p("Downloads/a.txt").exists() and not self.p("Downloads/.stash").exists())

    def test_move_through_a_link_goes_where_it_leads(self):
        """A link to a folder Claude may use is that folder: the file lands there, and Undo takes it back."""
        out = json.loads(self.ok("move", "--json", "--into", "~/Downloads/to-docs", "--", "~/Downloads/b.pdf"))
        self.assertTrue(self.p("Documents/b.pdf").exists())
        self.assertEqual(out["into"], "~/Documents")
        self.assertEqual(self.undo(out)[0], 0)
        self.assertTrue(self.p("Downloads/b.pdf").exists())

    def test_a_moved_link_is_the_link(self):
        self.ok("move", "--into", "~/Documents", "--", "~/Downloads/to-ssh")
        self.assertTrue(self.p("Documents/to-ssh").is_symlink())
        self.assertTrue(self.p(".ssh/id_rsa").exists())

    def test_which_moves_ask(self):
        ask = lambda *paths, into="~/Downloads/x", folders=NORMAL: self.ok(
            "move", "--asks", "--into", into, "--", *paths, folders=folders).strip()
        self.assertEqual(ask("~/Downloads/a.txt", "~/Downloads/b.pdf"), "no")
        self.assertEqual(ask("~/Downloads/sub"), "yes")                                   # a folder
        self.assertEqual(ask("~/Documents/d.txt"), "yes")                                 # Documents → Downloads
        self.assertEqual(ask("~/Documents/d.txt", folders=OPEN), "no")                    # all one folder on Open
        for n in range(51):
            self.p(f"Downloads/many/{n}.txt").parent.mkdir(exist_ok=True)
            self.p(f"Downloads/many/{n}.txt").write_text("x")
        self.assertEqual(ask(*(f"~/Downloads/many/{n}.txt" for n in range(51)), into="~/Downloads"), "yes")
        self.assertEqual(ask(*(f"~/Downloads/many/{n}.txt" for n in range(50)), into="~/Downloads"), "no")

    def test_the_card(self):
        card = json.loads(self.ok("move", "--check", "--into", "~/Downloads/new", "--", "~/Downloads/sub"))
        self.assertEqual(card["Into"], "~/Downloads/new  (a new folder)")
        self.assertIn("~/Downloads/sub  (a folder of 1 file", card["Move"])
        self.assertFalse(self.p("Downloads/new").exists())

    # --- rename --------------------------------------------------------------------------------------------------

    def test_rename_and_back(self):
        out = json.loads(self.ok("rename", "--json", "--", "~/Downloads/b.pdf", "invoice.pdf"))
        self.assertTrue(self.p("Downloads/invoice.pdf").exists())
        self.assertEqual(self.undo(out)[0], 0)
        self.assertTrue(self.p("Downloads/b.pdf").exists() and not self.p("Downloads/invoice.pdf").exists())

    def test_rename_refuses(self):
        self.refused("rename", "--", "~/Downloads/b.pdf", "a.txt", says="nothing is overwritten")
        self.refused("rename", "--", "~/Downloads/b.pdf", ".b.pdf", says="hidden")
        self.refused("rename", "--", "~/Downloads/b.pdf", "../b.pdf", says="without /")
        self.refused("rename", "--", "~/Downloads/b.pdf", "x" * 256, says="255 bytes")
        self.refused("rename", "--", "~/Downloads", "Stuff", says="home's own folders")
        self.refused("rename", "--", "~/Downloads/repo/README", "R", says="a git repository")
        self.refused("rename", "--", "~/Music/song.mp3", "s.mp3", folders=NORMAL, says="outside")
        self.p("Stuff").mkdir()
        self.p("Mail").rename(self.p("OldMail"))
        self.refused("rename", "--", "~/Stuff", "Mail", says="your mail")

    # --- move-back -----------------------------------------------------------------------------------------------

    def test_move_back_into_a_taken_place_moves_nothing(self):
        out = json.loads(self.ok("move", "--json", "--into", "~/Documents/in", "--", "~/Downloads/a.txt",
                                 "~/Downloads/b.pdf"))
        self.p("Downloads/b.pdf").write_text("new")
        code, _, err = self.undo(out)
        self.assertNotEqual(code, 0)
        self.assertIn("Something new is at ~/Downloads/b.pdf", err)
        self.assertTrue(self.p("Documents/in/a.txt").exists())                             # all or none
        self.assertEqual(self.p("Downloads/b.pdf").read_text(), "new")

    def test_move_back_edited_by_hand_keeps_the_rules(self):
        """A log edited by hand gives move-back any pairs: it moves nothing a move couldn't have."""
        for pair, says in (((str(self.p("Downloads/a.txt")), str(self.p(".ssh/a.txt"))), "hidden"),
                           ((str(self.p("Downloads/a.txt")), str(self.outside / "a.txt")), "outside"),
                           ((str(self.p("Downloads/a.txt")), str(self.p("Downloads/repo/a.txt"))), "git repository"),
                           ((str(self.p(".ssh/id_rsa")), str(self.p("Downloads/id_rsa"))), "none hidden"),
                           ((str(self.p("Downloads/a.txt")), str(self.p("Downloads/.a"))), "hidden"),
                           ((str(self.p("Downloads/a.txt")),), "pairs")):
            code, _, err = self.files("move-back", "--made", "", "--", *pair)
            self.assertNotEqual(code, 0, pair)
            self.assertIn(says, err)
        self.refused("move-back", "--made", "", "--", str(self.p("Downloads/a.txt")), str(self.p("Music/a.txt")),
                     folders=NORMAL, says="outside")
        self.assertTrue(self.p("Downloads/a.txt").exists() and self.p(".ssh/id_rsa").exists())

    def test_your_own_use_keeps_home_and_hidden(self):
        self.ok("move", "--into", "~/Music", "--", "~/Downloads/a.txt", folders=None)   # no folder list of yours
        self.refused("move", "--into", "~/.ssh", "--", "~/Music/a.txt", folders=None, says="none hidden")


if __name__ == "__main__":
    unittest.main()
