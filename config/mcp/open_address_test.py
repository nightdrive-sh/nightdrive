#!/usr/bin/env python3
"""open_address asks once per site (#1981): `python3 config/mcp/open_address_test.py`.

Its asks_if, `nightdrive windows site URL`, prints `first HOST` for a plain address and `yes` for what asks every time:
an unknown or unclear host, a mailto:, an address that holds another one (an open redirect on an allowed site would
carry what Claude put in it on to any site), or a long query. The registry lets an act tool's call past the card only
for a key the user allowed once, and only while Access allows its right. Nothing is opened: the commands are
stand-ins, the memory a file of its own."""

import importlib.machinery
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True

import access  # noqa: E402
import allowed  # noqa: E402
import confirm  # noqa: E402
import registry  # noqa: E402
import run  # noqa: E402
from run import ToolError  # noqa: E402

SCRIPT = REPO / "config/hypr/scripts/windows"
loader = importlib.machinery.SourceFileLoader("windows_script", str(SCRIPT))
windows = importlib.util.module_from_spec(importlib.util.spec_from_loader("windows_script", loader))
loader.exec_module(windows)


class Site(unittest.TestCase):
    """The key is the exact host; what could lead elsewhere, or isn't plainly one host, asks every time"""

    def test_keys(self):
        for url, said in (
            ("https://github.com/foo/bar", "first github.com"),
            ("https://GitHub.com/search?q=quickshell", "first github.com"),   # a host is any case
            ("http://github.com/", "first github.com"),
            ("https://gist.github.com/x", "first gist.github.com"),            # a subdomain is a site of its own
            ("https://youtube.com/watch?v=abc&t=10", "first youtube.com"),
            ("https://a.example/readme.md?f=v1.2", "first a.example"),
            ("https://t.co/abc", "first t.co"),                                 # its own links: not Claude's to make
            ("https://a.example:443/", "first a.example"),                     # the scheme's own port
            ("http://a.example:8080/x", "first a.example:8080"),               # another port, another service
            ("https://xn--80ak6aa92e.example/", "first xn--80ak6aa92e.example"),
        ):
            with self.subTest(url=url):
                self.assertEqual(windows.site(url), said)

    def test_redirects_ask(self):
        for url in (
            "https://www.google.com/url?q=https://evil.example/?d=secret",
            "https://l.facebook.com/l.php?u=https%3A%2F%2Fevil.example",
            "https://a.example/?u=https%253A%252F%252Fevil.example",          # encoded twice
            "https://a.example/?next=//evil.example",
            "https://a.example/?next=evil.example/x",
            "https://a.example/?next=www.evil.example",
            "https://a.example/out/https:/evil.example",
            "https://a.example/#https://evil.example",                         # a script there may read it
            "https://a.example//evil.example",
        ):
            with self.subTest(url=url):
                self.assertEqual(windows.site(url), "yes")

    def test_a_long_query_asks(self):
        self.assertEqual(windows.site("https://a.example/x?d=" + "a" * windows.SITE_QUERY_MAX), "yes")
        self.assertEqual(windows.site("https://a.example/x#" + "a" * (windows.SITE_QUERY_MAX + 1)), "yes")
        self.assertEqual(windows.site("https://a.example/x?d=" + "a" * 100), "first a.example")

    def test_an_unclear_host_asks(self):
        for url in ("https://u@a.example/", "https://a.example:x@evil.example/", "https://a.example\\@evil.example",
                    "https://a.example/\\evil.example", "https://пример.example/", "https://a%2Eexample/",
                    "https://[::1]/", "https://a.example./", "https://a.example:70000/", "https:/a.example",
                    "https://a.example /", "https://a.ex\tample/", "https://", "ftp://a.example/",
                    "mailto:a@b.example?subject=x", "javascript:alert(1)"):
            with self.subTest(url=url):
                self.assertEqual(windows.site(url), "yes")

    def test_the_key_fits_the_memory(self):
        said = windows.site("https://" + ".".join(["a" * 40] * 4) + "/")
        self.assertTrue(allowed.KEY.fullmatch(said.partition(" ")[2]), said)


