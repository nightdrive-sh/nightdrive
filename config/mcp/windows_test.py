#!/usr/bin/env python3
"""windows_view's and open_address's limits in config/hypr/scripts/windows (#1866): `python3 config/mcp/windows_test.py`.
Hyprland is a stand-in (the script's hypr(), clients() and claude-write), so nothing is opened or pictured:
- a picture by an app's name is of the window the card showed, or none (the app's latest changed meanwhile);
- …and with the title it showed (a tab switched since, #1884); a listed app's new title gets a card;
- a layer surface over the window (a menu, a notification, the launcher) stops it, the desktop's own empty ones don't;
- a mailto: sets only to, cc, subject and body: no attach=, bcc=, nor one hidden by %-encoding."""

import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "hypr/scripts/windows"
loader = importlib.machinery.SourceFileLoader("windows_script", str(SCRIPT))
spec = importlib.util.spec_from_loader("windows_script", loader)
windows = importlib.util.module_from_spec(spec)
loader.exec_module(windows)

FIREFOX = [{"address": "0xa1", "class": "firefox", "title": "Bank", "at": [0, 40], "size": [800, 600],
            "workspace": {"name": "1"}, "monitor": 0},
           {"address": "0xa2", "class": "firefox", "title": "News", "at": [800, 40], "size": [800, 600],
            "workspace": {"name": "1"}, "monitor": 0}]
OWN = [{"namespace": "nightdrive-bar", "x": 0, "y": 0, "w": 1600, "h": 37},
       {"namespace": "nightdrive-drawer", "x": 0, "y": 37, "w": 1600, "h": 900},
       {"namespace": "claude-confirm", "x": 400, "y": 200, "w": 600, "h": 400}]


class Desktop:
    def __init__(self, wins, layers=()):
        self.wins, self.layers = wins, list(layers)

    def hypr(self, what):
        return {"layers": {"eDP-1": {"levels": {"0": [{"namespace": "wallpaper", "x": 0, "y": 0, "w": 1600,
                                                        "h": 1000}],
                                                "2": OWN[:2], "3": OWN[2:] + self.layers}}},
                "monitors": [{"id": 0, "scale": 1, "activeWorkspace": {"name": "1"},
                              "specialWorkspace": {"name": ""}}]}[what]


SEEN = Path(tempfile.mkdtemp(prefix="windows-test-")) / "seen.json"   # never the session's own


def shot(window, wins, layers=(), card=None, apps=()):
    """windows shot WINDOW --check (card None) or as the call the card allowed; (exit code, stdout, stderr)."""
    desk = Desktop(wins, layers)
    env = {"NIGHTDRIVE_MCP": "1", "NIGHTDRIVE_MCP_OPTIONS": json.dumps({"apps": list(apps)}),
           **({"NIGHTDRIVE_MCP_CARD": json.dumps(card)} if card is not None else {})}
    a = SimpleNamespace(window=window, check=card is None, out=None, json=True, inline=False)
    out, err = io.StringIO(), io.StringIO()
    ran = mock.MagicMock(returncode=0, stderr="")
    with mock.patch.dict(os.environ, env), mock.patch.object(windows, "hypr", desk.hypr), \
            mock.patch.object(windows, "clients", lambda: desk.wins), \
            mock.patch.object(windows, "blocked", lambda c: False), \
            mock.patch.object(windows, "entries", lambda: {}), mock.patch.object(windows, "SEEN", SEEN), \
            mock.patch.object(windows.subprocess, "run", return_value=ran) as run, \
            mock.patch("sys.stdout", out), redirect_stderr(err):
        try:
            windows.cmd_shot(a)
            code = 0
        except SystemExit as e:
            code = e.code
    took = any(c.args and c.args[0] and c.args[0][0] == "grim" for c in run.call_args_list)
    return code, out.getvalue(), err.getvalue(), took


