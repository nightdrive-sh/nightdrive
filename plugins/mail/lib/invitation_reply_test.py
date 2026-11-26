#!/usr/bin/env python3
"""Answering an invitation from Mail (invitation_reply.py, #2130): `python3 plugins/mail/lib/invitation_reply_test.py`.
Nothing is sent and Calendar isn't run: compose's send and Calendar's answers are stand-ins that record their calls."""

import email
import email.policy
import sys
import unittest
from email.message import EmailMessage
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import compose  # noqa: E402
import invitation_reply  # noqa: E402

ACC = {"name": "Jari", "address": "jari@example.com", "sent": "x/Sent"}
REPLY = {"to": "maija@example.com", "to_name": "Maija", "answer": "ACCEPTED", "subject": "Accepted: Planning",
         "body": "Jari has accepted this invitation.\n\nPlanning\n2026-11-10 10:00–11:00\n",
         "ics": "BEGIN:VCALENDAR\r\nMETHOD:REPLY\r\nEND:VCALENDAR\r\n"}


class ReplyTest(unittest.TestCase):
    def setUp(self):
        self.calls, self.sent = [], []
        self.saved = {n: getattr(compose, n) for n in ("account_id", "account", "parsed", "send")}
        original = EmailMessage()
        original["Message-ID"] = "<invite@example.com>"
        original["References"] = "<earlier@example.com>"
        compose.account_id = lambda msgid: "work"
        compose.account = lambda aid=None: ACC
        compose.parsed = lambda msgid: original
        compose.send = lambda f: self.sent.append(f) or {"ok": True, "id": "new@example.com"}

    def tearDown(self):
        for n, v in self.saved.items():
            setattr(compose, n, v)

    def ask(self, data, args):
        self.calls.append(args)
        if args[0] == "--reply":
            return dict(REPLY)
        return {"done": "answered", "calendar_name": "Home", "said": "Accepted: Planning"}

    def test_it_goes_to_the_organiser_as_a_reply_then_the_calendar_keeps_it(self):
        out = invitation_reply.run("m1", b"ics", ["accept", "--calendar", "acc/home"], self.ask)
        self.assertTrue(out["ok"])
        self.assertEqual(out["said"], "Answer sent to Maija: Accepted, and kept in Home")
        f = self.sent[0]
        self.assertEqual((f["to"], f["account"], f["calendar"]), ("Maija <maija@example.com>", "work", REPLY["ics"]))
        self.assertEqual(f["in_reply_to"], "<invite@example.com>")
        self.assertEqual(f["references"], "<earlier@example.com> <invite@example.com>")
        self.assertEqual(self.calls[0], ["--reply", "accept", "--as", "jari@example.com", "--name", "Jari"])
        self.assertEqual(self.calls[1], ["--answered", "accept", "--as", "jari@example.com", "--add", "acc/home"])

    def test_the_card_sends_nothing(self):
        out = invitation_reply.run("m1", b"ics", ["maybe", "--card"], self.ask)
        self.assertEqual((out["To"], out["From"]), ("Maija <maija@example.com>", "jari@example.com"))
        self.assertEqual(self.sent, [])
        self.assertEqual(len(self.calls), 1)

    def test_a_failed_send_writes_nothing(self):
        compose.send = lambda f: (_ for _ in ()).throw(OSError("connection refused"))
        out = invitation_reply.run("m1", b"ics", ["decline"], self.ask)
        self.assertEqual(out["error"], "Not sent: connection refused")
        self.assertEqual([c[0] for c in self.calls], ["--reply"])   # no --answered

    def test_what_calendar_refuses_isnt_sent(self):
        out = invitation_reply.run("m1", b"ics", ["accept"], lambda d, a: {"error": "You organise it."})
        self.assertEqual(out, {"error": "You organise it."})
        self.assertEqual(self.sent, [])

    def test_wrong_answers(self):
        for args in ([], ["yes"], ["accept", "--loud"]):
            self.assertIn("error", invitation_reply.run("m1", b"", args, self.ask))
        self.assertEqual(self.calls, [])


class MessageTest(unittest.TestCase):
    def test_the_reply_carries_the_calendar_part_as_imip_asks(self):
        msg = compose.build(ACC, {"to": "maija@example.com", "subject": "Accepted: Planning", "body": "Hi",
                                  "calendar": REPLY["ics"]})
        back = email.message_from_bytes(msg.as_bytes(), policy=email.policy.default)
        self.assertEqual(back.get_content_type(), "multipart/alternative")
        cal = [p for p in back.walk() if p.get_content_type() == "text/calendar"]
        self.assertEqual(len(cal), 1)
        self.assertEqual(cal[0].get_param("method"), "REPLY")
        self.assertIn("METHOD:REPLY", cal[0].get_content())


if __name__ == "__main__":
    unittest.main()
