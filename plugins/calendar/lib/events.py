#!/usr/bin/env python3
"""The events between two days, by khal: `calendar events` (Claude's calendar_events, and the window's views).

    events.py FROM TO [--json] [--calendar ID] [--search TEXT] [--limit N]
    events.py --config        write khal's config and print its path (`calendar khal …`)

FROM is the first day, TO the day after the last (YYYY-MM-DD), so a week is MONDAY NEXT-MONDAY, as the window asks.
khal expands the recurring events (RRULE, RDATE, EXDATE, a changed occurrence) into each of their times and keeps an
index of the .ics files in its own database, so a month is read in a moment after the first time.

An event: uid, calendar (id), calendar_name, color, title, start, end, all_day, location, notes, recurring, reminder (repeat).
start and end are local time, YYYY-MM-DDTHH:MM, or the day, YYYY-MM-DD, for an all-day event, whose end is its last
day. reminder: its first alarm in minutes before the start (alarms.py: 0 at the start; an all-day event's -540 is
9:00 on the day), or null: read from the event's file, which khal doesn't tell. A recurring one also has repeat, its
series' rule as repeat.read() gives it ({every, interval, days, until, count, simple, text}), or null when the file has
only some of its times.
"""

import datetime as dt
import json
import subprocess
import sys

import alarms
import calendars
import repeat

LIMIT = 200         # the default: a busy month, short enough for Claude to read
RANGE_MAX = 400     # days: a longer range is a mistake, and would only fill Claude's context
TIMEOUT = 120       # khal's first run indexes every event
# khal's fields (khal list --json FIELD), and the names they have here
FIELDS = {"uid": "uid", "calendar": "calendar", "title": "title", "start": "start", "end": "end",
          "all-day": "all_day", "location": "location", "description": "notes", "repeat-pattern": "recurring",
          "repeat-symbol": "recurring_symbol"}


def day(text, name):
    try:
        return dt.date.fromisoformat(text)
    except (TypeError, ValueError):
        sys.exit(f"{name} is a day, YYYY-MM-DD, not {text!r}.")


def khal(found, first, last):
    """khal's rows for the days first…last (both included, as khal counts them)"""
    config = calendars.write_khal(found)
    # Not --once: it would show a recurring event's first time only. A multi-day event comes on each of its days instead,
    # and events() keeps it once
    argv = ["khal", "-c", str(config), "list", "--day-format", ""]
    for field in FIELDS:
        argv += ["--json", field]
    argv += [first.isoformat(), last.isoformat()]
    try:
        done = subprocess.run(argv, capture_output=True, text=True, timeout=TIMEOUT)
    except FileNotFoundError:
        sys.exit("khal isn't installed: sudo dnf install khal (Calendar's installer does it).")
    except subprocess.TimeoutExpired:
        sys.exit("khal took too long: try a shorter range.")
    if done.returncode != 0:
        sys.exit(f"khal: {done.stderr.strip()[-1000:]}")
    rows = []
    # A JSON list a line: each day's events (khal prints one per day)
    for line in done.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            value = json.loads(line)
        except ValueError:
            continue
        rows += value if isinstance(value, list) else [value]
    return rows


def event(row, names):
    e = {ours: row.get(theirs, "") for theirs, ours in FIELDS.items()}
    e["all_day"] = str(e["all_day"]).lower() in ("true", "1", "yes")
    # A changed time of a series has no pattern of its own in khal, only the symbol (#2009)
    e["recurring"] = bool(e["recurring"]) or bool(str(e.pop("recurring_symbol", "")).strip())
    cal = names.get(e["calendar"], {})
    e["calendar_name"], e["color"] = cal.get("name", e["calendar"]), cal.get("color", calendars.COLOR_DEFAULT)
    return e


def events(first, after, calendar=None, search="", reminders=True):
    """Every event in the range, the earliest first; reminders=False leaves out reading their files (remind.py reads
    every alarm itself)"""
    found = calendars.calendars()
    names = {c["id"]: c for c in found}
    if calendar and calendar not in names:
        by_name = [c for c in found if c["name"].lower() == calendar.lower()]
        if len(by_name) != 1:
            sys.exit(f"No calendar {calendar!r}: calendar calendars lists them.")
        calendar = by_name[0]["id"]
    if not found:
        return []
    out, seen = [], set()
    for row in khal(found, first, after - dt.timedelta(days=1)):
        e = event(row, names)
        if (e["uid"], e["start"]) not in seen:
            seen.add((e["uid"], e["start"]))
            out.append(e)
    if calendar:
        out = [e for e in out if e["calendar"] == calendar]
    words = search.lower().split()
    if words:
        out = [e for e in out if all(w in f"{e['title']}\n{e['location']}\n{e['notes']}".lower() for w in words)]
    if reminders:
        files = alarms.Files(found)
        for e in out:
            vevent = files.event(e["calendar"], e["uid"], alarms.local(dt.date.fromisoformat(e["start"]) if e["all_day"]
                                                                        else dt.datetime.fromisoformat(e["start"])))
            e["reminder"] = alarms.reminder(vevent) if vevent is not None else None
            if e["recurring"]:
                master = next((x for x in files.vevents(e["calendar"], e["uid"]) if "recurrence-id" not in x), None)
                e["repeat"] = repeat.read(master) if master is not None else None
    # All-day ones first on their day, then by time
    out.sort(key=lambda e: (e["start"][:10], not e["all_day"], e["start"], e["title"].lower()))
    return out


def text(result):
    if not result["events"]:
        return "No events."
    rows = []
    for e in result["events"]:
        if e["all_day"]:
            when = e["start"] + (f" – {e['end']}" if e["end"] != e["start"] else "")
        else:
            end = e["end"][11:] if e["end"][:10] == e["start"][:10] else e["end"].replace("T", " ")
            when = f"{e['start'].replace('T', ' ')} – {end}"
        rows.append(f"{when}  {e['title']}" + (f"  @ {e['location'].splitlines()[0]}" if e["location"] else "")
                    + f"  [{e['calendar_name']}]")
    more = result["count"] - len(result["events"])
    return "\n".join(rows + ([f"… and {more} more: --limit, or a shorter range"] if more > 0 else []))


def main(argv):
    if argv == ["--config"]:
        print(calendars.write_khal(calendars.calendars()))
        return
    as_json = "--json" in argv
    rest = [a for a in argv if a != "--json"]
    opts = {"--calendar": None, "--search": "", "--limit": str(LIMIT)}
    for flag in opts:
        if flag in rest:
            i = rest.index(flag)
            if i + 1 >= len(rest):
                sys.exit(f"{flag} takes a value")
            opts[flag] = rest[i + 1]
            del rest[i:i + 2]
    if len(rest) != 2:
        sys.exit(__doc__)
    first, after = day(rest[0], "FROM"), day(rest[1], "TO")
    if after <= first:
        sys.exit("TO is the day after the last: later than FROM.")
    if (after - first).days > RANGE_MAX:
        sys.exit(f"At most {RANGE_MAX} days at a time.")
    try:
        limit = max(1, int(opts["--limit"]))
    except ValueError:
        sys.exit("--limit takes a number")
    found = events(first, after, opts["--calendar"], opts["--search"])
    result = {"from": first.isoformat(), "to": after.isoformat(), "count": len(found), "events": found[:limit]}
    print(json.dumps(result, ensure_ascii=False) if as_json else text(result))


if __name__ == "__main__":
    main(sys.argv[1:])
