"""Nightdrive's iOS app as the computer's microphone (Dashboard #3173, protocol.md › The microphone).

With the lid closed the built-in microphone hears nothing. The app, open in front, says it is ready (POST /api/mic,
every few seconds while its page is shown); the computer's dictation key (hypr/scripts/dictate) then asks this server,
over a socket of the user's alone (mic_socket.py), to start and stop it. The app listens with its own speech
recognition and sends back the words, which dictate puts where Voxtype's would have gone.

A command reaches the app only on its own event stream (GET /api/events?mic=DEVICE), which only the machine's own
Tailscale user can open (access.py), and the app shows that it listens.

The server keeps the state of a dictation in STATE_FILE for the desktop's toast (quickshell/Dictation.qml), and as the
sign to dictate's stop that this dictation is the app's: `waiting NAME`, `listening NAME`, `transcribing NAME`;
gone when it ends.
"""
import itertools
import os
import re
import threading
import time

from access import RUNTIME

LID = os.path.join(RUNTIME, "nightdrive-lid")        # hypr/scripts/lid: open | closed
STATE_FILE = os.path.join(RUNTIME, "dictate-remote")
READY_FOR = 25      # seconds a ready holds without another: the page says it every 10 s while it is shown
START_WAIT = 2.5    # seconds a start waits for the app to listen; then the computer's own microphone
TEXT_WAIT = 8       # seconds a stop waits for the app's last words
MAX_TEXT = 20000    # characters of words taken back
DEVICE = re.compile(r"^[A-Za-z0-9-]{8,64}$")


class MicError(Exception):
    pass


def lid_closed(path=LID):
    try:
        with open(path) as f:
            return f.read().strip() == "closed"
    except OSError:
        return False


def device_id(value):
    """A page's id for itself (random, per load), or None when it isn't one."""
    return value if isinstance(value, str) and DEVICE.match(value) else None


def device_name(value):
    """What the app calls its device (iPad, iPhone), shown on the desktop: short and plain."""
    name = re.sub(r"[^\w .-]", "", value if isinstance(value, str) else "")[:24].strip()
    return name or "the app"


class Mic:
    """The ready apps and the one dictation at a time. cond is the server's: a stream waits on it for its state and its
    commands, and a start or stop waits on it for the app's answer."""

    def __init__(self, cond, state_file=STATE_FILE, clock=time.monotonic):
        self.cond = cond
        self.state_file = state_file
        self.clock = clock
        # device → {"name", "seen" (its last ready), "stream": its newest event stream (an older one may be a dead
        # connection iOS left open, which would swallow a command)}
        self.devices = {}
        self.streams = itertools.count(1)
        self.commands = {}      # device → commands its stream hasn't sent yet
        self.ids = itertools.count(1)
        self.current = None     # {"id", "device", "name", "started", "done", "text", "error"}

    # From the page (server.py): its stream, its ready, its events

    def _device(self, device):
        return self.devices.setdefault(device, {"name": "", "seen": None, "stream": None})

    def open(self, device):
        """A stream of this device's opened: it is the one that gets its commands from now on. Returns its token."""
        with self.cond:
            token = next(self.streams)
            self._device(device)["stream"] = token
            return token

    def close(self, device, token):
        with self.cond:
            d = self._device(device)
            if d["stream"] == token:
                d["stream"] = None
                self.commands.pop(device, None)

    def ready(self, device, name, on):
        with self.cond:
            d = self._device(device)
            d["name"], d["seen"] = device_name(name), self.clock() if on else None

    def _newest(self, device, token):
        return bool(device) and device in self.devices and self.devices[device]["stream"] == token

    def take(self, device, token):
        """The commands for this stream, once, if it is its device's newest (call with cond held)."""
        return self.commands.pop(device, []) if self._newest(device, token) else []

    def pending(self, device, token):
        return self._newest(device, token) and bool(self.commands.get(device))

    def event(self, device, mic_id, kind, text="", error=""):
        """The app's answer about the dictation it was given: started, error, or text (its words, last)."""
        with self.cond:
            cur = self.current
            if not cur or cur["device"] != device or cur["id"] != mic_id:
                raise ValueError("Not the dictation going on")
            if kind == "started":
                cur["started"] = True
                self._write(f"listening {cur['name']}")
            elif kind == "error":
                cur["error"] = str(error)[:80] or "error"
            elif kind == "text":
                cur["text"] = str(text or "")[:MAX_TEXT]
                cur["done"] = True
            else:
                raise ValueError("No such event")
            self.cond.notify_all()

    # From the dictation key (mic_socket.py)

    def available(self):
        """The ready app to use: the one ready most recently, with its stream open; None when there is none."""
        with self.cond:
            now = self.clock()
            ready = [(d["seen"], dev) for dev, d in self.devices.items()
                     if d["stream"] and d["seen"] is not None and now - d["seen"] < READY_FOR]
            return max(ready)[1] if ready else None

    def start(self, wait=START_WAIT):
        """Tells the ready app to listen and waits until it does: {"id", "name"}. MicError when there is none, or it
        didn't start in time (it went to the background and its stream is a dead one)."""
        device = self.available()
        if not device:
            raise MicError("No app is ready")
        with self.cond:
            if self.current:
                self._send(self.current["device"], "abort", self.current["id"])
            name = self.devices[device]["name"]
            cur = self.current = {"id": next(self.ids), "device": device, "name": name, "started": False,
                                  "done": False, "text": "", "error": ""}
            self._write(f"waiting {name}")
            self._send(device, "start", cur["id"])
            self.cond.wait_for(lambda: cur["started"] or cur["done"] or cur["error"] or self.current is not cur,
                               timeout=wait)
            if self.current is cur and cur["started"]:
                return {"id": cur["id"], "name": name}
            why = cur["error"] or "the app didn't start listening"
            if self.current is cur:
                self._send(device, "abort", cur["id"])
                self._end()
            raise MicError(why)

    def stop(self, mic_id=None, wait=TEXT_WAIT):
        """Let go: the app stops, and its words come back ("" when none came in time). Without an id, the one going
        on: the key may be let go while start still waits."""
        with self.cond:
            cur = self.current
            if not cur or (mic_id is not None and cur["id"] != mic_id):
                return ""
            self._write(f"transcribing {cur['name']}")
            self._send(cur["device"], "stop", cur["id"])
            self.cond.wait_for(lambda: cur["done"] or self.current is not cur, timeout=wait)
            if self.current is cur:
                self._end()
            return cur["text"]

    def abort(self):
        with self.cond:
            if self.current:
                self._send(self.current["device"], "abort", self.current["id"])
                self._end()

    # Inside, with cond held

    def _send(self, device, op, mic_id):
        self.commands.setdefault(device, []).append({"op": op, "id": mic_id})
        self.cond.notify_all()

    def _end(self):
        self.current = None
        try:
            os.unlink(self.state_file)
        except FileNotFoundError:
            pass
        self.cond.notify_all()

    def _write(self, text):
        tmp = self.state_file + ".tmp"
        with open(tmp, "w") as f:
            f.write(text + "\n")
        os.replace(tmp, self.state_file)    # whole, for the toast that watches it
