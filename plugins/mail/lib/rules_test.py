#!/usr/bin/env python3
"""The sorting rules (#3733): `python3 plugins/mail/lib/rules_test.py`. Which folder a sender's mail goes to, which
rule wins, what can't be a rule, and that a change can be taken back."""

import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import rules  # noqa: E402


class Rules(unittest.TestCase):
    def setUp(self):
        d = tempfile.mkdtemp(prefix="nightmail-rules-")
        self.addCleanup(shutil.rmtree, d)
        patch = mock.patch.object(rules, "PATH", os.path.join(d, "rules.json"))
        patch.start()
        self.addCleanup(patch.stop)

    def test_none_at_first(self):
        self.assertEqual(rules.load(), [])
        self.assertIsNone(rules.match([], "home", "news@shop.fi"))

    def test_sender_before_domain(self):
        rules.add("home", "Offers", "domain", "shop.fi")
        rules.add("home", "Receipts", "sender", "orders@shop.fi")
        now = rules.load()
        self.assertEqual(rules.match(now, "home", "Orders@Shop.fi"), "Receipts")
        self.assertEqual(rules.match(now, "home", "news@shop.fi"), "Offers")
        self.assertEqual(rules.match(now, "home", "news@mail.shop.fi"), "Offers")      # a subdomain
        self.assertIsNone(rules.match(now, "home", "news@notshop.fi"))                 # not a subdomain
        self.assertIsNone(rules.match(now, "work", "news@shop.fi"))                    # another account's

    def test_one_rule_per_sender(self):
        rules.add("home", "Offers", "sender", "news@shop.fi")
        change = rules.add("home", "Newsletters", "sender", "news@shop.fi")
        self.assertEqual([r["folder"] for r in change["removed"]], ["Offers"])
        self.assertEqual([r["folder"] for r in rules.load()], ["Newsletters"])
        self.assertEqual(rules.add("home", "Newsletters", "sender", "news@shop.fi"), {"added": [], "removed": []})

    def test_refused(self):
        for kind, value in [("sender", "shop.fi"), ("sender", "a@b@c"), ("domain", "gmail.com"), ("domain", "x@shop.fi"),
                            ("domain", "localhost")]:
            with self.assertRaises(ValueError, msg=value):
                rules.add("home", "Offers", kind, value)
        self.assertEqual(rules.load(), [])

    def test_undo(self):
        rules.add("home", "Offers", "sender", "news@shop.fi")
        change = rules.add("home", "Newsletters", "sender", "news@shop.fi")
        rules.restore(change["added"], change["removed"])
        self.assertEqual([r["folder"] for r in rules.load()], ["Offers"])
        gone = rules.remove("home", "sender", "news@shop.fi")
        self.assertEqual(rules.load(), [])
        rules.restore(gone["added"], gone["removed"])
        self.assertEqual(len(rules.load()), 1)

    def test_address(self):
        self.assertEqual(rules.address('"Shop, the" <News@Shop.fi>'), "news@shop.fi")
        self.assertEqual(rules.address("news@shop.fi"), "news@shop.fi")
        self.assertEqual(rules.address("undisclosed"), "")

    def test_broken_file(self):
        Path(rules.PATH).write_text("{not json")
        self.assertEqual(rules.load(), [])


if __name__ == "__main__":
    unittest.main()
