#!/usr/bin/env python3
"""Mail's ids as Claude's tools give them (#1859): `python3 plugins/mail/lib/ids_test.py`. Each test builds a throwaway
notmuch database and account, runs the commands mcp.json runs (archive, unarchive, delete --check, thread, search,
draft, draft-show, discard, send --check) with ids that are queries in disguise, and checks they are refused and that
no mail moved. Needs notmuch; sends nothing (the account's SMTP server is a closed port)."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import ids  # noqa: E402

# Ids that are, or hide, a query: each must be refused before notmuch sees it
HOSTILE = [
    "thread:0 or tag:inbox", "*", "tag:inbox", "tag:draft", "(tag:inbox)", "(tag inbox)", 'x" or tag:inbox or id:"y@z',
    "m1@b.c or tag:inbox", "m1@b.c OR *", "m1@b.c)", "(m1@b.c", '"m1@b.c"', "m1@b.c*", "m1@b.c\\", "a@b c", "a@b\tc",
    "m1@b.c\n", "", " ", "thread:*", "thread:", "thread:0000000000000001 or *", "thread:000000000000000G",
    "thread:00000000000000001", "notmuch-sha1-*", "--output=files", "folder:/INBOX/", "date:2000..", "<m1@b.c>",
    "thread:0 or subject:Hello",   # deleted "Hello" before #1859, with "Hello" as its subject on the card
]
EVIL = 'x" or tag:inbox or id:"y@z'   # a stranger's Message-ID with a quote in it

ACCOUNT = """[account acc]
name = Me
address = me@x.y
smtp = 127.0.0.1:1
user = me
password-cmd = true
sent = acc/Sent
drafts = acc/Drafts
"""


def mail(mid, subject, body="Hello", reply_to=None):
    extra = f"In-Reply-To: <{reply_to}>\n" if reply_to else ""
    return (f"From: Maija <maija@b.c>\nTo: Me <me@x.y>\nSubject: {subject}\nMessage-ID: <{mid}>\n{extra}"
            f"Date: Thu, 29 Oct 2026 10:00:00 +0200\n\n{body}\n")


@unittest.skipUnless(shutil.which("notmuch"), "needs notmuch")
class Commands(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="nightmail-ids-"))
        self.addCleanup(shutil.rmtree, self.dir)
        self.root = self.dir / "mail"
        self.files = {}
        for folder, mid, subject, extra in [
            ("INBOX", "m1@b.c", "Hello", {}), ("INBOX", "m3@b.c", "Re: Hello", {"reply_to": "m1@b.c"}),
            ("INBOX", "m2@b.c", "Bills", {}), ("INBOX", EVIL, "Evil", {}), ("Archive", "a1@b.c", "Old", {}),
            ("Drafts", "d1@x.y", "First", {"body": "First draft"}), ("Drafts", "d2@x.y", "Second", {}),
        ]:
            for sub in ("cur", "new", "tmp"):
                (self.root / "acc" / folder / sub).mkdir(parents=True, exist_ok=True)
            path = self.root / "acc" / folder / "cur" / f"{len(self.files)}:2,S"
            path.write_text(mail(mid, subject, **extra))
            self.files[mid] = path
        (self.dir / "config" / "nightmail").mkdir(parents=True)
        (self.dir / "config" / "nightmail" / "account.conf").write_text(ACCOUNT)
        (self.dir / "notmuch").write_text(f"[database]\npath={self.root}\n[new]\ntags=inbox;unread;\n"
                                          "[search]\nexclude_tags=deleted;spam;\n")
        self.env = {**os.environ, "NOTMUCH_CONFIG": str(self.dir / "notmuch"), "XDG_CONFIG_HOME": str(self.dir / "config"),
                    "XDG_CACHE_HOME": str(self.dir / "cache"), "NIGHTDRIVE_MCP": "1",
                    "NIGHTDRIVE_MCP_OPTIONS": json.dumps({"blocked": ["bank.fi"]})}
        self.env.pop("NOTMUCH_PROFILE", None)
        self.notmuch("new", "--quiet")
        self.notmuch("tag", "-inbox", "--", "folder:acc/Archive")
        self.notmuch("tag", "-inbox", "+draft", "--", "folder:acc/Drafts")

    def notmuch(self, *args):
        return subprocess.run(["notmuch", *args], env=self.env, capture_output=True, text=True, check=True).stdout

    def run_lib(self, script, *args, stdin=""):
        return subprocess.run([sys.executable, str(HERE / script), *args], env=self.env, input=stdin,
                              capture_output=True, text=True)

    def thread_of(self, mid):
        return self.notmuch("search", "--output=threads", "--query=sexp", ids.message(mid)).strip()

    def mail_files(self):
        return sorted(str(p.relative_to(self.root)) for p in self.root.glob("acc/*/cur/*"))

    def refused(self, result, before):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.mail_files(), before, "mail moved")

    def test_archive_refuses_hostile_ids(self):
        before = self.mail_files()
        for bad in HOSTILE:
            with self.subTest(id=bad):
                self.refused(self.run_lib("inbox.py", "archive", bad), before)
                # One bad id among good ones stops them all
                self.refused(self.run_lib("inbox.py", "archive", self.thread_of("m2@b.c"), bad), before)

    def test_unarchive_and_delete_refuse_hostile_ids(self):
        before = self.mail_files()
        for bad in HOSTILE:
            with self.subTest(id=bad):
                self.refused(self.run_lib("inbox.py", "unarchive", bad), before)
                # A real subject doesn't make it pass
                for said in ("Bills", "Hello"):
                    self.refused(self.run_lib("inbox.py", "delete", "--check", bad,
                                              stdin=json.dumps({"subjects": [said]})), before)

    def test_archive_moves_only_the_thread(self):
        out = self.run_lib("inbox.py", "archive", self.thread_of("m1@b.c"))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(sorted(json.loads(out.stdout)["ids"]), ["m1@b.c", "m3@b.c"])
        inbox = self.notmuch("search", "--output=messages", "tag:inbox").split()
        self.assertEqual(sorted(inbox), sorted(["id:m2@b.c", "id:" + self.evil_id()]))

    def evil_id(self):
        return self.notmuch("search", "--output=messages", "subject:Evil").split()[0].removeprefix("id:")

    def test_quote_in_a_message_id_stays_one_message(self):
        """A stranger's Message-ID with a quote, read back from the database, is quoted in every query."""
        out = self.run_lib("inbox.py", "archive", self.thread_of(self.evil_id()))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(json.loads(out.stdout)["moved"], 1)
        self.assertEqual(sorted(self.notmuch("search", "--output=messages", "tag:inbox").split()),
                         ["id:m1@b.c", "id:m2@b.c", "id:m3@b.c"])
        # Its id as such isn't one Claude can give (a quote), but its thread is
        self.assertNotEqual(self.run_lib("browse.py", "thread", self.evil_id()).returncode, 0)
        self.assertEqual(self.run_lib("browse.py", "thread", self.thread_of(self.evil_id())).returncode, 0)

    def test_unarchive_takes_back_what_archive_printed(self):
        """Archive's undo gets the ids it printed, as the database has them: an odd Message-ID among them (a *,
        parentheses, a quote) doesn't stop the rest from coming back (#1881)"""
        odd = "odd*(x)@b.c"
        path = self.root / "acc" / "INBOX" / "cur" / "odd:2,S"
        path.write_text(mail(odd, "Odd"))
        self.notmuch("new", "--quiet")
        out = self.run_lib("inbox.py", "archive", self.thread_of(odd), self.thread_of(self.evil_id()),
                           self.thread_of("m2@b.c"))
        self.assertEqual(out.returncode, 0, out.stderr)
        printed = json.loads(out.stdout)["ids"]
        self.assertEqual(sorted(printed), sorted([odd, self.evil_id(), "m2@b.c"]))
        back = self.run_lib("inbox.py", "unarchive", *printed)
        self.assertEqual(back.returncode, 0, back.stderr)
        self.assertEqual(json.loads(back.stdout)["moved"], 3)
        self.assertEqual(sorted(self.notmuch("search", "--output=messages", "tag:inbox").split()),
                         sorted(f"id:{i}" for i in ["m1@b.c", "m2@b.c", "m3@b.c", odd, self.evil_id()]))

    def test_unarchive_is_never_a_query(self):
        """Quoted, an id finds only the message that has it: a1@b.c in Archive stays for anything but its own id"""
        before = self.mail_files()
        for bad in ("a1@b.c*", "*", "a1@b.c or *", "(tag inbox)", "a1@b.c)", '"a1@b.c"', "id:a1@b.c", "a1@b.c "):
            with self.subTest(id=bad):
                self.refused(self.run_lib("inbox.py", "unarchive", bad), before)
        self.assertEqual(self.run_lib("inbox.py", "unarchive", "a1@b.c").returncode, 0)

    def test_delete_check_still_works(self):
        out = self.run_lib("inbox.py", "delete", "--check", "m2@b.c", stdin='{"subjects": ["Bills"]}')
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertTrue(any("/Trash/" in f for f in self.mail_files()))

    def test_thread_refuses_hostile_ids(self):
        for bad in HOSTILE:
            with self.subTest(id=bad):
                out = self.run_lib("browse.py", "thread", bad)
                self.assertNotEqual(out.returncode, 0)
                self.assertEqual(out.stdout, "")
        self.assertEqual(self.run_lib("browse.py", "thread", "m1@b.c").returncode, 0)

    def test_search_query_is_not_an_option(self):
        for env in ({}, {"NIGHTDRIVE_MCP": "0"}):   # with and without the blocked list
            self.env.update(env)
            for query in ("--output=files", "--exclude=false"):
                with self.subTest(query=query, env=env):
                    out = self.run_lib("browse.py", "search", query)
                    self.assertNotIn(str(self.root), out.stdout + out.stderr)
                    if out.returncode == 0:
                        self.assertEqual(json.loads(out.stdout)["threads"], [])

    def drafts_left(self):
        return sorted(p.name for p in self.root.glob("acc/Drafts/cur/*"))

    def test_drafts_refuse_hostile_ids(self):
        before = self.drafts_left()
        shown = json.loads(self.run_lib("drafts.py", "show", "d1@x.y").stdout)
        for bad in HOSTILE + [self.thread_of("d1@x.y")]:
            with self.subTest(id=bad):
                for args, stdin in ((("send", bad, "--check"), json.dumps(shown)), (("discard", bad), ""),
                                    (("show", bad), "")):
                    out = self.run_lib("drafts.py", *args, stdin=stdin)
                    self.assertNotEqual(out.returncode, 0)
                    # Refused for the id: the closed SMTP port would say "Sending failed"
                    self.assertNotIn("Sending failed", out.stderr)
                    self.assertEqual(self.drafts_left(), before)
                if bad == "":
                    continue   # an empty reply_to is a new message, not a reply
                out = self.run_lib("drafts.py", "draft", stdin=json.dumps({"reply_to": bad, "body": "Hi"}))
                self.assertNotEqual(out.returncode, 0)
                self.assertEqual(self.drafts_left(), before)

    def test_only_drafts_are_discarded(self):
        self.assertNotEqual(self.run_lib("drafts.py", "discard", "m2@b.c").returncode, 0)
        out = self.run_lib("drafts.py", "discard", "d2@x.y")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(len(self.drafts_left()), 1)

    def test_send_sends_the_copy_it_compared(self):
        """A draft changed on disk after the comparison doesn't go out: the compared copy does."""
        with mock.patch.dict(os.environ, self.env):
            import compose
            import drafts
            with mock.patch.object(compose, "CONFIG", str(self.dir / "config" / "nightmail" / "account.conf")), \
                    mock.patch.object(compose, "PARTS", str(self.dir / "cache" / "parts")):
                shown = drafts.show("d1@x.y")
                read = drafts.read

                def read_then_sync(mid):
                    got = read(mid)
                    self.files["d1@x.y"].write_text(mail("d1@x.y", "First", body="Changed by a sync"))
                    return got

                sent = {}
                with mock.patch.object(drafts, "read", read_then_sync), \
                        mock.patch.object(compose, "send", lambda f: sent.update(f) or {"id": "s@x.y"}):
                    drafts.send("d1@x.y", shown)
        self.assertIn("First draft", sent["body"])
        self.assertNotIn("Changed", sent["body"])


class Forms(unittest.TestCase):
    def test_hostile(self):
        for bad in HOSTILE + ["a@b\x00", None, ["m1@b.c"], "x" * 600 + "@b.c"]:
            with self.subTest(id=bad), self.assertRaises(ValueError):
                ids.term(bad)

    def test_ids(self):
        for good, want in [("thread:0000000000000005", '(thread "0000000000000005")'),
                           ("CAF=x+1_Q@mail.gmail.com", '(id "CAF=x+1_Q@mail.gmail.com")'),
                           ("20261029.abc$x{1}@host.example", '(id "20261029.abc$x{1}@host.example")'),
                           ("notmuch-sha1-" + "0" * 40, f'(id "notmuch-sha1-{"0" * 40}")')]:
            self.assertEqual(ids.term(good), want)

    def test_threads_only_where_asked(self):
        with self.assertRaises(ValueError):
            ids.term("thread:0000000000000005", threads=False)

    def test_database_ids_are_quoted(self):
        self.assertEqual(ids.message('id:x"y\\z'), '(id "x\\"y\\\\z")')


if __name__ == "__main__":
    unittest.main()
