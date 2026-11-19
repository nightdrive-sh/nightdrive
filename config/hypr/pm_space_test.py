#!/usr/bin/env python3
"""A project manager's space (pm-space.lua), its sessions opened in the background (#3158), in the sandbox only:

    nightdrive sandbox exec python3 nightdrive/config/hypr/pm_space_test.py

A session that `nightdrive ask --background` opens becomes the group's last tab, in the background: the tab shown and the
keyboard stay where they were, whether you are in the PM's window, in one of the tabs or on another workspace. The PM
alone has no group yet: its first session is shown, still without the keyboard.

A project manager that is a background session of Claude Code's daemon (`claude --bg`, shown in its window by `claude
agents`) isn't up its window's process chain: its sessions still open on its space, after ⌘⌥ moved the whole space to
another workspace and while another one is active (#3196). A new `claude agents` window showing one is a PM by its name
too, as claude-sessions tells the bar, and gets a space of its own (#3200).

A session that opens while the launcher or a menu has the keyboard leaves it there: the space is put in order once the
layer closes (#3206).

A window a session opens itself (a test terminal, a preview: CLAUDECODE=1 in its environment) is a tile where it opens,
never in the group, and the keyboard stays where it was, under the launcher too; one you open yourself on the space is
no tab either, but has the keyboard (#3168).

It opens real windows (kitty), so it runs only inside the sandbox's container, never on a desktop someone uses: elsewhere
(CI, check.py without a desktop, your own Hyprland) it skips itself.
"""

import json
import os
import re
import signal
import subprocess
import tempfile
import time
import unittest

PM_WS, OTHER_WS = 7, 8            # workspaces the test takes; they must be empty
BG_WS, BG_MOVED_WS = 5, 6         # the daemon PM's, before and after ⌘⌥ moves it; empty too
LAYER_WS = 4                      # a space with a layer open over it (#3206); empty too
AGENTS_WS = 3                     # a `claude agents` window opens here beside another window (#3200); empty too
AGENT_WS, AGENT_OTHER_WS = 2, 9   # a space a session opens windows on, and another workspace (#3168); empty too
TERMINAL_OR_CLAUDE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scripts", "terminal-or-claude")
CLAUDE_SESSIONS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "topbar", "scripts", "claude-sessions")
PM_NAME = re.compile(r"\s+(project\s+manager|pm)\s*$", re.I)   # SessionGroups.js isPm
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


