#!/usr/bin/env python3
"""A project manager's space (pm-space.lua), its sessions opened in the background (#3158), in the sandbox only:

    nightdrive sandbox exec python3 nightdrive/config/hypr/pm_space_test.py

A session that `nightdrive ask --background` opens becomes the group's last tab, in the background: the tab shown and the
keyboard stay where they were, whether you are in the PM's window, in one of the tabs or on another workspace. The PM
alone has no group yet: its first session is shown, still without the keyboard.

It opens real windows (kitty), so it runs only inside the sandbox's container, never on a desktop someone uses: elsewhere
(CI, check.py without a desktop, your own Hyprland) it skips itself.
"""

import json
import os
import signal
import subprocess
import tempfile
import time
import unittest

PM_WS, OTHER_WS = 7, 8            # workspaces the test takes; they must be empty
PREFIX = "pmtest_"                # the test windows' titles
SESSION_CLASS = "claude-background"   # terminal-or-claude's --background class (rules.lua, pm-space.lua)
SETTLE = 1.0                      # pm-space.lua arranges 120 ms after events settle; a window takes a moment to map

IN_SANDBOX = os.path.exists("/run/.containerenv") and bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True, check=True).stdout


def clients():
    return json.loads(hyprctl("-j", "clients"))


def address(title):
    for c in clients():
        if c["title"] == PREFIX + title:
            return c["address"]
    return None


def lua(code):
    """Runs Lua in Hyprland; what it writes to the file OUT is returned (hyprctl eval itself only says ok)."""
    with tempfile.NamedTemporaryFile("r", suffix=".json") as f:
        hyprctl("eval", code.replace("OUT", json.dumps(f.name)))
        return json.loads(f.read() or "null")


def state():
    """The focused window's title, and the PM space's group: the tab shown and the tabs in order (titles, no prefix)."""
    return lua(f"""
        local function t(w) return w and (w.title:gsub("^{PREFIX}", "")) or "" end
        local s = {{ focus = t(hl.get_active_window()), shown = "", tabs = {{}} }}
        for _, w in ipairs(hl.get_workspace_windows({PM_WS}) or {{}}) do
            if w.group and #s.tabs == 0 then
                s.shown = t(w.group.current)
                for _, m in ipairs(w.group.members or {{}}) do s.tabs[#s.tabs + 1] = t(m) end
            end
        end
        local f = io.open(OUT, "w")
        f:write('{{"focus":"' .. s.focus .. '","shown":"' .. s.shown .. '","tabs":["' .. table.concat(s.tabs, '","') .. '"]}}')
        f:close()
    """)


def open_window(cls, title, ws):
    """As terminal-or-claude --background opens a session: an exec rule puts it on WS without switching to it."""
    hyprctl("dispatch", f'hl.dsp.exec_cmd("kitty --class {cls} -T {PREFIX}{title} sleep 600", '
                        f'{{ workspace = "{ws} silent" }})')
    for _ in range(80):
        if address(title):
            time.sleep(SETTLE)
            return address(title)
        time.sleep(0.1)
    raise AssertionError(f"{title} didn't open")


def focus(title):
    hyprctl("dispatch", f'hl.dsp.focus({{ window = "address:{address(title)}" }})')
    time.sleep(0.4)


@unittest.skipUnless(IN_SANDBOX, "opens windows: only inside nightdrive sandbox (nightdrive sandbox exec python3 …)")
class BackgroundSession(unittest.TestCase):
    """One space built up in order, each step a check: unittest runs the methods in name order."""

    @classmethod
    def setUpClass(cls):
        taken = [c["title"] for c in clients() if c["workspace"]["id"] in (PM_WS, OTHER_WS)]
        if taken:
            raise unittest.SkipTest(f"workspaces {PM_WS} and {OTHER_WS} aren't empty: {taken}")
        open_window("other", "other", OTHER_WS)
        pm = open_window("pm", "pm", PM_WS)
        hyprctl("eval", f'NightdrivePmSpaces({{ {{ a = "{pm}", n = "Test Project Manager" }} }})')
        time.sleep(SETTLE)

    @classmethod
    def tearDownClass(cls):
        # The terminals themselves: a close request to each left a group's last tab open now and then
        for c in clients():
            if c["title"].startswith(PREFIX):
                try:
                    os.kill(c["pid"], signal.SIGTERM)
                except ProcessLookupError:
                    pass

    def open_session(self, title):
        before = json.loads(hyprctl("-j", "activeworkspace"))["id"]
        open_window(SESSION_CLASS, title, PM_WS)
        self.assertEqual(json.loads(hyprctl("-j", "activeworkspace"))["id"], before, "the view moved")
        return state()

    def test_1_first_session_shown_without_the_keyboard(self):
        focus("other")
        s = self.open_session("s1")
        self.assertEqual((s["focus"], s["shown"], s["tabs"]), ("other", "s1", ["s1"]))

    def test_2_from_another_workspace(self):
        focus("other")
        self.open_session("s2")
        s = self.open_session("s3")
        self.assertEqual((s["focus"], s["shown"], s["tabs"]), ("other", "s1", ["s1", "s2", "s3"]))

    def test_3_from_the_pm(self):
        focus("pm")
        s = self.open_session("s4")
        self.assertEqual((s["focus"], s["shown"], s["tabs"]), ("pm", "s1", ["s1", "s2", "s3", "s4"]))

    def test_4_from_a_tab_in_the_middle(self):
        focus("s2")   # a tab you read: shown and typed in
        s = self.open_session("s5")
        self.assertEqual((s["focus"], s["shown"], s["tabs"]), ("s2", "s2", ["s1", "s2", "s3", "s4", "s5"]))

    def test_5_from_the_last_tab(self):
        focus("s5")
        s = self.open_session("s6")
        self.assertEqual((s["focus"], s["shown"], s["tabs"]), ("s5", "s5", ["s1", "s2", "s3", "s4", "s5", "s6"]))


if __name__ == "__main__":
    unittest.main()
