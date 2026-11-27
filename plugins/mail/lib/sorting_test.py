#!/usr/bin/env python3
"""Your own folders and sorting by sender, end to end (#3733): `python3 plugins/mail/lib/sorting_test.py`. A
throwaway notmuch database and account: a folder made, a sender's mail dragged into it (and its inbox mail along), new
mail from them sorted there unannounced while the rest stays for its notification, ⌘Z, and the folder deleted with its
mail back in the inbox. Needs notmuch; reaches no server (NIGHTMAIL_NO_SYNC, and a closed port)."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent

ACCOUNT = """[account acc]
name = Me
address = me@x.y
smtp = 127.0.0.1:1
user = me
password-cmd = true
sent = acc/Sent
drafts = acc/Drafts
"""

ISYNCRC = """IMAPAccount acc
Host 127.0.0.1
Port 1
TLSType None
User me
Pass x

IMAPStore acc-remote
Account acc

MaildirStore acc-local
Path {root}/acc/
Inbox {root}/acc/INBOX

Channel acc
Far :acc-remote:
Near :acc-local:
Patterns *
Create Both
SyncState *
"""


def mail(mid, sender, subject, reply_to=None):
    extra = f"In-Reply-To: <{reply_to}>\n" if reply_to else ""
    return (f"From: {sender}\nTo: Me <me@x.y>\nSubject: {subject}\nMessage-ID: <{mid}>\n{extra}"
            "Date: Thu, 26 Nov 2026 10:00:00 +0200\n\nHello\n")


@unittest.skipUnless(shutil.which("notmuch"), "needs notmuch")
class Sorting(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="nightmail-sorting-"))
        self.addCleanup(shutil.rmtree, self.dir)
        self.root = self.dir / "mail"
        for folder in ("INBOX", "Sent", "Drafts", "Archive", "Spam", "Trash"):
            for sub in ("cur", "new", "tmp"):
                (self.root / "acc" / folder / sub).mkdir(parents=True, exist_ok=True)
        self.n = 0
        self.deliver("n1@shop.fi", "Shop <news@shop.fi>", "Sale")
        self.deliver("n2@shop.fi", "Shop <news@shop.fi>", "More sale")
        self.deliver("d1@shop.fi", "Deals <deals@mail.shop.fi>", "Deals")
        self.deliver("a1@b.c", "Anna <anna@b.c>", "Lunch?")
        self.deliver("r1@x.y", "Me <me@x.y>", "Re: Sale", reply_to="n1@shop.fi", folder="Sent")
        config = self.dir / "config"
        (config / "nightmail").mkdir(parents=True)
        (config / "nightmail" / "account.conf").write_text(ACCOUNT)
        (config / "isyncrc").write_text(ISYNCRC.format(root=self.root))
        (self.dir / "notmuch").write_text(f"[database]\npath={self.root}\n[new]\ntags=inbox;unread;\n"
                                          "[user]\nprimary_email=me@x.y\n[search]\nexclude_tags=deleted;spam;\n")
        (self.dir / "run").mkdir()
        self.env = {**os.environ, "NOTMUCH_CONFIG": str(self.dir / "notmuch"), "XDG_CONFIG_HOME": str(config),
                    "XDG_CACHE_HOME": str(self.dir / "cache"), "XDG_RUNTIME_DIR": str(self.dir / "run"),
                    "NIGHTMAIL_NO_SYNC": "1"}
        self.env.pop("NOTMUCH_PROFILE", None)
        self.notmuch("new", "--quiet")
        self.notmuch("tag", "-inbox", "--", "folder:acc/Sent")
        self.notmuch("tag", "+notified", "--", "tag:inbox")       # what was there before is old

    def deliver(self, mid, sender, subject, reply_to=None, folder="INBOX"):
        self.n += 1
        sub = "new" if folder == "INBOX" else "cur"
        name = f"{self.n}.test,U={self.n}" + ("" if sub == "new" else ":2,S")
        (self.root / "acc" / folder / sub / name).write_text(mail(mid, sender, subject, reply_to))

    def notmuch(self, *args):
        return subprocess.run(["notmuch", *args], env=self.env, capture_output=True, text=True, check=True).stdout

    def run_lib(self, script, *args, ok=True):
        p = subprocess.run([sys.executable, str(HERE / script), *args], env=self.env, capture_output=True,
                           text=True)
        if ok:
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return json.loads(p.stdout) if p.stdout.strip() else {}

    def folder_of(self, mid):
        files = self.notmuch("search", "--output=files", f"id:{mid}").split()
        return sorted({Path(f).parent.parent.name for f in files})

    def tags(self, mid):
        return set(self.notmuch("search", "--output=tags", f"id:{mid}").split())

    def thread(self, mid):
        return self.notmuch("search", "--output=threads", f"id:{mid}").strip()

    def test_folders(self):
        self.assertEqual(self.run_lib("folders.py", "list"), {"folders": {"acc": []}})
        self.assertEqual(self.run_lib("folders.py", "create", "acc", " Offers ")["folder"], "Offers")
        self.assertTrue((self.root / "acc" / "Offers" / "cur").is_dir())
        self.assertEqual(self.run_lib("folders.py", "list"), {"folders": {"acc": ["Offers"]}})
        for bad in ("offers", "Inbox", "a/b", ".hidden", "", "x*"):
            self.assertIn("error", self.run_lib("folders.py", "create", "acc", bad, ok=False), bad)

    def test_drag_new_mail_and_undo(self):
        self.run_lib("folders.py", "create", "acc", "Offers")
        step = self.run_lib("sorting.py", "learn", "acc", "Offers", self.thread("n1@shop.fi"))
        # The thread's sender is the stranger, not your reply in it
        self.assertEqual(step["senders"], ["news@shop.fi"])
        self.assertEqual(sorted(step["moved"]), ["n1@shop.fi", "n2@shop.fi"])
        self.assertEqual(self.folder_of("n2@shop.fi"), ["Offers"])
        self.assertNotIn("inbox", self.tags("n2@shop.fi"))
        self.assertEqual(self.folder_of("r1@x.y"), ["Sent"])           # your reply stays
        self.assertEqual(self.folder_of("d1@shop.fi"), ["INBOX"])      # another sender of the domain
        self.assertEqual(self.folder_of("a1@b.c"), ["INBOX"])

        # New mail: theirs goes to Offers unannounced, Anna's stays for its notification
        self.deliver("n3@shop.fi", "Shop <NEWS@shop.fi>", "Last chance")
        self.deliver("a2@b.c", "Anna <anna@b.c>", "Tomorrow?")
        self.notmuch("new", "--quiet", "--no-hooks")
        out = self.run_lib("classify.py")
        self.assertEqual(out, {"sorted": 1, "folders": {"acc/Offers": 1}})
        self.assertEqual(self.folder_of("n3@shop.fi"), ["Offers"])
        self.assertTrue({"notified", "unread"} <= self.tags("n3@shop.fi"))
        self.assertNotIn("inbox", self.tags("n3@shop.fi"))
        self.assertEqual(self.folder_of("a2@b.c"), ["INBOX"])
        self.assertNotIn("notified", self.tags("a2@b.c"))

        # ⌘Z: the rule gone, the moved mail back in the inbox
        self.run_lib("sorting.py", "undo", json.dumps(step))
        self.assertEqual(self.run_lib("rules.py", "list")["rules"], [])
        self.assertEqual(self.folder_of("n2@shop.fi"), ["INBOX"])
        self.assertIn("inbox", self.tags("n2@shop.fi"))

    def test_domain_and_forget(self):
        self.run_lib("folders.py", "create", "acc", "Offers")
        step = self.run_lib("sorting.py", "learn", "--domain", "acc", "Offers", "n1@shop.fi")
        self.assertEqual([r["domain"] for r in step["added"]], ["shop.fi"])
        self.assertEqual(self.folder_of("d1@shop.fi"), ["Offers"])     # mail.shop.fi falls under it
        gone = self.run_lib("sorting.py", "forget", "acc", "d1@shop.fi")
        self.assertEqual([r["domain"] for r in gone["removed"]], ["shop.fi"])
        self.assertEqual(self.run_lib("rules.py", "list")["rules"], [])
        self.assertIn("error", self.run_lib("sorting.py", "learn", "--domain", "acc", "Offers", "r1@x.y", ok=False))

    def test_delete_folder(self):
        self.run_lib("folders.py", "create", "acc", "Offers")
        self.run_lib("sorting.py", "learn", "acc", "Offers", "n1@shop.fi")
        # The server can't be reached (a closed port): the mail is back, the folder stays to be deleted again
        failed = self.run_lib("folders.py", "delete", "acc", "Offers", ok=False)
        self.assertIn("back in the inbox", failed["error"])
        self.assertEqual(self.folder_of("n1@shop.fi"), ["INBOX"])
        self.assertTrue((self.root / "acc" / "Offers").is_dir())
        # Without a server account in isyncrc there is nothing to delete there
        (self.dir / "config" / "isyncrc").unlink()
        self.run_lib("sorting.py", "learn", "acc", "Offers", "n1@shop.fi")
        done = self.run_lib("folders.py", "delete", "acc", "Offers")
        self.assertEqual((done["moved"], done["server"]), (2, False))
        self.assertFalse((self.root / "acc" / "Offers").exists())
        self.assertEqual(self.folder_of("n2@shop.fi"), ["INBOX"])
        self.assertTrue({"inbox", "notified"} <= self.tags("n2@shop.fi"))
        self.assertEqual(self.run_lib("rules.py", "list")["rules"], [])


if __name__ == "__main__":
    unittest.main()
