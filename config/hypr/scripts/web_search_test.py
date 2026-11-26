#!/usr/bin/env python3
"""web-search (#2836): what is an address, and how a Chromium browser's search template is filled and found:
`python3 config/hypr/scripts/web_search_test.py`. Nothing is opened: the browser's profile is a throwaway folder."""

import json
import os
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
loader = SourceFileLoader("web_search", str(HERE / "web-search"))
ws = module_from_spec(spec_from_loader("web_search", loader))
loader.exec_module(ws)


class Address(unittest.TestCase):
    def test_addresses(self):
        self.assertEqual(ws.address("nightdrive.sh"), "https://nightdrive.sh")
        self.assertEqual(ws.address("example.com/a?b=1"), "https://example.com/a?b=1")
        self.assertEqual(ws.address("http://x.org"), "http://x.org")
        self.assertEqual(ws.address("localhost:8080"), "http://localhost:8080")
        self.assertEqual(ws.address("192.168.1.1/admin"), "http://192.168.1.1/admin")

    def test_searches(self):
        for text in ("best pizza helsinki", "3.5", "fm-84", "https://x.com/a b", "mailto:a@b.c", "v1.2"):
            self.assertEqual(ws.address(text), "", text)


class Template(unittest.TestCase):
    def test_fill(self):
        self.assertEqual(ws.fill("https://s.example/search?q={searchTerms}&src=d", "c++ & co"),
                         "https://s.example/search?q=c%2B%2B%20%26%20co&src=d")
        # Google's prepopulated template: its base URL in, its other parameters out
        self.assertEqual(ws.fill("{google:baseURL}search?q={searchTerms}&{google:RLZ}{google:originalQueryForSuggestion}", "a"),
                         "https://www.google.com/search?q=a")

    def test_dirs(self):
        self.assertTrue(ws.chromium_dir("brave-origin-stable").endswith("/BraveSoftware/Brave-Origin"))
        self.assertTrue(ws.chromium_dir("brave-browser-nightly").endswith("/BraveSoftware/Brave-Browser-Nightly"))
        self.assertTrue(ws.chromium_dir("google-chrome-stable").endswith("/google-chrome"))
        self.assertTrue(ws.chromium_dir("chromium-browser").endswith("/chromium"))

    def test_profile_choice_and_fallback(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(ws, "CONFIG", tmp):
            # Nothing saved: the browser's own engine
            self.assertIn("search.brave.com", ws.chromium_template("brave-browser"))
            self.assertEqual(ws.chromium_template("chromium"), ws.FALLBACK_SEARCH)
            # The last used profile's choice
            prof = os.path.join(tmp, "chromium", "Profile 1")
            os.makedirs(prof)
            with open(os.path.join(tmp, "chromium", "Local State"), "w") as f:
                json.dump({"profile": {"last_used": "Profile 1"}}, f)
            with open(os.path.join(prof, "Preferences"), "w") as f:
                json.dump({"default_search_provider_data": {"template_url_data": {"url": "https://ddg.example/?q={searchTerms}"}}}, f)
            self.assertEqual(ws.chromium_template("chromium"), "https://ddg.example/?q={searchTerms}")


if __name__ == "__main__":
    unittest.main()
