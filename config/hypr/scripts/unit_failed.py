"""When a Nightdrive service keeps failing, one notification (#3313). A timer's service that fails shows nowhere but the
journal: Calendar's reminders failed every minute for four days before anyone saw (#3309). Each such unit has
`OnFailure=nightdrive-unit-failed@%n.service`, which runs `unit-failed UNIT` after every failure; this decides whether
it is worth a notification.

- A failure counts toward a streak; a successful run after the streak's last failure (the journal's "Finished" for the
  unit) ends it, so only failures in a row count.
- FAILS in a row before the notification, then at most one per unit per QUIET: a unit failing every minute gets one a
  day, not one a minute.
- A unit that waits for the network (After=network-online.target: the syncs) doesn't count a failure while this computer
  is offline, and its streak must also have lasted NETWORK_AGE: a sync on a train or a server's short outage stays quiet.

The state is a small JSON file: {unit: {count, since, last, notified}}, times in Unix seconds.
"""

import contextlib
import fcntl
import json
import os
import subprocess
import time

FAILS = 3                    # failures in a row before the notification
NETWORK_AGE = 2 * 3600       # and, for a unit that needs the network, the streak's age
QUIET = 24 * 3600            # at most one notification per unit per this
FORGET = 7 * 24 * 3600       # a unit that hasn't failed for this long is dropped from the state
# The user manager's "Finished UNIT" (job done) message: a successful run (sd-messages.h SD_MESSAGE_UNIT_STARTED)
FINISHED = "39f53479d3a045ac8e11786248231fbf"
JOURNAL = ["journalctl", "--user", "--no-pager", "-o", "json"]


def state_path():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return os.path.join(base, "nightdrive", "unit-failed.json")


def load(path=None):
    try:
        with open(path or state_path(), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save(state, path=None):
    path = path or state_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


@contextlib.contextmanager
def locked(path=None):
    """Two units failing at once each run a handler: one at a time reads and writes the state."""
    path = path or state_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".lock", "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def record(entry, now, last_ok, counted):
    """The unit's entry after a failure at `now`. last_ok: its newest successful run (None: not known). counted: False
    for a network unit while offline, which neither counts nor starts a streak."""
    e = dict(entry or {})
    if e.get("last") and last_ok and last_ok > e["last"]:
        e.pop("count", None), e.pop("since", None)     # it worked in between: a new streak
    if counted:
        e["count"] = e.get("count", 0) + 1
        e.setdefault("since", now)
        e["last"] = now
    return e


def due(entry, now, network):
    """Whether this failure gets the notification."""
    if entry.get("count", 0) < FAILS:
        return False
    if network and now - entry.get("since", now) < NETWORK_AGE:
        return False
    return "notified" not in entry or now - entry["notified"] >= QUIET


def prune(state, now):
    return {u: e for u, e in state.items()
            if now - max(e.get("last", 0), e.get("notified", 0)) < FORGET}


def _run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _entries(text):
    out = []
    for line in text.splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def last_success(unit):
    """When the unit last finished well, from the journal (Unix seconds), or None."""
    for e in _entries(_run(JOURNAL + ["-u", unit, "MESSAGE_ID=" + FINISHED, "-n", "1", "-r"])):
        try:
            return int(e["__REALTIME_TIMESTAMP"]) / 1e6
        except (KeyError, ValueError):
            pass
    return None


def last_error(unit):
    """The unit's own last line of output (a Python error's last line, say), not systemd's lines about it."""
    for e in _entries(_run(JOURNAL + ["-u", unit, "-n", "40", "-r"])):
        msg = e.get("MESSAGE")
        if e.get("MESSAGE_ID") or e.get("SYSLOG_IDENTIFIER") == "systemd" or not isinstance(msg, str):
            continue
        if msg.strip():
            return msg.strip()[:200]
    return ""


def show(unit, prop):
    return _run(["systemctl", "--user", "show", "-p", prop, "--value", unit]).strip()


def needs_network(unit):
    return "network-online.target" in show(unit, "After").split()


def online():
    """NetworkManager's connectivity; without it (or when it can't tell: checking off), an IPv4 default route."""
    state = _run(["nmcli", "-t", "-f", "CONNECTIVITY", "general"]).strip()
    if state in ("full", "limited", "portal", "none"):
        return state == "full"
    try:
        with open("/proc/net/route") as f:
            return any(len(c) > 1 and c[1] == "00000000" for c in (line.split() for line in f))
    except OSError:
        return False


def when(ts, now):
    t, today = time.localtime(ts), time.localtime(now)
    return time.strftime("%H:%M" if t[:3] == today[:3] else "%-d.%-m. %H:%M", t)


def message(unit, entry, now, description, error):
    """(summary, body) of the notification."""
    name = description or unit
    body = f"Failed {entry['count']} times in a row since {when(entry['since'], now)}."
    if error:
        body += f"\n{error}"
    body += f"\nThe log: journalctl --user -u {unit}"
    return f"{name} keeps failing", body
