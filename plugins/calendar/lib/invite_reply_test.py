#!/usr/bin/env python3
"""Answering an invitation (invite_reply.py, #2130) on calendar folders of their own:
`python3 plugins/calendar/lib/invite_reply_test.py`. Nothing is sent: the REPLY is only built, the sync recorded."""

import sys
import unittest
from pathlib import Path

import icalendar

sys.path.insert(0, str(Path(__file__).parent))
import invite  # noqa: E402
import invite_reply  # noqa: E402
import invite_test  # noqa: E402
import invite_write  # noqa: E402

ME = "jari@example.com"


def ics(method="REQUEST", seq=0):
    return invite_test.ics(method, seq=seq)


def occurrence():
    """One time of a recurring event: the invitation for 10 November alone"""
    text = invite_test.INVITE.format(method="REQUEST", start="1000", end="1100", seq=2)
    text = text.replace("SEQUENCE:2", "SEQUENCE:2\nRECURRENCE-ID;TZID=FLE Standard Time:20261110T100000")
    return icalendar.Calendar.from_ical(text)


def event_of(text):
    reply = icalendar.Calendar.from_ical(text)
    return reply, next(iter(reply.walk("VEVENT")))


class ReplyTest(unittest.TestCase):
    # invite_test's temporary calendars and recorded sync, without running its tests again
    setUp, tearDown, files = invite_test.InviteTest.setUp, invite_test.InviteTest.tearDown, invite_test.InviteTest.files

    def stored_partstat(self):
        stored = icalendar.Calendar.from_ical(self.files()[0].read_bytes())
        event = next(iter(stored.walk("VEVENT")))
        return str(invite_reply.me(event, ME).params["PARTSTAT"])

    def test_the_reply_is_what_rfc_5546_asks_and_no_more(self):
        out = invite_reply.build(ics(seq=3), "accept", ME, "Jari")
        self.assertEqual((out["to"], out["subject"]), ("maija@example.com", "Accepted: Planning review"))
        reply, event = event_of(out["ics"])
        self.assertEqual(str(reply["method"]), "REPLY")
        self.assertEqual(str(event["uid"]), "040000008200E00074C5B7101A82E008-ONE")
        self.assertEqual(int(event["sequence"]), 3)
        self.assertIn("dtstamp", event)
        self.assertEqual(invite_reply.address_of(event["organizer"]), "maija@example.com")
        self.assertEqual(str(event["organizer"].params["CN"]), "Maija Meikäläinen")   # without the override mark
        who = invite_reply.attendees(event)
        self.assertEqual(len(who), 1)                               # only the one answering
        self.assertEqual((invite_reply.address_of(who[0]), str(who[0].params["PARTSTAT"])), (ME, "ACCEPTED"))
        self.assertNotIn("RSVP", who[0].params)
        for gone in ("DESCRIPTION", "VALARM", "ATTACH", "URL:", "LOCATION"):
            self.assertNotIn(gone, out["ics"])                      # the sender's notes and links stay home
        self.assertIn("TZID:FLE Standard Time", out["ics"])        # the zone its time names goes with it
        self.assertTrue(out["listed"])

    def test_maybe_and_decline(self):
        self.assertEqual(invite_reply.build(ics(), "maybe", ME)["subject"], "Tentative: Planning review")
        out = invite_reply.build(ics(), "decline", ME)
        self.assertEqual(str(invite_reply.attendees(event_of(out["ics"])[1])[0].params["PARTSTAT"]), "DECLINED")
        with self.assertRaises(SystemExit):
            invite_reply.build(ics(), "perhaps", ME)

    def test_an_address_not_invited_answers_as_itself(self):
        out = invite_reply.build(ics(), "accept", "alias@example.com", "Jari")
        who = invite_reply.attendees(event_of(out["ics"])[1])[0]
        self.assertEqual((invite_reply.address_of(who), str(who.params["CN"])), ("alias@example.com", "Jari"))
        self.assertFalse(out["listed"])

    def test_one_time_of_a_recurring_event_says_which(self):
        _, event = event_of(invite_reply.build(occurrence(), "decline", ME)["ics"])
        self.assertIn("recurrence-id", event)

    def test_what_cant_be_answered(self):
        for method in ("CANCEL", "PUBLISH", "REPLY"):
            info = invite.describe(ics(method))
            self.assertFalse(invite_reply.status(ics(method), info, ME)["can"])
            with self.assertRaises(SystemExit):
                invite_reply.build(ics(method), "accept", ME)
        own = invite_reply.status(ics(), invite.describe(ics()), "MAIJA@example.com")
        self.assertEqual((own["can"], own["why"]), (False, "You organise it."))
        with self.assertRaises(SystemExit):
            invite_reply.build(ics(), "accept", "not an address")

    def test_accept_puts_it_in_the_calendar_with_the_answer(self):
        info = invite.describe(ics())
        self.assertEqual(invite_reply.status(ics(), info, ME), {"can": True, "why": "", "answer": None,
                                                                "to": "maija@example.com", "as": ME})
        self.assertEqual(invite_reply.answered(ics(), "accept", ME, "acc/home")["done"], "answered")
        self.assertEqual(self.stored_partstat(), "ACCEPTED")
        self.assertEqual(invite_reply.status(ics(), invite.describe(ics()), ME)["answer"], "ACCEPTED")
        invite_reply.answered(ics(), "maybe", ME)                  # a change of mind: the same copy
        self.assertEqual(len(self.files()), 1)
        self.assertEqual(self.stored_partstat(), "TENTATIVE")

    def test_decline_leaves_a_new_one_out(self):
        self.assertEqual(invite_reply.answered(ics(), "decline", ME, "acc/home")["done"], "none")
        self.assertEqual(self.files(), [])
        self.assertEqual(self.synced, [])

    def test_decline_keeps_one_already_there_marked(self):
        invite_write.run(ics(), "add", "acc/home")
        invite_reply.answered(ics(), "decline", ME)
        self.assertEqual(self.stored_partstat(), "DECLINED")
        self.assertEqual(len(self.files()), 1)


if __name__ == "__main__":
    unittest.main()
