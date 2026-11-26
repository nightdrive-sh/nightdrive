#!/usr/bin/env python3
"""To and Cc with names that hold commas, quotes and encoded words (#3593): `python3 plugins/mail/lib/recipients_test.py`.
A reply to all showed a Cc of "Lastname, Firstname" <addr> as if it began at Firstname. These check that no step from
the reply to SMTP splits such a name: the parsing, the header a sent message and a draft get, notmuch's reply to that
message, and the draft as Claude's card shows it."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from email import message_from_bytes, policy
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import compose  # noqa: E402
import drafts  # noqa: E402
import recipients  # noqa: E402

# Made-up people: a comma in quotes, a comma with letters outside ASCII, an encoded word holding a comma, quotes
# inside a quoted name, and a bare address
CC = ('"Virtanen, Aino" <aino@example.com>, "Mäkinen, Liisa" <liisa@example.com>, '
      '=?utf-8?q?Nieminen=2C_Ville?= <ville@example.net>, "Odd \\"Q\\" Name" <odd@example.org>, plain@example.org')
PEOPLE = [("Virtanen, Aino", "aino@example.com"), ("Mäkinen, Liisa", "liisa@example.com"),
          ("Nieminen, Ville", "ville@example.net"), ('Odd "Q" Name', "odd@example.org"), ("", "plain@example.org")]
ACCOUNT = {"name": "Test Sender", "address": "me@example.org"}


def sent(cc, to="Other Person <other@example.com>"):
    """The message compose.build makes, as the bytes that go out (and into Sent or Drafts), read back."""
    msg = compose.build(ACCOUNT, {"to": to, "cc": cc, "subject": "Plans", "body": "Hello"})
    return msg.as_bytes(), message_from_bytes(msg.as_bytes(), policy=policy.default)


class Parsing(unittest.TestCase):
    def test_names_stay_whole(self):
        self.assertEqual(recipients.pairs(CC), PEOPLE)

    def test_a_list_and_empty_entries(self):
        self.assertEqual(recipients.pairs(['"Virtanen, Aino" <aino@example.com>', "", "Bob <bob@example.com>"]),
                         [("Virtanen, Aino", "aino@example.com"), ("Bob", "bob@example.com")])
        self.assertEqual(recipients.pairs(""), [])
        self.assertEqual(recipients.pairs(None), [])

    def test_shown_readable_and_parses_back(self):
        shown = recipients.listed(CC)
        self.assertEqual(shown[:2], ['"Virtanen, Aino" <aino@example.com>', '"Mäkinen, Liisa" <liisa@example.com>'])
        self.assertEqual(shown[3], '"Odd \\"Q\\" Name" <odd@example.org>')
        self.assertEqual(shown[4], "plain@example.org")
        self.assertNotIn("=?", ", ".join(shown))
        self.assertEqual(recipients.pairs(", ".join(shown)), PEOPLE)

    def test_smtp_gets_every_address(self):
        self.assertEqual(recipients.addresses(["x@example.com", CC]), ["x@example.com"] + [a for _, a in PEOPLE])


class Outgoing(unittest.TestCase):
    def test_cc_header_keeps_each_name(self):
        raw, back = sent(CC)
        self.assertEqual(recipients.pairs(str(back["Cc"])), PEOPLE)
        self.assertEqual(recipients.pairs(str(back["To"])), [("Other Person", "other@example.com")])
        self.assertIn(b"aino@example.com", raw)

    def test_shown_form_sends_the_same(self):
        """A draft saved from what the card shows (drafts.draft joins addresses()) goes to the same people."""
        _, back = sent(", ".join(drafts.addresses(CC)))
        self.assertEqual(recipients.pairs(str(back["Cc"])), PEOPLE)

    def test_draft_view_is_readable(self):
        self.assertEqual(drafts.addresses(CC), recipients.listed(CC))


@unittest.skipUnless(shutil.which("notmuch"), "needs notmuch")
class Reply(unittest.TestCase):
    """notmuch reply's headers are what the writing window's To and Cc get (compose.reply)."""

    def test_reply_to_all_keeps_the_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            maildir = Path(tmp, "Mail", "INBOX")
            for sub in ("cur", "new", "tmp"):
                (maildir / sub).mkdir(parents=True)
            raw, _ = sent(CC, to='"Korhonen, Pekka" <pekka@example.com>, me@example.org')
            raw = raw.replace(b"From: Test Sender <me@example.org>", b'From: "Lahti, Sanna" <sanna@example.com>')
            (maildir / "new" / "1:2,").write_bytes(raw)
            config = Path(tmp, "config")
            config.write_text(f"[database]\npath={tmp}/Mail\n[user]\nname=Test Sender\nprimary_email=me@example.org\n")
            env = dict(os.environ, NOTMUCH_CONFIG=str(config))
            subprocess.run(["notmuch", "new", "--quiet"], env=env, check=True, capture_output=True)
            mid = message_from_bytes(raw, policy=policy.default)["Message-ID"].strip("<>")
            out = subprocess.run(["notmuch", "reply", "--format=json", "--reply-to=all", "id:" + mid],
                                 env=env, check=True, capture_output=True, text=True).stdout
        h = json.loads(out)["reply-headers"]
        self.assertEqual(recipients.pairs(h["To"]),
                         [("Lahti, Sanna", "sanna@example.com"), ("Korhonen, Pekka", "pekka@example.com")])
        # Quotes inside a name come back without their escapes from notmuch: the address is what must hold
        self.assertEqual([a for _, a in recipients.pairs(h["Cc"])], [a for _, a in PEOPLE])
        self.assertEqual(recipients.pairs(h["Cc"])[:3], PEOPLE[:3])


if __name__ == "__main__":
    unittest.main()