class Call(unittest.TestCase):
    """registry.call of the real open_address: asks once for a site, then not, and its card says so"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.opened, self.cards, self.answer = [], [], True
        for p in (mock.patch.object(allowed, "FILE", self.dir / "claude-allowed.json"),
                  mock.patch.object(run, "execute", side_effect=self.execute)):
            p.start()
            self.addCleanup(p.stop)
        tools, _ = registry.read_file(REPO / "config/mcp/tools/apps-files.json", REPO / "config/mcp", None)
        self.tool = next(t for t in tools if t.name == "open_address")
        self.reg = registry.Registry(core=self.dir / "none", active=self.dir / "none", access_file=self.dir / "a.json")
        self.reg.visible = lambda: {"open_address": self.tool}
        self.reg.rules = access.Access("normal")
        self.reg.undo = None
        self.reg.confirm = SimpleNamespace(ask=self.card)

    def tearDown(self):
        self.tmp.cleanup()

    def execute(self, tool, argv, stdin, timeout):
        if argv[1:3] == ["windows", "site"]:
            return windows.site(argv[3]) + "\n", "", 0
        self.opened.append(argv[4])
        return '{"kind": "address"}', "", 0

    def card(self, tool, arguments):
        self.cards.append(confirm.card(tool, arguments)["note"] or "")
        return self.answer

    def open(self, url):
        return self.reg.call("open_address", {"url": url})

    def test_once_per_site(self):
        self.open("https://github.com/foo")
        self.assertEqual(len(self.cards), 1)
        self.assertIn("opens addresses on github.com without asking from now on", self.cards[0])
        self.assertNotIn("card_note", self.tool.spec)       # the note was that card's alone
        self.open("https://github.com/bar?tab=readme")
        self.assertEqual((len(self.cards), len(self.opened)), (1, 2))
        self.open("https://gist.github.com/x")              # another host asks
        self.assertEqual(len(self.cards), 2)
        self.assertEqual(allowed.load(), {"open_address": ["gist.github.com", "github.com"]})

    def test_a_redirect_on_an_allowed_site_asks_every_time(self):
        allowed.remember("open_address", "www.google.com")
        for _ in range(2):
            self.open("https://www.google.com/url?q=https://evil.example/")
            self.reg.pace.refusals.clear()
        self.assertEqual(len(self.cards), 2)
        self.assertNotIn("from now on", self.cards[0])       # allowing it doesn't remember anything
        self.assertEqual(allowed.load(), {"open_address": ["www.google.com"]})

    def test_a_refusal_remembers_nothing(self):
        self.answer = False
        with self.assertRaises(ToolError):
            self.open("https://evil.example/?d=secret")
        self.assertEqual((self.opened, allowed.load()), ([], {}))

    def test_mailto_asks_every_time(self):
        self.open("mailto:a@b.example?subject=Hi")
        self.open("mailto:a@b.example?subject=Hi")
        self.assertEqual((len(self.cards), allowed.load()), (2, {}))

    def test_access_ask_asks_every_time(self):
        allowed.remember("open_address", "github.com")
        self.reg.rules = access.Access("normal", {"apps-files": {"modify": "ask"}})
        self.open("https://github.com/foo")
        self.assertEqual(len(self.cards), 1)
        self.assertNotIn("from now on", self.cards[0])

    def test_no_from_an_act_tools_asks_if_still_asks(self):
        with mock.patch.object(windows, "site", return_value="no"):
            self.open("https://github.com/foo")
        self.assertEqual((len(self.cards), allowed.load()), (1, {}))


class Format(unittest.TestCase):
    """asks_if is a change or act tool's; first_note only goes with it"""

    def spec(self, **kw):
        return {"name": "t_x", "title": "X", "description": "x", "class": "act", "area": "apps-files",
                "inputSchema": {"type": "object", "properties": {"u": {"type": "string"}}},
                "command": ["./x", "{u}"], **kw}

    def test_problems(self):
        self.assertIsNone(registry.problem(self.spec(asks_if=["./s", "{u}"], first_note="on {key}"), None))
        self.assertIn("asks_if", registry.problem(self.spec(asks_if=["./s"], **{"class": "read"}), None))
        self.assertIn("first_note", registry.problem(self.spec(first_note="on {key}"), None))
        self.assertIn("first_note", registry.problem(self.spec(asks_if=["./s"], first_note=["x"]), None))


if __name__ == "__main__":
    unittest.main()
