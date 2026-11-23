"""`places check`: notices arriving at and leaving places (Dashboard #3277) and tells Remind and Schedule. The rules are
place_rules.py's; this file keeps their state, arms the timer for a pending leaving, and runs the events.

Who calls it: net-watch, when the active connections change and at sleep and waking (--sleep, --wake); autostart.lua at
login (--wake: the computer may have been shut down elsewhere) and at each unlock; and its own leave timer.

- The state is ~/.local/state/nightdrive/places-seen.json (place → here, last_seen, missing_since), changed under a lock:
  net-watch may start two checks at once. The events run after the lock is let go, so a slow one holds no other check.
- A pending leaving gets a transient systemd timer (timers.arm) that runs `places check` again at its moment. Its unit
  has the moment in its name: the timer's own check arms the next one while its service still runs, and systemd won't
  start a unit of a name that is running. The one armed before is stopped, so only one waits.
- An event runs `remind event arrive work` and `schedule event arrive work` (#3278, #3279). A command that doesn't know
  `event` yet (its usage lists no such choice) is skipped, as is one that fails: said in the journal (tag
  nightdrive-places), never on screen, as a check runs in the background.
"""
import contextlib, fcntl, json, os, re, subprocess, syslog, time

import place_rules
import places
import timers

SCRIPTS = os.path.dirname(os.path.realpath(__file__))
TOLD = ("remind", "schedule")        # the commands an event goes to, in this order (scripts beside this one)
UNIT = "nightdrive-places-leave"     # the leave timer's units: UNIT-<unix time>
TAG = "nightdrive-places"            # the journal's tag (journalctl -t nightdrive-places)
RUN_TIMEOUT = 60                     # s for one command to take an event: a reminder shows itself and returns


def state_path():
    return os.path.expanduser("~/.local/state/nightdrive/places-seen.json")


def log(text):
    syslog.openlog(TAG)
    syslog.syslog(syslog.LOG_INFO, text)


@contextlib.contextmanager
def locked_state():
    """The state as a dict to change in place, under a lock; written back atomically. A missing or broken file is {}."""
    p = state_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(p) as f:
                state = json.load(f)
        except (OSError, ValueError):
            state = {}
        if not isinstance(state, dict):
            state = {}
        yield state
        tmp = p + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f, ensure_ascii=False, indent=1)
            f.write("\n")
        os.replace(tmp, p)


def knows_event(script):
    """Whether the command takes `event` (its argparse usage lists the choice): until #3278 and #3279 add it, a word
    it doesn't know would be read as a reminder's time or a command's (`remind event …`), so it isn't sent at all."""
    try:
        p = subprocess.run([script, "--help"], capture_output=True, text=True, timeout=RUN_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return bool(re.search(r"\{[^}]*\bevent\b[^}]*\}", p.stdout))


def tell(kind, name):
    """Runs the event in each command of TOLD. → [{command, ok, skipped}] (skipped: why it wasn't run, or None)."""
    out = []
    for cmd in TOLD:
        script = os.path.join(SCRIPTS, cmd)
        argv = [script, "event", kind, name]
        shown = [cmd, "event", kind, name]
        if not knows_event(script):
            log(f"{kind} {name}: {cmd} has no event command yet, skipped")
            out.append({"command": shown, "ok": False, "skipped": "no event command"})
            continue
        try:
            p = subprocess.run(argv, capture_output=True, text=True, timeout=RUN_TIMEOUT)
            ok, err = p.returncode == 0, p.stderr.strip()
        except (OSError, subprocess.TimeoutExpired) as e:
            ok, err = False, str(e)
        if not ok:
            log(f"{kind} {name}: {cmd} failed: {err}")
        out.append({"command": shown, "ok": ok, "skipped": None})
    return out


def arm(at):
    """The leave timer at `at` (None: none). → the unit armed, or None."""
    unit = f"{UNIT}-{int(at)}"
    # A second late: the check it runs must find the hold over, never a second short of it
    ok, err = timers.arm(unit, int(at) + 1, "Nightdrive: has this computer left a place?",
                         [os.path.join(SCRIPTS, "places"), "check"])
    if not ok:
        log(f"leave timer at {int(at)}: {err}")
        return None
    return unit


def check(event=None, now=None, wifi=None, arm=arm, disarm=timers.disarm, tell=tell):
    """One check. event: None, "sleep" or "wake". arm, disarm and tell are the tests' to replace.
    → {event, wifi, here, events: [{event, place}], next_check, ran: [{command, ok, skipped}]}"""
    now = int(time.time()) if now is None else now
    wifi = places.current_wifi() if wifi is None else wifi
    rows = places.load()
    with locked_state() as state:
        events, due = place_rules.step(state, rows, wifi, now, event)
        before = state.get("timer")
        unit = before
        if due is None or before != f"{UNIT}-{int(due)}":
            if before:
                disarm(before)
            unit = arm(due) if due is not None else None
        state["timer"] = unit
        here = place_rules.here(state)
    for kind, name in events:
        log(f"{kind} {name}")
    ran = [r for kind, name in events for r in tell(kind, name)]
    return {"event": event, "wifi": wifi, "here": here,
            "events": [{"event": k, "place": n} for k, n in events],
            "next_check": due, "ran": ran}


def text(result):
    """The check's result for a person: where it is, what happened."""
    lines = [f"{'Arrived at' if e['event'] == 'arrive' else 'Left'} {e['place']}" for e in result["events"]]
    lines.append("Here: " + (", ".join(result["here"]) or "no known place"))
    if result["next_check"]:
        lines.append("Checks again at " + timers.clock(result["next_check"]) + " (a place's network has gone)")
    return "\n".join(lines)