class Shot(unittest.TestCase):
    def test_card_names_the_window(self):
        code, out, _, took = shot("firefox", FIREFOX)
        self.assertEqual((code, json.loads(out)["Window"], took), (0, "0xa1", False))

    def test_same_window_as_the_card(self):
        code, _, err, took = shot("firefox", FIREFOX, card={"App": "firefox", "Window": "0xa1"})
        self.assertEqual((code, took), (0, True), err)

    def test_latest_changed_since_the_card(self):
        """The user used the Bank window after the card showed News: no picture of Bank."""
        code, _, err, took = shot("firefox", FIREFOX, card={"App": "firefox", "Title": "News", "Window": "0xa2"})
        self.assertEqual((code, took), (1, False))
        self.assertIn("isn't firefox's latest", err)

    def test_title_changed_since_the_card(self):
        """The card said Wikipedia; the user switched the tab to the bank before allowing it (#1884)."""
        code, _, err, took = shot("0xa1", FIREFOX, card={"App": "firefox", "Title": "Wikipedia", "Window": "0xa1"})
        self.assertEqual((code, took), (1, False))
        self.assertIn("title changed", err)
        untitled = [dict(FIREFOX[0], title="")]
        self.assertEqual(shot("0xa1", untitled, card={"Title": "(no title)", "Window": "0xa1"})[0], 0)
        self.assertEqual(shot("0xa1", FIREFOX, card={"Title": "Bank", "Window": "0xa1"})[0], 0)

    def test_listed_app_asks_for_a_new_title(self):
        """Firefox on the list: Wikipedia pictured without a card, then the bank tab gets one."""
        SEEN.unlink(missing_ok=True)
        wiki = [dict(FIREFOX[0], title="Wikipedia")]
        bank = [dict(FIREFOX[0], title="Bank")]
        self.assertFalse(json.loads(shot("0xa1", wiki, apps=["firefox"])[1]).get("ask", True))   # the first: listed
        said = json.loads(shot("0xa1", wiki, apps=["firefox"])[1])
        self.assertEqual(shot("0xa1", wiki, card=said, apps=["firefox"])[3], True)
        self.assertFalse(json.loads(shot("0xa1", wiki, apps=["firefox"])[1]).get("ask", True))   # seen: no card
        self.assertNotIn("ask", json.loads(shot("0xa1", bank, apps=["firefox"])[1]))           # new: the card
        self.assertNotIn("ask", json.loads(shot("0xa2", FIREFOX, apps=["firefox"])[1]))        # another window
        self.assertEqual(shot("0xa1", bank, card={"Title": "Bank", "Window": "0xa1"}, apps=["firefox"])[3], True)
        self.assertFalse(json.loads(shot("0xa1", bank, apps=["firefox"])[1]).get("ask", True))   # allowed once
        SEEN.write_text("not json")
        self.assertFalse(json.loads(shot("0xa1", bank, apps=["firefox"])[1]).get("ask", True))

    def test_layers_over_it(self):
        for layer in ({"namespace": "nightdrive-menu", "x": 700, "y": 37, "w": 300, "h": 400},
                      {"namespace": "nightdrive-notifications", "x": 500, "y": 50, "w": 300, "h": 900},
                      {"namespace": "", "x": 0, "y": 0, "w": 10000, "h": 10000}):
            with self.subTest(layer=layer["namespace"]):
                code, _, err, took = shot("0xa1", FIREFOX, layers=[layer], card={"Window": "0xa1"})
                self.assertEqual((code, took), (1, False))
                self.assertIn("over it", err)
                self.assertEqual(shot("0xa1", FIREFOX, layers=[layer])[0], 1)   # the card's check too

    def test_layer_elsewhere(self):
        menu = {"namespace": "nightdrive-menu", "x": 1000, "y": 37, "w": 300, "h": 400}   # over News only
        self.assertEqual(shot("0xa1", FIREFOX, layers=[menu], card={"Window": "0xa1"})[0], 0)
        self.assertEqual(shot("0xa2", FIREFOX, layers=[menu], card={"Window": "0xa2"})[0], 1)


class Mailto(unittest.TestCase):
    def open(self, target):
        a = SimpleNamespace(target=target, url=True, app=False, file=False, json=True, unless_typing=False)
        err = io.StringIO()
        with mock.patch.object(windows, "focused_address", lambda: ""), \
                mock.patch.object(windows, "clients", lambda: []), \
                mock.patch.object(windows, "launch") as launch, mock.patch("sys.stdout", io.StringIO()), \
                redirect_stderr(err):
            try:
                windows.cmd_open(a)
                code = 0
            except SystemExit as e:
                code = e.code
        return code, launch.called, err.getvalue()

    def test_fields_allowed(self):
        for url in ("mailto:a@b.c", "mailto:a@b.c?subject=Hi&body=See%20you", "MAILTO:a@b.c?To=x@y.z&CC=c@d.e",
                    "https://example.com/?attach=x"):
            with self.subTest(url=url):
                self.assertEqual(self.open(url)[:2], (0, True))

    def test_hostile(self):
        for url in ("mailto:a@b.c?attach=/home/u/.ssh/id_ed25519", "mailto:a@b.c?subject=x&%61ttach=~/.ssh/id",
                    "mailto:a@b.c?bcc=evil@x.y", "mailto:a@b.c?subject=x&amp;attachment=file:///etc/passwd",
                    "mailto:a@b.c?Attach=x", "mailto:a@b.c?subject=x& attach=y", "mailto:a@b.c?in-reply-to=<x>"):
            with self.subTest(url=url):
                code, launched, err = self.open(url)
                self.assertEqual((code, launched), (1, False))
                self.assertIn("A mailto: address may set", err)


if __name__ == "__main__":
    unittest.main()
