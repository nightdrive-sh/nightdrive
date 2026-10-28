"""The code a sender types before it may send (LocalSend's PIN): shown in the middle of the screen (CodeDialog.qml), so
only someone who can see this computer can send to it. Anyone on the network could otherwise show an Accept/Decline
under any name, the phone's own included, or put a text in a notification.

LocalSend's sending app knows the flow: a prepare-upload without the PIN gets 401, and the app asks its user for it and
sends again with ?pin=. It doesn't remember a PIN, so each send asks: the code is a new one each time, and typing it is
the Accept (receiver.prepare). The phone shows "too many attempts" on 429 and "busy" on 409."""
import os
import secrets
import subprocess
import threading
import time

DIGITS = 6
TTL = 120          # seconds a code is good for: CodeDialog's own timeout
TRIES = 3          # wrong codes before the code is dropped (and the sender has to wait)
REST = 60          # seconds a sender waits after 3 wrong codes or a code it let expire: no one can keep opening the card
RESHOW = 10        # seconds before the same sender opens the card again (it was closed and the phone asked again)


class Codes:
    """One code at a time, for one sender's address."""

    def __init__(self):
        self.lock = threading.Lock()
        self.ip, self.code, self.until, self.shown, self.tries = None, "", 0.0, 0.0, 0
        self.resting = {}       # address → when it may ask again (time.monotonic)

    def check(self, ip, pin, what):
        """A prepare-upload from ip with pin ("" without one): "ok" (the right code), "ask" (401, the card shows the
        code), "busy" (409: another sender's code is up) or "wait" (429)."""
        now = time.monotonic()
        show = False
        with self.lock:
            if self.ip and now > self.until:
                self._drop(rest=True)
            self.resting = {a: t for a, t in self.resting.items() if t > now}
            if ip in self.resting:
                return "wait"
            if self.ip and self.ip != ip:
                return "busy"
            if self.ip == ip and pin:
                if secrets.compare_digest(pin.encode(), self.code.encode()):   # bytes: a str must be ASCII
                    self._drop()
                    hide()
                    return "ok"
                self.tries += 1
                if self.tries >= TRIES:
                    self._drop(rest=True)
                    hide()
                    return "wait"
                return "ask"
            if self.ip == ip:
                show = now - self.shown > RESHOW
            else:
                # A new code (also for a PIN sent when none was up: an old one, the phone asks again)
                self.ip, self.tries, self.until = ip, 0, now + TTL
                self.code = f"{secrets.randbelow(10 ** DIGITS):0{DIGITS}d}"
                show = True
            if show:
                self.shown = now
            code = self.code
        if show:
            qs("open", "smartphone", "LocalSend", code, f"{what}. Type this code in LocalSend there.")
        return "ask"

    def cancel(self, ip):
        """The sender gave up: the card goes, the code stays good (it may try again at once)."""
        with self.lock:
            mine = self.ip == ip
        if mine:
            hide()

    def _drop(self, rest=False):
        if rest:
            self.resting[self.ip] = time.monotonic() + REST
        self.ip, self.code = None, ""


def hide():
    qs("close")


def qs(*a):
    # qs ipc only finds a Quickshell with the same QT_QPA_PLATFORM as its own: Hyprland sets it, the service has none
    env = dict(os.environ, QT_QPA_PLATFORM=os.environ.get("QT_QPA_PLATFORM") or "wayland;xcb")
    subprocess.Popen(["qs", "ipc", "call", "code", *a], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
