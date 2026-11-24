"""One Open or Save window for portal.py: Files' picker (app/picker.qml) in a Quickshell process of its own.

Its own process, not a window of the Files the user has open: a picker that fails takes none of their windows with it,
and its end is plain to see (the process exits). The request goes to it as request.json in a folder of its own under
$XDG_RUNTIME_DIR, and the answer comes back as answer.json there before it quits; a process that ends without one
failed. It writes ready there once its window is made: without that in READY_S the picker counts as failed too, and is
stopped (portal.py then gives the request to GTK's window). Its window floats over the app that asked, as a dialog
does: config/hypr/picker-windows.lua puts it there as it maps, and place() does it afterwards where that isn't loaded.
"""
import json
import os
import shutil
import subprocess
import tempfile

from gi.repository import GLib

APP_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")
PICKER_QML = os.path.join(APP_DIR, "picker.qml")
POLL_MS = 120                 # how often to look for the window while it comes up
READY_S = float(os.environ.get("FILES_PICK_READY_S", 5))   # the picker's window comes in this time, or GTK's takes
                                                            # the request (a test makes it shorter)
PLACE_S = 3                   # after ready, how long Hyprland may take to map the window before it isn't placed
SIZE = (1000, 680)            # the picker's size at most; less over a smaller app, never under MIN
MIN = (420, 360)
MARGIN = 40                   # the app shows this much around the picker, where it has room


def hyprctl_json(*args):
    try:
        return json.loads(subprocess.run(["hyprctl", "-j", *args], capture_output=True, text=True, timeout=2).stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def dispatch(expr):
    subprocess.run(["hyprctl", "dispatch", expr], capture_output=True, timeout=2)


def geometry(caller, monitor):
    """Where the picker goes: centred over the app that asked (caller: x, y, w, h), or the screen when there is none.

    The picker is as large as SIZE, but no larger than the app less MARGIN on each side, and never under MIN."""
    x, y, w, h = caller or monitor
    pw = max(MIN[0], min(SIZE[0], w - 2 * MARGIN))
    ph = max(MIN[1], min(SIZE[1], h - 2 * MARGIN))
    return x + (w - pw) // 2, y + (h - ph) // 2, pw, ph


class Picker:
    def __init__(self, req, done):
        self.req = req
        self.done = done              # done(answer): a dict, or None when the picker failed
        self.pid = 0
        self.poll = None
        self.late = None
        self.ready = 0                # when it said it was ready (monotonic seconds), 0 before
        self.placed = False
        self.finished = False
        self.hypr = bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")) and shutil.which("hyprctl") is not None
        base = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
        os.makedirs(os.path.join(base, "nightdrive"), exist_ok=True)
        self.dir = tempfile.mkdtemp(prefix="picker-", dir=os.path.join(base, "nightdrive"))
        # The app's window, asked for now: it has the keyboard as it asks
        self.caller = self._active()

    def _active(self):
        if not self.hypr:
            return None
        w = hyprctl_json("activewindow")
        if not w or not w.get("address"):
            return None
        return {"at": tuple(w["at"]) + tuple(w["size"]), "workspace": w["workspace"]["id"], "monitor": w["monitor"]}

    def start(self):
        with open(os.path.join(self.dir, "request.json"), "w") as f:
            json.dump(self.req, f)
        env = dict(os.environ, FILES_PICK=self.dir)
        try:
            self.pid, *_ = GLib.spawn_async(["qs", "-p", PICKER_QML], envp=[f"{k}={v}" for k, v in env.items()],
                                            flags=GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD)
        except GLib.Error:
            self._finish(None)
            return
        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, self.pid, self._exited)
        self.poll = GLib.timeout_add(POLL_MS, self._look)
        self.late = GLib.timeout_add(int(READY_S * 1000), self._too_late)

    def stop(self):
        """The request is over before the picker answered (Request.Close): it goes, and says nothing."""
        self.finished = True
        self._kill()

    def _look(self):
        """Whether the picker is ready, and its window, once Hyprland has mapped it: placed over the app that asked."""
        if self.finished:
            self.poll = None
            return False
        now = GLib.get_monotonic_time() / 1e6
        if not self.ready and os.path.exists(os.path.join(self.dir, "ready")):
            self.ready = now
        if self.hypr and not self.placed:
            for c in hyprctl_json("clients") or []:
                if c.get("pid") == self.pid and c.get("mapped", True):
                    # Floating already: Hyprland's picker-windows.lua placed it as it mapped. Else (a desktop without
                    # that file) it is placed now, after its first frame as a tile
                    if not c.get("floating"):
                        self.place(c["address"])
                    self.placed = True
                    self.ready = self.ready or now
        if self.ready and (self.placed or not self.hypr or now - self.ready > PLACE_S):
            self.poll = None
            return False
        return True

    def _too_late(self):
        """No window in READY_S: the picker is stopped and counts as failed."""
        self.late = None
        if not self.ready and not self.finished:
            print(f"portal: Files' picker didn't come up in {READY_S:g} s.", flush=True)
            self._finish(None)
            self._kill()
        return False

    def _kill(self):
        if self.pid:
            try:
                os.kill(self.pid, 15)
            except ProcessLookupError:
                pass

    def place(self, address):
        mon = None
        for m in hyprctl_json("monitors") or []:
            if m.get("focused"):
                left, top, right, bottom = (m.get("reserved") or [0, 0, 0, 0])[:4]   # the bar's room
                mon = (m["x"] + left, m["y"] + top, int(m["width"] / m["scale"]) - left - right,
                       int(m["height"] / m["scale"]) - top - bottom)
        x, y, w, h = geometry(self.caller["at"] if self.caller else None, mon or (0, 0, *SIZE))
        win = f'"address:{address}"'
        dispatch(f'hl.dsp.window.float({{ action = "enable", window = {win} }})')
        dispatch(f"hl.dsp.window.resize({{ x = {w}, y = {h}, exact = true, window = {win} }})")
        dispatch(f"hl.dsp.window.move({{ x = {x}, y = {y}, exact = true, window = {win} }})")
        # A picker an agent's test started (CLAUDECODE, AGENTS.md) leaves the keyboard where it is, as its windows do
        if not os.environ.get("CLAUDECODE"):
            dispatch(f"hl.dsp.focus({{ window = {win} }})")

    def _exited(self, pid, _status):
        GLib.spawn_close_pid(pid)
        self.pid = 0
        for source in (self.poll, self.late):
            if source:
                GLib.source_remove(source)
        self.poll = self.late = None
        answer = None
        try:
            with open(os.path.join(self.dir, "answer.json")) as f:
                answer = json.load(f)
        except (OSError, ValueError):
            pass
        self._finish(answer)

    def _finish(self, answer):
        shutil.rmtree(self.dir, ignore_errors=True)
        if self.finished:
            return
        self.finished = True
        self.done(answer)
