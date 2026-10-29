#!/usr/bin/env python3
"""Claude's contacts search can't read the address book a letter or a digit at a time (#1789, #1866):
`python3 plugins/contacts/lib/lookup_test.py`. A word of 2 characters, or a number of 3 digits, is the least, and
given.PER_HOUR different people an hour the most (#1884)."""

import itertools
import string
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import given  # noqa: E402
import lookup  # noqa: E402


class Shortest(unittest.TestCase):
    def find(self, query, shown=("phones",)):
        with mock.patch.object(lookup, "SHOWN", set(shown) if shown is not None else None), \
                mock.patch.object(lookup, "everyone", lambda: []):
            return lookup.find(query, 25)

    def test_too_short(self):
        for query in ("a", "+3", "35", "+35", "0", "00", "040", "- 3", "a +3"):
            with self.subTest(query=query), self.assertRaises(LookupError):
                self.find(query)

    def test_enough(self):
        for query in ("ma", "+358", "358", "0401", "Ma +3", "40 123"):
            with self.subTest(query=query):
                self.assertEqual(self.find(query)["count"], 0)

    def test_your_own_search_has_no_limit(self):
        self.assertEqual(self.find("+3", shown=None)["count"], 0)


def person(i):
    name = "".join(itertools.islice(itertools.cycle(string.ascii_lowercase), i % 26, i % 26 + 5)) + f" {i}"
    return {"id": f"card-{i}", "ids": [f"card-{i}"], "name": name, "nickname": "", "org": "", "company": "",
            "title": "", "emails": [{"label": "", "value": f"p{i}@x.example"}], "phones": [], "addresses": [],
            "accounts": [], "urls": [], "birthday": "", "note": ""}


class PerHour(unittest.TestCase):
    """Two letters at a time, "aa" … "zz", read the whole book: Claude gets at most given.PER_HOUR different people an
    hour (#1884)."""

    BOOK = [person(i) for i in range(300)]

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        for p in (mock.patch.object(given, "FILE", Path(tmp.name) / "state/contacts-claude.json"),
                  mock.patch.object(lookup, "everyone", lambda: self.BOOK),
                  mock.patch.object(lookup, "SHOWN", {"emails"})):
            p.start()
            self.addCleanup(p.stop)

    def test_two_letters_at_a_time(self):
        got, refused = set(), 0
        for a, b in itertools.product(string.ascii_lowercase, repeat=2):
            try:
                got |= {p["id"] for p in lookup.find(a + b, 25)["people"]}
            except LookupError as e:
                refused += 1
                self.assertIn("100 is the most", str(e))
        self.assertLessEqual(len(got), given.PER_HOUR)
        self.assertGreater(refused, 0)
        given.take([f"fill-{i}" for i in range(given.PER_HOUR - len(given.read()))])
        stranger = next(i for i in range(300) if f"card-{i}" not in got)
        with self.assertRaises(LookupError):
            lookup.card(f"p{stranger}@x.example")   # and card by card neither
        again = sorted(got)[0]   # someone Claude already had: still given
        self.assertEqual(lookup.card(f"p{again.split('-')[1]}@x.example")["id"], again)

    def test_the_same_people_again(self):
        for _ in range(50):
            self.assertEqual(lookup.find("abcde", 25)["count"], 12)
        self.assertEqual(len(given.read()), 12)

    def test_an_hour_later(self):
        given.take([f"card-{i}" for i in range(given.PER_HOUR)], now=1000.0)
        with self.assertRaises(LookupError):
            given.take(["card-200"], now=1000.0 + given.WINDOW - 1)
        given.take(["card-200"], now=1000.0 + given.WINDOW)
        self.assertEqual(list(given.read()), ["card-200"])

    def test_a_batch_that_doesnt_fit_counts_nothing(self):
        given.take([f"card-{i}" for i in range(given.PER_HOUR - 1)])
        with self.assertRaises(LookupError):
            given.take(["card-200", "card-201"])
        self.assertNotIn("card-200", given.read())
        given.take(["card-200"])

    def test_a_broken_file(self):
        given.FILE.parent.mkdir(parents=True)
        for text in ("not json", "[]", '{"card-1": "x"}'):
            given.FILE.write_text(text)
            given.take(["card-1"])
            self.assertEqual(list(given.read()), ["card-1"])

    def test_your_own_search_counts_nothing(self):
        with mock.patch.object(lookup, "SHOWN", None):
            for a in string.ascii_lowercase:
                lookup.find(a, 25)
        self.assertFalse(given.FILE.exists())


if __name__ == "__main__":
    unittest.main()
