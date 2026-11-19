#!/usr/bin/env python3
"""⌘⇧ + a number moves a tab alone (window-groups.lua, #3194), in the sandbox only:

    nightdrive sandbox exec python3 nightdrive/config/hypr/group_move_test.py

A tab goes to the workspace out of its group, the tab after it is shown in its place (the one before, when it was the
last) and the other tabs stay; a window in no group moves as before. On a workspace whose focused window is a group it
doesn't join that group. A session moved out of a project manager's space (pm-space.lua) isn't taken back into its group.

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

SRC, DEST, PM_WS = 5, 6, 7        # workspaces the test takes; they must be empty
PREFIX = "gmtest_"                # the test windows' titles
SESSION_CLASS = "claude-background"   # terminal-or-claude's --background class (rules.lua, pm-space.lua)
SETTLE = 1.0                      # a window takes a moment to map; pm-space.lua arranges 120 ms after events settle

IN_SANDBOX = os.path.exists("/run/.containerenv") and bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True, check=True).stdout


def clients():
    return [c for c in json.loads(hyprctl("-j", "clients")) if c["title"].startswith(PREFIX)]


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


def where(title):
    """A window's workspace and its group's tabs in order (titles, no prefix; [] in none)."""
    by_addr = {c["address"]: c["title"].removeprefix(PREFIX) for c in clients()}
    for c in clients():
        if c["title"] == PREFIX + title:
            return c["workspace"]["id"], [by_addr.get(a, a) for a in c["grouped"]]
    return None, []


def shown(ws):
    """The tab shown in the group on ws, and the focused window (titles, no prefix)."""
    return lua(f"""
        local function t(w) return w and (w.title:gsub("^{PREFIX}", "")) or "" end
        local s = ""
        for _, w in ipairs(hl.get_workspace_windows({ws}) or {{}}) do
            if w.group and s == "" then s = t(w.group.current) end
        end
        local f = io.open(OUT, "w")
        f:write('["' .. s .. '","' .. t(hl.get_active_window()) .. '"]')
        f:close()
    """)


def open_window(title, ws, cls="kitty"):
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


def group(*titles):
    """The windows as one group, in this order, the first one's tab shown."""
    first = address(titles[0])
    hyprctl("dispatch", f'hl.dsp.group.toggle({{ window = "address:{first}" }})')
    for t in titles[1:]:
        hyprctl("eval", f'local g = hl.get_window("address:{first}").group; '
                        f'g:add(hl.get_window("address:{address(t)}"), g.size + 1)')
    hyprctl("dispatch", f'hl.dsp.group.active({{ index = 1, window = "address:{first}" }})')
    time.sleep(0.4)


def move(ws):
    """What ⌘⇧ + the number does (bindings.lua)."""
    hyprctl("eval", f"NIGHTDRIVE_MOVE_TO_WORKSPACE({ws})")
    time.sleep(SETTLE)


@unittest.skipUnless(IN_SANDBOX, "opens windows: only inside nightdrive sandbox (nightdrive sandbox exec python3 …)")
class MoveTab(unittest.TestCase):
    """Built up in order, each step a check: unittest runs the methods in name order."""

    @classmethod
    def setUpClass(cls):
        taken = [c["title"] for c in json.loads(hyprctl("-j", "clients")) if c["workspace"]["id"] in (SRC, DEST, PM_WS)]
        if taken:
            raise unittest.SkipTest(f"workspaces {SRC}, {DEST} and {PM_WS} aren't empty: {taken}")
        for t in ("a", "b", "c", "d"):
            open_window(t, SRC)
        group("a", "b", "c", "d")
        for t in ("x", "y"):
            open_window(t, DEST)
        group("x", "y")

    @classmethod
    def tearDownClass(cls):
        for c in clients():
            try:
                os.kill(c["pid"], signal.SIGTERM)
            except ProcessLookupError:
                pass

    def test_1_a_middle_tab_goes_alone(self):
        focus("b")
        move(DEST)
        self.assertEqual(where("b"), (DEST, []), "b moved in a group, or not at all")
        self.assertEqual(where("a"), (SRC, ["a", "c", "d"]))
        self.assertEqual(shown(SRC)[0], "c", "the tab after b isn't shown")
        self.assertEqual(shown(DEST)[1], "b", "the focus didn't follow it")
        self.assertEqual(where("x"), (DEST, ["x", "y"]), "b joined the group where it landed")

    def test_2_the_last_tab_shows_the_one_before(self):
        focus("d")
        move(DEST)
        self.assertEqual(where("d"), (DEST, []))
        self.assertEqual(where("a"), (SRC, ["a", "c"]))
        self.assertEqual(shown(SRC)[0], "c")

    def test_3_two_tabs_leave_one_window(self):
        focus("a")
        move(DEST)
        self.assertEqual(where("a"), (DEST, []))
        self.assertEqual(where("c"), (SRC, []), "a group of one was left behind")

    def test_4_a_window_in_no_group_moves_as_before(self):
        focus("c")
        move(DEST)
        self.assertEqual(where("c"), (DEST, []))

    def test_5_a_session_moved_out_of_a_pm_space_stays_out(self):
        pm = open_window("pm", PM_WS, "pm")
        hyprctl("eval", f'NightdrivePmSpaces({{ {{ a = "{pm}", n = "Test Project Manager" }} }})')
        time.sleep(SETTLE)
        for t in ("s1", "s2", "s3"):
            open_window(t, PM_WS, SESSION_CLASS)
        self.assertEqual(where("s1"), (PM_WS, ["s1", "s2", "s3"]))
        focus("s2")
        move(DEST)
        time.sleep(SETTLE)
        self.assertEqual(where("s2"), (DEST, []), "s2 went back, or into a group")
        self.assertEqual(where("s1"), (PM_WS, ["s1", "s3"]))
        self.assertEqual(where("pm"), (PM_WS, []))


if __name__ == "__main__":
    unittest.main()
