#!/usr/bin/env python3
"""windows_view's and open_address's limits in config/hypr/scripts/windows (#1866): `python3 config/mcp/windows_test.py`.
Hyprland is a stand-in (the script's hypr(), clients() and claude-write), so nothing is opened or pictured:
- a picture by an app's name is of the window the card showed, or none (the app's latest changed meanwhile);
- …and with the title it showed (a tab switched since, #1884); a listed app's new title gets a card;
- the picture is the window's own buffer (grim -T its stableId), so nothing over it is in it (#1913);
- it is thrown away when the window changed while grim ran: the title, closed, the focus moved (#1913);
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
            "workspace": {"name": "1"}, "monitor": 0, "stableId": "18000001"},
           {"address": "0xa2", "class": "firefox", "title": "News", "at": [800, 40], "size": [800, 600],
            "workspace": {"name": "1"}, "monitor": 0, "stableId": "18000002"}]


class Desktop:
    """Hyprland as the script sees it. during(desk), if given, runs while grim does: what the user changes meanwhile."""
    def __init__(self, wins, during=None, scale=1):
        self.wins, self.during, self.scale, self.focus = [dict(w) for w in wins], during, scale, "0xa1"

    def hypr(self, what):
        return {"monitors": [{"id": 0, "scale": self.scale, "activeWorkspace": {"name": "1"},
                              "specialWorkspace": {"name": ""}}],
                "activewindow": {"address": self.focus}}[what]

    def run(self, argv, **kw):
        if argv and argv[0] == "grim":
            Path(argv[-1]).write_bytes(b"png")
            if self.during:
                self.during(self)
        return mock.MagicMock(returncode=0, stderr="")


TMP = Path(tempfile.mkdtemp(prefix="windows-test-"))
SEEN = TMP / "seen.json"   # never the session's own
OUT = TMP / "shot.png"


def shot(window, wins, card=None, apps=(), during=None, scale=1, grims=None):
    """windows shot WINDOW --check (card None) or as the call the card allowed; (exit code, stdout, stderr, whether
    grim ran). grims, a list, gets each grim's argv; the picture is left in OUT unless it was thrown away."""
    desk = Desktop(wins, during, scale)
    env = {"NIGHTDRIVE_MCP": "1", "NIGHTDRIVE_MCP_OPTIONS": json.dumps({"apps": list(apps)}),
           **({"NIGHTDRIVE_MCP_CARD": json.dumps(card)} if card is not None else {})}
    OUT.unlink(missing_ok=True)
    a = SimpleNamespace(window=window, check=card is None, out=str(OUT), json=True, inline=False)
    out, err = io.StringIO(), io.StringIO()
    with mock.patch.dict(os.environ, env), mock.patch.object(windows, "hypr", desk.hypr), \
            mock.patch.object(windows, "clients", lambda: desk.wins), \
            mock.patch.object(windows, "blocked", lambda c: bool(c.get("private"))), \
            mock.patch.object(windows, "entries", lambda: {}), mock.patch.object(windows, "SEEN", SEEN), \
            mock.patch.object(windows.subprocess, "run", side_effect=desk.run) as run, \
            mock.patch("sys.stdout", out), redirect_stderr(err):
        try:
            windows.cmd_shot(a)
            code = 0
        except SystemExit as e:
            code = e.code
    calls = [c.args[0] for c in run.call_args_list if c.args and c.args[0] and c.args[0][0] == "grim"]
    if grims is not None:
        grims.extend(calls)
    return code, out.getvalue(), err.getvalue(), bool(calls)


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

    def test_the_window_alone(self):
        """grim pictures the window's own buffer by its stableId, never an area of the screen: a window over it isn't
        in the picture (#1913). The scale is of the buffer: at most MAX_EDGE px on the long side."""
        grims = []
        code, out, err, _ = shot("0xa1", FIREFOX, card={"Window": "0xa1"}, scale=2, grims=grims)
        self.assertEqual(code, 0, err)
        argv = grims[0]
        self.assertEqual(argv[argv.index("-T") + 1], "18000001")
        self.assertNotIn("-g", argv)
        self.assertNotIn("-c", argv)
        self.assertEqual(argv[argv.index("-s") + 1], "0.980")       # 1600 px buffer → 1568
        self.assertEqual(json.loads(out)["width"], 1568)

    def test_no_stable_id(self):
        old = [{k: v for k, v in FIREFOX[0].items() if k != "stableId"}]
        code, _, err, took = shot("0xa1", old, card={"Window": "0xa1"})
        self.assertEqual((code, took), (1, False))
        self.assertIn("stableId", err)

    def test_changed_while_grim_ran(self):
        """The tab switched, the window closed or turned private, or the focus moved while grim ran: thrown away."""
        cases = {"its title": lambda d: d.wins[0].update(title="Mail"),
                 "the window closed": lambda d: d.wins.pop(0),
                 "whether it's left out": lambda d: d.wins[0].update(private=True),
                 "its workspace": lambda d: d.wins[0].update(workspace={"name": "3"}),
                 "the focus": lambda d: setattr(d, "focus", "0xa2")}
        for what, during in cases.items():
            with self.subTest(what=what):
                code, out, err, took = shot("0xa1", FIREFOX, card={"Title": "Bank", "Window": "0xa1"}, during=during)
                self.assertEqual((code, took, out), (1, True, ""))
                self.assertIn(what, err)
                self.assertIn("thrown away", err)
                self.assertFalse(OUT.exists())

    def test_unchanged_elsewhere(self):
        """Another window changing meanwhile (a notification, a new window) isn't in the picture: it's kept."""
        code, _, err, _ = shot("0xa1", FIREFOX, card={"Window": "0xa1"},
                               during=lambda d: d.wins[1].update(title="Inbox (3)"))
        self.assertEqual(code, 0, err)
        self.assertTrue(OUT.exists())


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
