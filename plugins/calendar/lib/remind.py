#!/usr/bin/env python3
"""The events' reminders as notifications: nightdrive-calendar-remind.timer runs `calendar remind` every minute, and
each reminder whose time has come shows once (notice.py), with Open and Snooze.

    remind.py check                      notify what has come since the last check (the timer's)
    remind.py list [--json] [--days N]   the settings and the reminders of the next N days (1; at most 28)
    remind.py on | off                   the reminders' notifications on or off (Settings ⌘, in the window)
    remind.py default none|MINUTES       a timed event without a reminder of its own gets one MINUTES before
    remind.py join on | off              the notification with Join a minute before a meeting, on or off

Where they come from: each event's alarms (alarms.py), at each time of a recurring one, as khal lists the times; and,
for a timed event without any, the default (settings.py). The plan (PLAN) of the next AHEAD days is made again only
when a calendar's folder, the settings or the day have changed, so the minute's check reads a file, not every event.

A reminder missed while the computer slept or was off shows when it wakes, if its event hasn't ended; more than
ONE_BY_ONE at once come as one notification. With the reminders off, the check still marks what comes as seen, so
turning them on doesn't bring back the ones of the time they were off. Snooze (notice.py) puts one in SNOOZED.

A timed event with a meeting link (meeting.py: Teams, Meet, Zoom, Webex) also gets a notification JOIN_BEFORE its start,
with Join (#3444): kind "join" in the plan, its key the event's and "|join". Not when one of its own reminders comes
that close to the start anyway (with its Join), and not with settings' join_notice off. A reminder of such an event
has Join too: the plan carries its meeting. It always comes on its own, not in the many-at-once notification: its
Join is the point of it.
"""

import datetime as dt
import json
import shutil
import subprocess
import sys
from pathlib import Path

import alarms
import calendars
import events
import settings
import sources
import write

PLAN = sources.STATE_DIR / "reminders.json"     # {"key": fingerprint, "alarms": [alarm]}
SEEN = sources.STATE_DIR / "reminded.json"      # {alarm key: its event's end}: notified, or passed while off
SNOOZED = sources.STATE_DIR / "snoozed.json"    # {alarm key: {"until": iso, "alarm": alarm}}
AHEAD = 29         # days of events planned: a reminder four weeks before an event is in the plan
ONE_BY_ONE = 3     # more due at once come as one notification
JOIN_BEFORE = dt.timedelta(minutes=1)     # the join notification: the timer's minute, then a minute to open the call
JOIN_NEAR = dt.timedelta(minutes=2)       # an own reminder this close to the start has Join already: no second one
PLAN_FORM = "2"    # in the fingerprint: a plan written before meetings were in it (#3444) is made again
NOTICE = Path(__file__).resolve().with_name("notice.py")


def read(path, default):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, type(default)) else default
    except (OSError, ValueError):
        return default


