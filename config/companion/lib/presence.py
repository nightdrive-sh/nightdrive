"""Whether you are at the computer or away (protocol.md › State, "presence"): away, a tap on a session's tile opens its
own view on the page instead of bringing its window up on a computer nobody is looking at.

Away is the session locked (the lock that hypr/scripts/lock starts: greeter/lock.qml, or hyprlock in its place), or no
input for IDLE_LIMIT. The idle time is logind's: hypridle sets the session's IdleHint a minute after the last input
(hypr/hypridle.conf, as Ferry reads it), and IdleSinceHint says when. Companion's own keys and focus go through
hyprctl dispatch, not through an input device, so they don't count as you being there.

You can also say it yourself from the page (POST /api/presence): that holds until the computer sees a change of its own
(you lock it, leave it, or come back to it), so a choice made once can't stay wrong for the rest of the day.
"""
import json
import os
import subprocess
import time

IDLE_LIMIT = 300           # seconds without input before you count as away
IDLE_AFTER = 60            # hypridle sets IdleHint this long after the last input (hypridle.conf's first listener)
LOCKS = (["-f", "[q]s -p .*/greeter/lock\\.qml"], ["-x", "hyprlock"])
# Where hypr/scripts/claude-notify reads it (#3065): away, a request waits for Companion even in the active window
STATE_FILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "nightdrive", "presence.json")


def _run(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def idle_seconds(show_session, now):
    """Seconds since the last input from `loginctl show-session -p IdleHint -p IdleSinceHint` (0: in use), or None when
    logind doesn't know (a desktop that never sets the hint)."""
    v = dict(line.split("=", 1) for line in show_session.splitlines() if "=" in line)
    try:
        since = int(v.get("IdleSinceHint") or 0) / 1e6
    except ValueError:
        return None
    if not since:
        return None
    if v.get("IdleHint") != "yes":
        return 0
    return max(0, int(now - since + IDLE_AFTER))


def _idle():
    sid = _run(["loginctl", "show-user", str(os.getuid()), "-p", "Display", "--value"]).strip()
    if not sid:
        return None
    return idle_seconds(_run(["loginctl", "show-session", sid, "-p", "IdleHint", "-p", "IdleSinceHint"]), time.time())


def _locked():
    """The lock is up: only this session's processes (a sandbox container's runs as the same user), as lock does."""
    mine = ["pgrep", "--ns", str(os.getpid()), "--nslist", "pid", "-u", str(os.getuid())]
    return any(_run(mine + match).strip() for match in LOCKS)


def detect(idle=_idle, locked=_locked):
    """The computer's own view: "locked", "idle" or "" (at the computer)."""
    if locked():
        return "locked"
    s = idle()
    return "idle" if s is not None and s >= IDLE_LIMIT else ""


class Presence:
    """Detected, or as you set it on the page until the computer sees a change of its own."""

    def __init__(self, detect=detect):
        self.detect = detect
        self.set_to = None         # True / False: what you said; None: as detected
        self.set_at = None         # what the computer said then: the choice holds while it says the same

    def look(self):
        why = self.detect()
        if self.set_to is not None and why != self.set_at:
            self.set_to = None
        if self.set_to is not None:
            return {"away": self.set_to, "why": "set", "set": True}
        return {"away": bool(why), "why": why, "set": False}

    def set(self, away):
        if not isinstance(away, bool):
            raise ValueError("away is true or false")
        self.set_at = self.detect()
        # the same as detected: nothing to hold
        self.set_to = None if away == bool(self.set_at) else away


def start_time(pid):
    """The process's start in clock ticks since boot (/proc/PID/stat's 22nd field), or 0: with the pid it names this
    server's own run, so a pid reused after a crash doesn't pass for it."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            return int(f.read().rsplit(")", 1)[1].split()[19])
    except (OSError, IndexError, ValueError):
        return 0


class StateFile:
    """The presence for claude-notify: written (atomically) when it changes while a page watches, and gone when none
    does, as nothing looks then and it would go stale. The hook trusts it only while this process runs (pid, start)."""

    def __init__(self, path=STATE_FILE, pid=None):
        self.path = path
        self.pid = pid or os.getpid()
        self.start = start_time(self.pid)
        self.last = ""           # not None: the first remove() clears one an earlier run left behind

    def write(self, look):
        text = json.dumps({"away": bool(look.get("away")), "why": look.get("why", ""), "pid": self.pid,
                           "start": self.start}) + "\n"
        if text == self.last:
            return
        tmp = f"{self.path}.{self.pid}.tmp"
        try:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            with open(tmp, "w") as f:
                f.write(text)
            os.replace(tmp, self.path)
            self.last = text
        except OSError as e:     # the page works without it; the hook then goes by the window as before
            print("companion: presence file:", e, flush=True)

    def remove(self):
        if self.last is None:
            return
        self.last = None
        try:
            os.unlink(self.path)
        except OSError:
            pass


class Demo(Presence):
    """At the computer until you say otherwise: nothing is detected in the demo."""

    def __init__(self):
        super().__init__(detect=lambda: "")
