"""One-shot wall-clock timers kept over a logout: the base that `remind` (#3118) and `schedule` (#3121) share, so the two
don't each grow their own copy of it.

- Times as the commands take them: minutes (15, 90m, 1h30m), a time of day (22:45, 22.45: the next one), @UNIX.
- A state file of rows ({id, at, …}) read and written under a lock: a timer's own run may land while another adds one.
- Each row's timer is a transient systemd user timer on the wall clock (in UTC, so a time zone change doesn't move it),
  so a suspend doesn't push it later: one that came due while asleep goes as the computer wakes. Such a timer goes with
  the user's systemd at logout (no lingering) and at a reboot: the state file is what the caller arms again at login.

Imported by the scripts beside it (sys.path gets this folder, as net-watch does with net_watch_rules.py).
"""
import contextlib, datetime, fcntl, json, os, re, subprocess


def clock_time(text, now):
    """22:45 or 22.45 (also 9:05) → the next such moment as Unix time: today's, or tomorrow's once it has passed.
    None when it isn't one. Counted on the calendar, not as 24 h, so a daylight saving change keeps the clock time."""
    m = re.fullmatch(r"([01]?\d|2[0-3])[:.]([0-5]\d)", str(text).strip())
    if not m:
        return None
    today = datetime.datetime.fromtimestamp(now)
    at = today.replace(hour=int(m.group(1)), minute=int(m.group(2)), second=0, microsecond=0)
    if at.timestamp() <= now:
        at = (today + datetime.timedelta(days=1)).replace(hour=at.hour, minute=at.minute, second=0, microsecond=0)
    return int(at.timestamp())


def parse_minutes(text, most):
    """15, 15m, 2h, 1h30m, 1h 30m → minutes; None when it isn't one or is outside 1…most."""
    t = re.sub(r"\s+", "", str(text).lower())
    if re.fullmatch(r"\d+", t):
        n = int(t)
    else:
        m = re.fullmatch(r"(?:(\d+)h)?(?:(\d+)m(?:in)?)?", t)
        if not m or not (m.group(1) or m.group(2)):
            return None
        n = int(m.group(1) or 0) * 60 + int(m.group(2) or 0)
    return n if 1 <= n <= most else None


def when(text, now, most):
    """WHEN (@UNIX, a time of day, minutes) → Unix time, or None. most: the furthest ahead, in minutes. @UNIX is the
    undo of a cancel (the same moment again), so it must be still to come and within that reach too."""
    if re.fullmatch(r"@\d+", str(text)):
        at = int(text[1:])
        return at if now < at <= now + most * 60 else None
    at = clock_time(text, now)
    if at is not None:
        return at
    minutes = parse_minutes(text, most)
    return None if minutes is None else now + minutes * 60


def clock(ts):
    return datetime.datetime.fromtimestamp(ts).strftime("%H:%M")


def iso(ts):
    return datetime.datetime.fromtimestamp(ts).astimezone().isoformat(timespec="seconds")


def minutes_left(ts, now):
    return max(0, int((ts - now + 59) // 60))


@contextlib.contextmanager
def locked_rows(path, key):
    """The rows under `key` in the JSON file at `path`, as a list to change in place; written back (atomically) only
    if it changed. A missing or broken file is an empty list, and a row without an id or a numeric at is dropped."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(path) as f:
                rows = json.load(f).get(key, [])
        except (OSError, ValueError, AttributeError):
            rows = []
        rows = [r for r in rows if isinstance(r, dict) and r.get("id") and isinstance(r.get("at"), (int, float))]
        before = json.dumps(rows)
        yield rows
        if json.dumps(rows) != before:
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                json.dump({key: rows}, f, ensure_ascii=False, indent=1)
            os.replace(tmp, path)


def systemctl(*args):
    return subprocess.run(["systemctl", "--user", *args], capture_output=True, text=True)


def armed(unit):
    return systemctl("is-active", "--quiet", unit + ".timer").returncode == 0


def arm(unit, at, description, command):
    """A timer named unit.timer that runs `command` (a list) at Unix time `at`. → (ok, error text)."""
    stamp = datetime.datetime.fromtimestamp(at, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    p = subprocess.run(["systemd-run", "--user", "--quiet", "--collect", "--unit", unit,
                        "--on-calendar", stamp, "--timer-property=AccuracySec=1s", "--timer-property=Persistent=false",
                        "--description", description, "--", *command],
                       capture_output=True, text=True)
    return p.returncode == 0, p.stderr.strip()


def disarm(unit):
    systemctl("stop", unit + ".timer")