def store(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


def fingerprint(cals, today):
    """What the plan was made from: the day, the settings, and each calendar's folder and newest file (an event added
    or removed changes the folder's time, one written in place only its file's). A stat a file, no reading"""
    parts = [PLAN_FORM, today.isoformat(), str(settings.get())]
    for c in cals:
        try:
            folder = Path(c["path"])
            times = [p.stat().st_mtime_ns for p in folder.glob("*.ics")]
            parts.append(f"{c['id']}:{folder.stat().st_mtime_ns}:{len(times)}:{max(times, default=0)}")
        except OSError:
            parts.append(c["id"])
    return "|".join(parts)


def bounds(e):
    """An event of events.py as aware local start and end (an all-day one's end is the midnight after its last day)"""
    start = alarms.local(write.when(e["start"], "start"))
    if e["all_day"]:
        return start, alarms.local(dt.date.fromisoformat(e["end"][:10]) + dt.timedelta(days=1))
    return start, alarms.local(write.when(e["end"], "end"))


def join_at(e, start, ats, on=True):
    """When an event's join notification comes, or None: a timed event with a meeting link, none of whose own reminders
    comes within JOIN_NEAR of its start"""
    if not on or e["all_day"] or not e.get("meeting"):
        return None
    if any(start - JOIN_NEAR <= at <= start for at in ats):
        return None
    return start - JOIN_BEFORE


def make_plan(cals, today):
    s = settings.get()
    default = s["default_reminder"]
    files = alarms.Files(cals)
    out = []
    for e in events.events(today - dt.timedelta(days=1), today + dt.timedelta(days=AHEAD), reminders=False):
        start, end = bounds(e)
        vevent = files.event(e["calendar"], e["uid"], start)
        ats = alarms.times(vevent, start, end) if vevent is not None else []
        if not ats and default is not None and not e["all_day"]:
            ats = [start - dt.timedelta(minutes=default)]
        base = f"{e['calendar']}|{e['uid']}|{e['start']}|"
        join = join_at(e, start, ats, s["join_notice"])
        for kind, key, at in [("reminder", base + at.isoformat(), at) for at in ats] + (
                [("join", base + "join", join)] if join else []):
            out.append({"key": key, "kind": kind, "at": at.isoformat(), "calendar": e["calendar"],
                        "calendar_name": e["calendar_name"], "uid": e["uid"], "title": e["title"],
                        "location": e["location"], "meeting": e.get("meeting"), "start": start.isoformat(),
                        "end": end.isoformat(), "all_day": e["all_day"], "day": e["start"][:10]})
    out.sort(key=lambda a: a["at"])
    return out


def plan(now):
    cals = calendars.calendars()
    key = fingerprint(cals, now.date())
    kept = read(PLAN, {})
    if kept.get("key") == key:
        return kept.get("alarms", [])
    found = make_plan(cals, now.date()) if cals else []
    store(PLAN, {"key": key, "alarms": found})
    return found


def spawn(args):
    cmd = [sys.executable, str(NOTICE)] + args
    # In a unit of its own: the timer's service ends at once, and would take a child of its own with it (as Tasks').
    # Without a user manager (a container, a shell outside the session) a process of its own instead
    if shutil.which("systemd-run"):
        try:
            if subprocess.run(["systemd-run", "--user", "--collect", "--quiet", "--"] + cmd, stdin=subprocess.DEVNULL,
                              capture_output=True, timeout=10).returncode == 0:
                return
        except subprocess.TimeoutExpired:
            return   # started, probably: a second one would show it twice
    subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def check(now=None):
    now = now or dt.datetime.now().astimezone()
    first_run = not SEEN.exists()
    seen = read(SEEN, {})
    snoozed = read(SNOOZED, {})
    due = []
    for a in plan(now):
        at, end = dt.datetime.fromisoformat(a["at"]), dt.datetime.fromisoformat(a["end"])
        if at > now or a["key"] in seen or a["key"] in snoozed or end <= now:
            continue
        seen[a["key"]] = a["end"]
        # The very first check knows nothing of what was shown before: only what has just come
        if not (first_run and at < now - dt.timedelta(minutes=2)):
            due.append(a)
    for key, s in list(snoozed.items()):
        if dt.datetime.fromisoformat(s["until"]) <= now:
            del snoozed[key]
            if dt.datetime.fromisoformat(s["alarm"]["end"]) > now:
                due.append(s["alarm"])
    # Only the events not long over are remembered, so the file stays small
    keep = (now - dt.timedelta(days=1)).isoformat()
    store(SEEN, {k: v for k, v in seen.items() if v >= keep})
    store(SNOOZED, snoozed)
    if not settings.get()["reminders"] or not due:
        return
    joins = [a for a in due if a.get("kind") == "join"]
    rest = [a for a in due if a.get("kind") != "join"]
    if len(rest) > ONE_BY_ONE:
        spawn(["many", json.dumps(rest, ensure_ascii=False)])
        rest = []
    for a in rest + joins:
        spawn(["one", json.dumps(a, ensure_ascii=False)])


def upcoming(days, now=None):
    now = now or dt.datetime.now().astimezone()
    until = now + dt.timedelta(days=days)
    return [a for a in plan(now) if now < dt.datetime.fromisoformat(a["at"]) <= until]


def text(result):
    s = result["settings"]
    head = ("Reminders are on" if s["reminders"] else "Reminders are off") + (
        f"; a timed event without one: {s['default_reminder']} min before" if s["default_reminder"] is not None
        else "; only the events' own") + ("; Join a minute before a meeting" if s["join_notice"] else "")
    import notice   # here: it imports this file
    now = dt.datetime.now().astimezone()
    r = notice.region.current()

    def at(a):   # the region's way: "Today 9:45", "Fri 6.11. 9:45 AM"
        t = dt.datetime.fromisoformat(a["at"])
        return f"{notice.day_name(t.date(), now.date(), r)} {notice.region.fmt(t, r['time'])}"
    rows = [f"{at(a)}  {'Join: ' if a.get('kind') == 'join' else ''}{a['title']}: {notice.when(a, now)}  "
            f"[{a['calendar_name']}]" for a in result["reminders"]]
    return "\n".join([head + "."] + (rows or [f"None in the next {result['days']} day(s)."]))


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    days = 1
    if "--days" in args:
        i = args.index("--days")
        try:
            days = max(1, min(28, int(args[i + 1])))
        except (IndexError, ValueError):
            sys.exit("--days takes a number")
        del args[i:i + 2]
    cmd = args[0] if args else "list"
    if cmd == "check" and len(args) == 1:
        check()
        return
    if cmd in ("on", "off") and len(args) == 1:
        settings.put("reminders", cmd == "on")
    elif cmd == "default" and len(args) == 2:
        m = None if args[1].lower() == "none" else alarms.minutes(args[1])
        if m not in settings.DEFAULT_CHOICES:
            takes = ", ".join(str(x) for x in settings.DEFAULT_CHOICES if x is not None)
            sys.exit(f"default takes none or {takes}.")
        settings.put("default_reminder", m)
    elif cmd == "join" and len(args) == 2 and args[1] in ("on", "off"):
        settings.put("join_notice", args[1] == "on")
    elif cmd != "list":
        sys.exit(__doc__)
    result = {"settings": settings.get(), "days": days, "reminders": upcoming(days)}
    print(json.dumps(result, ensure_ascii=False) if as_json else text(result))


if __name__ == "__main__":
    main(sys.argv[1:])
