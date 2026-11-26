#!/usr/bin/env python3
"""A reply has one draft, and Claude writes a new version of it (#3624): `python3 plugins/mail/lib/redraft_test.py`.
Claude once wrote the same reply three times into a thread; the copy left behind looked like the user's own unfinished
reply and went out too."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import drafts  # noqa: E402
import redraft  # noqa: E402

SIG = "Jari\n  Example Ltd"
QUOTE = "On Wed 25 Nov 2026, 09:12, Pinja wrote:\n> Käykö torstai?\n>\n> [code hidden]\n"


def node(mid, folder, replies=(), ts=0):
    return [{"id": mid, "headers": {"Subject": "s"}, "timestamp": ts,
             "filename": [f"/m/a/{folder}/cur/{mid}:2,S"]}, list(replies)]


class Tail(unittest.TestCase):
    def test_signature_and_quote(self):
        body = f"Hei!\n\nKäy.\n\n{SIG}\n\n{QUOTE}"
        self.assertEqual(redraft.tail(body, SIG), f"{SIG}\n\n{QUOTE}")

    def test_quote_without_signature(self):
        self.assertEqual(redraft.tail(f"Hei!\n\n{QUOTE}", ""), QUOTE)

    def test_finnish_attribution(self):
        quote = "Pinja kirjoitti:\n> Käykö?\n"
        self.assertEqual(redraft.tail("Käy.\n\n" + quote, ""), quote)

    def test_nothing_below(self):
        self.assertEqual(redraft.tail("Just text\n", ""), "")

    def test_signature_name_in_the_text(self):
        """The signature's first line alone, in the text, isn't where it starts."""
        body = f"Jari\nwill come.\n\n{SIG}\n\n{QUOTE}"
        self.assertEqual(redraft.tail(body, SIG), f"{SIG}\n\n{QUOTE}")

    def test_rewritten_keeps_the_quote_as_it_is(self):
        """Claude's copy of the quote has [code hidden]: only its text above goes in, so the quote stays whole."""
        old = f"Old text\n\n{SIG}\n\n{QUOTE.replace('[code hidden]', '482913')}"
        new = redraft.rewritten("New text\n", old, SIG)
        self.assertEqual(new, f"New text\n\n{SIG}\n\n{QUOTE.replace('[code hidden]', '482913')}")


class Answering(unittest.TestCase):
    def found(self, tree):
        with mock.patch.object(redraft, "notmuch", lambda *a: json.dumps(tree)):
            return redraft.answering("m1@x.y")

    def test_drafts_answering_it(self):
        tree = [[node("m1@x.y", "INBOX", [node("d2@x.y", "Drafts", ts=2), node("d1@x.y", "Drafts", ts=1),
                                          node("sent@x.y", "Sent", ts=3)])]]
        self.assertEqual(self.found(tree), ["d1@x.y", "d2@x.y"])

    def test_not_a_draft_deleted_or_answering_another(self):
        tree = [[node("m1@x.y", "INBOX", [node("m2@x.y", "INBOX", [node("d3@x.y", "Drafts")]),
                                          node("old@x.y", "Trash")])]]
        self.assertEqual(self.found(tree), [])


class Replaced(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        p = mock.patch.object(redraft, "REPLACED", os.path.join(tmp.name, "nightmail", "replaced.json"))
        p.start()
        self.addCleanup(p.stop)
        self.moves = []
        m = mock.patch.object(redraft, "run_move", lambda dest, mid, src: self.moves.append((dest, mid, src)))
        m.start()
        self.addCleanup(m.stop)

    def test_remember_and_restore(self):
        redraft.remember("new@x.y", "old@x.y")
        self.assertEqual(redraft.replaced_by("old@x.y"), "new@x.y")
        self.assertEqual(redraft.restore("new@x.y"), "old@x.y")
        self.assertEqual(self.moves, [("Drafts", "old@x.y", "Trash")])
        self.assertEqual(redraft.restore("new@x.y"), "")      # once
        self.assertEqual(redraft.replaced_by("old@x.y"), "")

    def test_a_draft_that_replaced_none(self):
        self.assertEqual(redraft.restore("x@x.y"), "")
        self.assertEqual(self.moves, [])

    def test_only_the_last_kept(self):
        for i in range(redraft.KEEP + 5):
            redraft.remember(f"n{i}", f"o{i}")
        self.assertEqual(len(redraft.load()), redraft.KEEP)
        self.assertEqual(redraft.replaced_by(f"o{redraft.KEEP + 4}"), f"n{redraft.KEEP + 4}")


class SecondDraft(unittest.TestCase):
    """drafts.py draft refuses a second reply to a message, naming the draft there."""

    def test_refused(self):
        with mock.patch.object(drafts.compose, "accounts", lambda: {"a": {}}), \
                mock.patch.object(drafts.ids, "one", lambda *a, **k: ""), \
                mock.patch.object(drafts.blocked, "entries", lambda: []), \
                mock.patch.object(drafts.blocked, "among", lambda *a: set()), \
                mock.patch.object(drafts.redraft, "answering", lambda mid: ["d1@x.y"]), \
                mock.patch.object(drafts.compose, "draft", lambda f: self.fail("a second draft was written")):
            with self.assertRaises(LookupError) as e:
                drafts.draft({"reply_to": "m1@x.y", "body": "Hi"})
        self.assertIn("d1@x.y", str(e.exception))
        self.assertIn("draft:", str(e.exception))


if __name__ == "__main__":
    unittest.main()
