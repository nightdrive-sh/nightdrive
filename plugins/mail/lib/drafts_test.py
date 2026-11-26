#!/usr/bin/env python3
"""What send --check takes as the draft the user was shown (#1861): `python3 plugins/mail/lib/drafts_test.py`. Claude
gets a draft with its secrets hidden (config/mcp/mask.py), so its copy of a reply quoting a code says "[code hidden]";
that copy sends the draft, but a copy that says anything else in the code's place doesn't."""

import sys
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import drafts  # noqa: E402

BODY = ("Thanks!\n\nOn Thu, Maija wrote:\n> Your verification code is 482913.\n"
        "> Reset: https://x.example/reset?token=Zx81kQp0aLm29sVb\n")
HAVE = {"from": "Me <me@x.y>", "to": ["Maija <maija@b.c>"], "cc": [], "subject": "Re: Your code 482913",
        "body": BODY, "attachments": []}


def shown(**changes):
    return dict(HAVE, **changes)


class Differences(unittest.TestCase):
    def test_the_draft_itself(self):
        self.assertEqual(drafts.differences(HAVE, shown()), [])

    def test_claudes_masked_copy(self):
        copy = shown(subject="Re: Your code [code hidden]",
                     body="Thanks!\n\nOn Thu, Maija wrote:\n> Your verification code is [code hidden].\n"
                          "> Reset: [login link hidden]\n")
        self.assertEqual(drafts.differences(HAVE, copy), [])

    def test_another_code_in_its_place(self):
        """The card would show 111111 while 482913 goes out."""
        self.assertEqual(drafts.differences(HAVE, shown(body=BODY.replace("482913", "111111"))), ["body"])
        self.assertEqual(drafts.differences(HAVE, shown(subject="Re: Your code 111111")), ["subject"])

    def test_half_masked(self):
        """Only the whole copy as Claude got it counts, not a mix of hidden and changed."""
        body = BODY.replace("482913", "[code hidden]").replace("Thanks!", "Thanks, see attached")
        self.assertEqual(drafts.differences(HAVE, shown(body=body)), ["body"])

    def test_hidden_mark_where_the_draft_has_none(self):
        self.assertEqual(drafts.differences(HAVE, shown(body=BODY + "[code hidden]\n")), ["body"])

    def test_missing_fields(self):
        self.assertEqual(drafts.differences(HAVE, {"from": HAVE["from"], "to": HAVE["to"]}), ["subject", "body"])


class Bcc(unittest.TestCase):
    """A draft another app wrote with Bcc isn't sent without them (#1866)."""

    def send(self, headers):
        from email.message import EmailMessage
        msg = EmailMessage()
        for k, v in headers.items():
            msg[k] = v
        sent = []
        with mock.patch.object(drafts, "read", lambda mid: (dict(HAVE, account="acc"), msg)), \
                mock.patch.object(drafts.compose, "resume", lambda mid, m: {"body": BODY}), \
                mock.patch.object(drafts.compose, "send", lambda f: sent.append(f) or {"id": "s@x.y"}):
            try:
                drafts.send("d1@x.y", dict(HAVE))
            except LookupError as e:
                return sent, str(e)
        return sent, ""

    def test_refused(self):
        for bcc in ("boss@x.y", "Boss <boss@x.y>, b@c.d"):
            sent, why = self.send({"To": "maija@b.c", "Bcc": bcc})
            self.assertEqual(sent, [])
            self.assertIn("Bcc", why)

    def test_without(self):
        for headers in ({"To": "maija@b.c"}, {"To": "maija@b.c", "Bcc": " "}):
            sent, why = self.send(headers)
            self.assertEqual((len(sent), why), (1, ""))


if __name__ == "__main__":
    unittest.main()
