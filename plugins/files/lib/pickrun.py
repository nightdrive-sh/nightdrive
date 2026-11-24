"""One Open or Save window for portal.py: Files' picker (app/picker.qml) in a Quickshell process of its own.

Its own process, not a window of the Files the user has open: a picker that fails takes none of their windows with it,
and its end is plain to see (the process exits). The request goes to it as request.json in a folder of its own under
$XDG_RUNTIME_DIR, and the answer comes back as answer.json there before it quits; a process that ends without one
failed. Once its window is up it floats over the app that asked, as a dialog does (place()).
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
        self.finished = False
        base = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
        os.makedirs(os.path.join(base, "nightdrive"), exist_ok=True)
        self.dir = tempfile.mkdtemp(prefix="picker-", dir=os.path.join(base, "nightdrive"))
        # The app's window, asked for now: it has the keyboard as it asks
        self.caller = self._active()

    def _active(self):
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

    def stop(self):
        """The request is over before the picker answered (Request.Close): it goes, and says nothing."""
        self.finished = True
        if self.pid:
            try:
                os.kill(self.pid, 15)
            except ProcessLookupError:
                pass

    def _look(self):
        """The picker's window, once it is mapped: placed over the app that asked."""
        if self.finished:
            return False
        for c in hyprctl_json("clients") or []:
            if c.get("pid") == self.pid and c.get("mapped", True):
                self.place(c["address"])
                self.poll = None
                return False
        return True

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
        if self.poll:
            GLib.source_remove(self.poll)
            self.poll = None
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