def state(ws=PM_WS):
    """The focused window's title, and the PM space's group: the tab shown and the tabs in order (titles, no prefix)."""
    return lua(f"""
        local function t(w) return w and (w.title:gsub("^{PREFIX}", "")) or "" end
        local s = {{ focus = t(hl.get_active_window()), shown = "", tabs = {{}} }}
        for _, w in ipairs(hl.get_workspace_windows({ws}) or {{}}) do
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


@unittest.skipUnless(IN_SANDBOX, "opens windows: only inside nightdrive sandbox (nightdrive sandbox exec python3 …)")
class DaemonProjectManager(unittest.TestCase):
    """`nightdrive ask --background` from a PM no window is a parent of, after its space was moved with ⌘⌥ (#3196)."""

    NAME = "Test Daemon Manager"

    def setUp(self):
        taken = [c["title"] for c in clients() if c["workspace"].get("id") in (BG_WS, BG_MOVED_WS)]
        if taken:
            self.skipTest(f"workspaces {BG_WS} and {BG_MOVED_WS} aren't empty: {taken}")
        self.home = tempfile.TemporaryDirectory()
        self.addCleanup(self.home.cleanup)
        self.addCleanup(BackgroundSession.tearDownClass)

    def ask(self):
        """terminal-or-claude --background as the PM's Bash would run it: CLAUDE_PID is a session named NAME, and no
        window is up the chain (the test runs under no window, as the daemon's sessions do). A throwaway HOME gives it
        a claude that only waits, and the session's record."""
        home = self.home.name
        os.makedirs(f"{home}/.local/bin")
        os.makedirs(f"{home}/.claude/sessions")
        os.makedirs(f"{home}/.config")
        os.symlink(os.path.expanduser("~/.config/hypr"), f"{home}/.config/hypr")
        with open(f"{home}/.local/bin/claude", "w") as f:
            f.write("#!/bin/sh\nexec sleep 600\n")
        os.chmod(f"{home}/.local/bin/claude", 0o755)
        with open(f"{home}/.claude/sessions/{os.getpid()}.json", "w") as f:
            json.dump({"pid": os.getpid(), "name": self.NAME, "kind": "bg"}, f)
        env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE")}
        env.update(HOME=home, CLAUDE_PID=str(os.getpid()))
        before = {c["address"] for c in clients() if c["class"] == SESSION_CLASS}
        subprocess.run([TERMINAL_OR_CLAUDE, "--background", "--dir", home, "--", "hi"], env=env, check=True)
        for _ in range(80):
            new = [c for c in clients() if c["class"] == SESSION_CLASS and c["address"] not in before]
            if new:
                self.addCleanup(os.kill, new[0]["pid"], signal.SIGTERM)   # titled by the command, not PREFIX
                time.sleep(SETTLE)
                return next(c for c in clients() if c["address"] == new[0]["address"])
            time.sleep(0.1)
        raise AssertionError("the session didn't open")

    def test_session_opens_on_the_moved_space(self):
        # The PM's window, titled as Claude Code titles it, its process a plain terminal's
        pm = open_window("kitty", "pm", BG_WS)
        hyprctl("eval", f'NightdrivePmSpaces({{ {{ a = "{pm}", n = "{self.NAME}" }} }})')
        time.sleep(SETTLE)
        # ⌘⌥ to an empty workspace renumbers the whole workspace (bindings.lua, move_all_windows): no window event
        hyprctl("dispatch", f"hl.dsp.workspace.change_id({{ workspace = {BG_WS}, id = {BG_MOVED_WS} }})")
        time.sleep(SETTLE)
        # You are elsewhere: a window on the PM's old number, which is an ordinary workspace again
        hyprctl("dispatch", f'hl.dsp.exec_cmd("kitty -T {PREFIX}there sleep 600", {{ workspace = "{BG_WS}" }})')
        for _ in range(80):
            if address("there"):
                break
            time.sleep(0.1)
        focus("there")
        session = self.ask()
        self.assertEqual(session["workspace"]["id"], BG_MOVED_WS, "the session didn't open on the PM's workspace")
        self.assertTrue(session["grouped"], "the session isn't a tab of the space's group")
        self.assertEqual(json.loads(hyprctl("-j", "activeworkspace"))["id"], BG_WS, "the view moved")
        self.assertEqual(json.loads(hyprctl("-j", "activewindow"))["address"], address("there"), "the keyboard moved")


# A layer as the launcher and the top bar menus are (on-demand, overlay), saying whether it has the keyboard: Hyprland
# doesn't tell which surface has it, Qt's window does (Window.active)
PROBE_QML = """import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
ShellRoot {
    PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 200; implicitHeight: 100
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "pmtest-probe"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        Item { id: probe; property bool keys: Window.active }
        IpcHandler { target: "probe"; function keys(): string { return String(probe.keys) } }
    }
}
"""


class ProbeLayer:
    """A layer with the keyboard, as the launcher has it: PROBE_QML."""

    def make_probe(self):
        self.probe_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.probe_dir.cleanup)
        with open(os.path.join(self.probe_dir.name, "shell.qml"), "w") as f:
            f.write(PROBE_QML)

    def qs(self, *args):
        return subprocess.run(["qs", "-p", self.probe_dir.name, *args], capture_output=True, text=True).stdout.strip()

    def open_layer(self):
        proc = subprocess.Popen(["qs", "-p", self.probe_dir.name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(proc.wait)
        self.addCleanup(self.close_layer)
        for _ in range(80):
            if self.qs("ipc", "call", "probe", "keys") == "true":
                return
            time.sleep(0.1)
        raise AssertionError("the layer didn't get the keyboard")

    def close_layer(self):
        self.qs("kill")


@unittest.skipUnless(IN_SANDBOX, "opens windows: only inside nightdrive sandbox (nightdrive sandbox exec python3 …)")
class LauncherKeepsTheKeyboard(ProbeLayer, unittest.TestCase):
    """A session opened while the launcher (or a menu) is open, you having been in a tab of the space (#3206): putting
    it in the group showed the tab again and focused it, and the keys went to it instead of the launcher. The space is
    put in order once the launcher closes."""

    def setUp(self):
        taken = [c["title"] for c in clients() if c["workspace"].get("id") == LAYER_WS]
        if taken:
            self.skipTest(f"workspace {LAYER_WS} isn't empty: {taken}")
        self.addCleanup(BackgroundSession.tearDownClass)
        self.make_probe()

    def tabs(self):
        for w in clients():
            if w["workspace"]["id"] == LAYER_WS and w["grouped"]:
                return [next(c["title"] for c in clients() if c["address"] == a).removeprefix(PREFIX) for a in w["grouped"]]
        return []

    def test_session_opened_under_the_launcher(self):
        pm = open_window("pm", "lpm", LAYER_WS)
        hyprctl("eval", f'NightdrivePmSpaces({{ {{ a = "{pm}", n = "Test Layer Manager" }} }})')
        time.sleep(SETTLE)
        open_window(SESSION_CLASS, "l1", LAYER_WS)
        open_window(SESSION_CLASS, "l2", LAYER_WS)
        focus("l1")   # the tab you were reading
        self.open_layer()
        open_window(SESSION_CLASS, "l3", LAYER_WS)
        self.assertEqual(self.qs("ipc", "call", "probe", "keys"), "true", "a window took the keyboard from the layer")
        self.close_layer()
        time.sleep(SETTLE)
        self.assertEqual(self.tabs(), ["l1", "l2", "l3"], "the space wasn't put in order once the layer closed")
        self.assertEqual(json.loads(hyprctl("-j", "activewindow"))["address"], address("l1"), "the keyboard moved")


@unittest.skipUnless(IN_SANDBOX, "opens windows: only inside nightdrive sandbox (nightdrive sandbox exec python3 …)")
class SessionOpensAWindow(ProbeLayer, unittest.TestCase):
    """A window a session opens itself (#3168): from the session's shell, as Claude Code runs a command, on the workspace
    you are on. It joined the group you were in, shown, and took the keyboard (agent-windows.lua, pm-space.lua)."""

    @classmethod
    def setUpClass(cls):
        taken = [c["title"] for c in clients() if c["workspace"].get("id") in (AGENT_WS, AGENT_OTHER_WS)]
        if taken:
            raise unittest.SkipTest(f"workspaces {AGENT_WS} and {AGENT_OTHER_WS} aren't empty: {taken}")
        open_window("other", "a-other", AGENT_OTHER_WS)
        pm = open_window("pm", "apm", AGENT_WS)
        hyprctl("eval", f'NightdrivePmSpaces({{ {{ a = "{pm}", n = "Test Agent Manager" }} }})')
        time.sleep(SETTLE)
        open_window(SESSION_CLASS, "a1", AGENT_WS)
        open_window(SESSION_CLASS, "a2", AGENT_WS)

    @classmethod
    def tearDownClass(cls):
        BackgroundSession.tearDownClass()

    def setUp(self):
        self.make_probe()

    def launch(self, title, claude=True):
        """A test window on the active workspace: run from a session's command (CLAUDECODE=1, detached as setsid -f
        leaves it), or as you open one (through Hyprland, as a key or the launcher does)."""
        if claude:
            env = dict(os.environ, CLAUDECODE="1")
            subprocess.run(["setsid", "-f", "kitty", "--class", "demo", "-T", PREFIX + title, "sleep", "600"], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        else:
            hyprctl("dispatch", f'hl.dsp.exec_cmd("kitty --class demo -T {PREFIX}{title} sleep 600")')
        for _ in range(80):
            win = next((c for c in clients() if c["title"] == PREFIX + title), None)
            if win:
                self.addCleanup(self.close_window, win["pid"], title)
                time.sleep(SETTLE)
                return next(c for c in clients() if c["title"] == PREFIX + title)
            time.sleep(0.1)
        raise AssertionError(f"{title} didn't open")

    def close_window(self, pid, title):
        os.kill(pid, signal.SIGTERM)
        for _ in range(50):
            if not address(title):
                return
            time.sleep(0.1)

    def assert_tile(self, win, ws):
        self.assertEqual((win["workspace"]["id"], win["floating"], win["grouped"]), (ws, False, []),
                         "not a tile of its own where it opened")

    def test_from_a_tab(self):
        focus("a1")   # the tab you read and type in
        win = self.launch("demo1")
        self.assert_tile(win, AGENT_WS)
        s = state(AGENT_WS)
        self.assertEqual((s["focus"], s["shown"], s["tabs"]), ("a1", "a1", ["a1", "a2"]))

    def test_from_the_pm(self):
        focus("apm")
        self.assert_tile(self.launch("demo2"), AGENT_WS)
        self.assertEqual(state(AGENT_WS)["focus"], "apm")

    def test_on_another_workspace(self):
        focus("a-other")
        self.assert_tile(self.launch("demo3"), AGENT_OTHER_WS)
        self.assertEqual(state(AGENT_WS)["focus"], "a-other")

    def test_under_the_launcher(self):
        focus("a1")
        self.open_layer()
        self.assert_tile(self.launch("demo4"), AGENT_WS)
        self.assertEqual(self.qs("ipc", "call", "probe", "keys"), "true", "the window took the keyboard from the layer")
        self.close_layer()
        time.sleep(SETTLE)
        s = state(AGENT_WS)
        self.assertEqual((s["shown"], s["tabs"]), ("a1", ["a1", "a2"]))

    def test_your_own_window(self):
        focus("a1")
        self.assert_tile(self.launch("mine", claude=False), AGENT_WS)
        s = state(AGENT_WS)
        self.assertEqual((s["focus"], s["shown"], s["tabs"]), ("mine", "a1", ["a1", "a2"]))


@unittest.skipUnless(IN_SANDBOX, "opens windows: only inside nightdrive sandbox (nightdrive sandbox exec python3 …)")
class AgentsWindow(unittest.TestCase):
    """A new window showing a background PM with `claude agents` (#3200): its claude has no record and the session runs
    under no window, so claude-sessions gave it no name and the bar never told pm-space it is a PM. Through
    claude-sessions, as Claude.qml's pmKey reads it, it now moves off a crowded workspace to a space of its own."""

    NAME = "Test Agents Project Manager"

    def setUp(self):
        taken = [c["title"] for c in clients() if c["workspace"].get("id") == AGENTS_WS]
        if taken:
            self.skipTest(f"workspace {AGENTS_WS} isn't empty: {taken}")
        self.addCleanup(BackgroundSession.tearDownClass)
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = tmp.name
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(os.path.join(self.home, ".claude", "sessions"))
        # The daemon's session: under no window, its record named and kind bg, as Claude Code writes it
        bg = subprocess.Popen(["sleep", "600"], cwd=self.tmp)
        self.addCleanup(bg.wait)
        self.addCleanup(bg.kill)
        with open(f"/proc/{bg.pid}/stat") as f:
            start = f.read().rsplit(") ", 1)[1].split()[19]
        with open(os.path.join(self.home, ".claude", "sessions", f"{bg.pid}.json"), "w") as f:
            json.dump({"pid": bg.pid, "name": self.NAME, "kind": "bg", "cwd": self.tmp, "procStart": start,
                       "sessionId": "00000000-0000-4000-8000-000000000000", "status": "idle"}, f)
        self.bg = bg.pid
        # `claude agents`: a process named claude (a script's name is its process's), with no record
        self.agents = os.path.join(self.tmp, "claude")
        with open(self.agents, "w") as f:
            f.write("#!/bin/sh\nsleep 600\n")
        os.chmod(self.agents, 0o755)

    def agents_window(self):
        """The terminal running it on AGENTS_WS, titled as Claude Code titles the session it shows."""
        hyprctl("dispatch", f'hl.dsp.exec_cmd("kitty -T \'✳ {self.NAME}\' {self.agents} agents", '
                            f'{{ workspace = "{AGENTS_WS} silent" }})')
        for _ in range(80):
            win = next((c for c in clients() if c["title"] == "✳ " + self.NAME), None)
            if win:
                self.addCleanup(os.kill, win["pid"], signal.SIGTERM)
                time.sleep(SETTLE)
                return win["address"]
            time.sleep(0.1)
        raise AssertionError("the agents window didn't open")

    def test_gets_a_space_of_its_own(self):
        open_window("other", "beside", AGENTS_WS)
        pm = self.agents_window()
        env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE")}
        env["HOME"] = self.home
        out = subprocess.run([CLAUDE_SESSIONS], env=env, capture_output=True, text=True, timeout=30, check=True).stdout
        found = next((s for s in json.loads(out) if s["address"] == pm), None)
        self.assertIsNotNone(found, f"claude-sessions didn't list the window: {out}")
        self.assertEqual((found["name"], found["pid"], found["dir"]), (self.NAME, self.bg, self.tmp))
        # Claude.qml's pmKey: the PMs among them, by name
        pms = [s for s in json.loads(out) if PM_NAME.search(s["name"])]
        self.assertIn(pm, [s["address"] for s in pms], "not a PM by its name")
        hyprctl("eval", "NightdrivePmSpaces({ " + ", ".join(f'{{ a = "{s["address"]}", n = "{s["name"]}" }}' for s in pms) + " })")
        time.sleep(SETTLE)
        win = next(c for c in clients() if c["address"] == pm)
        ws = win["workspace"]["id"]
        self.assertNotEqual(ws, AGENTS_WS, "the PM stayed on a crowded workspace")
        self.assertEqual([c["title"] for c in clients() if c["workspace"]["id"] == ws], ["✳ " + self.NAME],
                         "the PM's new workspace isn't its own")


if __name__ == "__main__":
    unittest.main()
