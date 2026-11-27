#!/usr/bin/env python3
"""Your own folders in isyncrc (#3733): `python3 plugins/mail/lib/isync_test.py`. An account that syncs every folder
needs nothing; one that syncs a channel per folder (Gmail) gets a channel for the new folder, and loses only that
one when the folder is deleted, the rest of the file as it was."""

import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import isync  # noqa: E402

RC = """IMAPAccount runbox
Host mail.runbox.com
User me@runbox.example
PassCmd "secret-tool lookup x y"

IMAPStore runbox-remote
Account runbox

MaildirStore runbox-local
Path {root}/home/
Inbox {root}/home/INBOX
SubFolders Verbatim

Channel runbox
Far :runbox-remote:
Near :runbox-local:
Patterns *
Create Both
Expunge Both
SyncState *

IMAPAccount gmail
Host imap.gmail.com
User me@gmail.example

IMAPStore gmail-remote
Account gmail

MaildirStore gmail-local
Path {root}/work/
Inbox {root}/work/INBOX

Channel gmail-inbox
Far :gmail-remote:INBOX
Near :gmail-local:INBOX
Create Near
Expunge Both
SyncState *

Channel gmail-trash
Far ":gmail-remote:[Gmail]/Trash"
Near :gmail-local:Trash
Create Near
SyncState *
"""


class Channels(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="nightmail-isync-"))
        self.addCleanup(shutil.rmtree, self.dir)
        self.root = str(self.dir / "Mail")
        self.rc = self.dir / "isyncrc"
        self.rc.write_text(RC.format(root=self.root))

    def test_patterns_need_nothing(self):
        self.assertEqual(isync.channel_for("home", "Offers", str(self.rc), self.root), "runbox:Offers")
        self.assertEqual(isync.channel_for("home", "INBOX", str(self.rc), self.root), "runbox:INBOX")
        before = self.rc.read_text()
        self.assertIsNone(isync.ensure("home", "Offers", str(self.rc), self.root))
        self.assertEqual(self.rc.read_text(), before)
        box, account = isync.far_box("home", "Offers", str(self.rc), self.root)
        self.assertEqual((box, account["host"]), ("Offers", "mail.runbox.com"))

    def test_a_channel_per_folder(self):
        before = self.rc.read_text()
        self.assertEqual(isync.channel_for("work", "INBOX", str(self.rc), self.root), "gmail-inbox")
        self.assertIsNone(isync.channel_for("work", "Big Offers", str(self.rc), self.root))
        self.assertEqual(isync.ensure("work", "Big Offers", str(self.rc), self.root), "gmail-big-offers")
        self.assertEqual(isync.channel_for("work", "Big Offers", str(self.rc), self.root), "gmail-big-offers")
        self.assertIn('Far ":gmail-remote:Big Offers"', self.rc.read_text())
        box, account = isync.far_box("work", "Big Offers", str(self.rc), self.root)
        self.assertEqual((box, account["name"]), ("Big Offers", "gmail"))
        # Made again: no second channel
        self.assertIsNone(isync.ensure("work", "Big Offers", str(self.rc), self.root))
        self.assertTrue(isync.remove("work", "Big Offers", str(self.rc)))
        self.assertEqual(self.rc.read_text(), before)
        self.assertFalse(isync.remove("work", "Big Offers", str(self.rc)))

    def test_no_isyncrc(self):
        self.rc.unlink()
        self.assertIsNone(isync.channel_for("home", "Offers", str(self.rc), self.root))
        self.assertIsNone(isync.ensure("home", "Offers", str(self.rc), self.root))


if __name__ == "__main__":
    unittest.main()
