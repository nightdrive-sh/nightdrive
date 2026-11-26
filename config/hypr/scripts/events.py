"""Events a reminder or a scheduled command can wait for in place of a time (Dashboard #3275): the WHEN grammar `remind`
and `schedule` share, beside timers.py (which keeps the times), so neither grows its own copy.

- WHEN as an event: wake (the first unlock after the computer next wakes), login (the next login), arrive PLACE and
  leave PLACE (a place of places.py: its Wi-Fi comes or goes; `places check` notices it and runs `… event arrive
  PLACE`). An unknown place is refused with the places there are, so a typo never waits for ever.
- --from WHEN: not before then (a time of day: the next one, minutes, @UNIX or an ISO date and time). "When I arrive at
  work in the morning", said in the evening, is `arrive work --from 05:00`: being at work already doesn't count.
- A row: {on, place?, from?, added}. An arrival may never come (a day at home): the row waits, and after WAIT_DAYS the
  caller asks about it (Schedule: Run or Skip; Jari 19.11.: it mustn't go quietly, nor fire on its own).

Imported by the scripts beside it (sys.path gets this folder, as with timers.py).
"""
import datetime, os, re, subprocess

import places
import timers

EVENTS = ("wake", "login", "arrive", "leave")
PLACED = ("arrive", "leave")       # the events that name a place
WAIT_DAYS = 7                      # an arrival or a leaving not seen in this long is asked about
FROM_MINUTES = 7 * 24 * 60         # --from at most a week ahead, as a time is
LOCKS = ("[q]s -p .*/greeter/lock\\.qml", "^hyprlock")   # the lock and its fallback (hypr/scripts/lock)


class WhenError(ValueError):
    """WHEN or --from can't be read: said for the user (the command prints it, Claude reads it)."""


def parse(text, rows=None):
    """WHEN → {on} or {on, place} when it is an event; None when it isn't one (a time, minutes: timers.when's).
    rows: the places (places.load() when None). WhenError: arrive or leave without a known place."""
    words = str(text).split(None, 1)
    if not words:
        return None
    on = words[0].lower()
    if on not in EVENTS:
        return None
    if on not in PLACED:
        if len(words) > 1:
            raise WhenError(f"{on} takes no place: {on} alone")
        return {"on": on}
    rows = places.load() if rows is None else rows
    name = words[1].strip() if len(words) > 1 else ""
    if not name:
        known = ", ".join(r["name"] for r in rows)
        raise WhenError(f"Which place: {on} PLACE" + (f" ({known})" if known else
                        ". There are no places yet: nightdrive places add NAME [SSID…]"))
    place = places.find(rows, name)
    if not place:
        raise WhenError(places.unknown(rows, name))
    return {"on": on, "place": place["name"]}


def parse_from(text, now):
    """--from WHEN → Unix time, still to come and within a week. WhenError when it isn't one."""
    t = str(text).strip()
    m = re.fullmatch(r"(\d{4}-\d\d-\d\d)[T ](\d\d?:\d\d)", t)
    if m:
        try:
            at = int(datetime.datetime.fromisoformat(f"{m.group(1)}T{m.group(2).zfill(5)}").timestamp())
        except ValueError:
            at = None
        if at is not None and not now < at <= now + FROM_MINUTES * 60:
            at = None
    else:
        at = timers.when(t, now, FROM_MINUTES)
    if at is None:
        raise WhenError("--from: a time of day (05:00: the next one), minutes (90m, 8h), or a date and time "
                        "(2026-11-23 05:00), still to come and within a week")
    return at


def row(event, now, start=None):
    """The fields an event row keeps: {on, place?, added, from?}."""
    return {**event, "added": now, **({"from": start} if start else {})}


def is_event(r):
    return isinstance(r.get("on"), str)


def label(r):
    """Short, as WHEN is typed: wake, login, arrive work."""
    return r["on"] + (" " + r["place"] if r.get("place") else "")


def day_clock(at, now):
    """05:00 today, 05:00 tomorrow, or Mon 23.11. 05:00."""
    days = (datetime.date.fromtimestamp(at) - datetime.date.fromtimestamp(now)).days
    day = {0: "today", 1: "tomorrow"}.get(days)
    return f"{timers.clock(at)} {day}" if day else datetime.datetime.fromtimestamp(at).strftime("%a %-d.%-m. %H:%M")


def describe(r, now=None):
    """For the list and the notifications: On arriving at work, not before 05:00 tomorrow."""
    text = {"wake": "On waking", "login": "At login", "arrive": "On arriving at " + str(r.get("place")),
            "leave": "On leaving " + str(r.get("place"))}[r["on"]]
    if r.get("from") and (now is None or now < r["from"]):
        text += ", not before " + (day_clock(r["from"], now) if now is not None else timers.clock(r["from"]))
    return text


def card_when(r, now, rows=None):
    """When, said in full for Claude's card: the place's networks too, so the user sees which arrival is meant."""
    if r["on"] in PLACED:
        rows = places.load() if rows is None else rows
        place = places.find(rows, r["place"]) or {"wifi": []}
        nets = ", ".join(place["wifi"])
        text = ("When I next arrive at " if r["on"] == "arrive" else "When I next leave ") + r["place"]
        text += f" (Wi-Fi {nets})" if nets else " (it has no Wi-Fi yet: nightdrive places add)"
    else:
        text = {"wake": "At the first unlock after the computer next wakes from sleep",
                "login": "At the next login"}[r["on"]]
    if r.get("from"):
        text += ", not before " + day_clock(r["from"], now)
    return text


def ready(r, now):
    """Its --from has come (or it has none): an event now may take it."""
    return not r.get("from") or now >= r["from"]


def matches(r, kind, place, now):
    """Whether an event (arrive work) is this row's: same event, same place (any case), and its --from has come."""
    if r.get("on") != kind or not ready(r, now):
        return False
    return kind not in PLACED or places.same(str(r.get("place", "")), place)


def deadline(r):
    """When an arrival or a leaving not seen is asked about: WAIT_DAYS after it was added, or after its --from. None
    for wake and login, which come with any use of the computer."""
    if r.get("on") not in PLACED:
        return None
    return int(max(r.get("added", 0), r.get("from") or 0)) + WAIT_DAYS * 86400


def public(r):
    """The fields the commands' --json adds: place (or null) and from (ISO, or null)."""
    return {"place": r.get("place"), "from": timers.iso(r["from"]) if r.get("from") else None}


def screen_locked():
    """The session's lock is up: this session's only (a container's runs as the same user), as hypr/scripts/lock asks.
    An event under it waits for the unlock, in remind and schedule alike."""
    mine = ["--ns", str(os.getpid()), "--nslist", "pid", "-u", str(os.getuid())]
    return any(subprocess.run(["pgrep", *mine, "-f", p], capture_output=True).returncode == 0 for p in LOCKS)
