#!/usr/bin/env python3
"""Claude's contacts search can't read the address book a letter or a digit at a time (#1789, #1866):
`python3 plugins/contacts/lib/lookup_test.py`. A word of 2 characters, or a number of 3 digits, is the least."""

import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

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


if __name__ == "__main__":
    unittest.main()
