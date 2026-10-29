#!/usr/bin/env python3
"""Adding and deleting events: `calendar add` and `calendar delete` (Claude's calendar_add and calendar_delete).

    write.py add [--json]                    the event on stdin as JSON, or as options (below)
        --calendar ID --title T --start S [--end E] [--location L] [--notes N]
    write.py delete [--check] CALENDAR UID   --check: stdin's JSON must name the event (title, start), as Claude's
                                             confirmation card showed it, or nothing is deleted
    write.py shared [--calendar ID]          yes when add would put the event in a calendar others see (calendars.conf's
                                             `shared`), so Claude's calendar_add asks on the card first; no otherwise

start and end are local times, "YYYY-MM-DDTHH:MM", or days, "YYYY-MM-DD", for an all-day event; an all-day event's
end is its last day (not iCalendar's day after). Without end: an hour, or the one day.

The event is a new .ics in the calendar's folder, then `calendar sync SOURCE/CALENDAR` takes it to the server (or the next
round does, when it can't now). Only a calendar of a CalDAV account that isn't read-only takes one: the ICS ones are
read from an address, and a read-only account's sync would take a new event away again. Calendar never edits an
event; a recurring one isn't deleted (that is the phone's, for now).
"""

import datetime as dt
import json
import subprocess
import sys
import uuid
import zoneinfo
from pathlib import Path

import icalendar

import calendars

COMMAND = Path(__file__).resolve().parents[1] / "bin/calendar"
PRODID = "-//Nightdrive//Calendar//EN"
SYNC_TIMEOUT = 90


def local_zone():
    """The system's zone by name (Europe/Helsinki), so the phone shows the event in it rather than in UTC"""
    target = Path("/etc/localtime").resolve()
    try:
        return zoneinfo.ZoneInfo(str(target).split("/zoneinfo/", 1)[1])
    except (IndexError, zoneinfo.ZoneInfoNotFoundError):
        return dt.datetime.now().astimezone().tzinfo


def when(text, field):
    """A date for a day, an aware datetime for a time; exits with a message a reader can act on"""
    text = (text or "").strip()
    try:
        if len(text) == 10:
            return dt.date.fromisoformat(text)
        moment = dt.datetime.fromisoformat(text)
    except ValueError:
        sys.exit(f"{field} is YYYY-MM-DD (all day) or YYYY-MM-DDTHH:MM (local time), not {text!r}.")
    return moment if moment.tzinfo else moment.replace(tzinfo=local_zone())


def shown(value):
    """The form events.py prints and the card shows: local time to the minute, or the day"""
    if isinstance(value, dt.datetime):
        if value.tzinfo:
            value = value.astimezone(local_zone())
        return value.strftime("%Y-%m-%dT%H:%M")
    return value.isoformat()


def span(start, last):
    """In words for the notification: "2026-11-05 10:00–11:30", "2026-11-13 – 2026-11-15" """
    a, b = shown(start).replace("T", " "), shown(last).replace("T", " ")
    if a == b:
        return a
    return f"{a}–{b[11:]}" if a[:10] == b[:10] and len(a) > 10 else f"{a} – {b}"


def writable(calendar_id):
    """The calendar an event may go in, or exit with what can be used instead"""
    found = calendars.calendars()
    ok = [c for c in found if not c["read_only"]]   # an ICS source is always read-only
    if not calendar_id and len(ok) == 1:
        return ok[0]
    c = next((x for x in found if calendar_id in (x["id"], x["name"])), None)
    names = ", ".join(f"{x['name']} ({x['id']})" for x in ok) or "none: every calendar here is read-only"
    if c is None:
        sys.exit(f"No calendar {calendar_id!r}. The ones that take events: {names}." if calendar_id
                 else f"Which calendar? The ones that take events: {names}.")
    if c not in ok:
        sys.exit(f"{c['name']} is read-only here (an ICS address, or an account with read-only = yes). "
                 f"The ones that take events: {names}.")
    return c


def sync(cal):
    """The calendar up to the server now, it alone (a hiccup in another of the account's mustn't fail it); False when
    that failed (the next round takes it). A calendar left empty needs --force-delete: vdirsyncer won't empty the
    server's otherwise, taking an empty folder for a mistake"""
    force = [] if any(Path(cal["path"]).glob("*.ics")) else ["--force-delete"]
    try:
        done = subprocess.run([str(COMMAND), "sync", *force, cal["id"]], capture_output=True, text=True,
                              timeout=SYNC_TIMEOUT)
    except subprocess.TimeoutExpired:
        return False
    if done.returncode != 0:
        print(f"calendar: sync {cal['name']}: {done.stderr.strip()[-500:]}", file=sys.stderr)
    return done.returncode == 0


def add(data):
    title = (data.get("title") or "").strip()
    if not title:
        sys.exit("An event needs a title.")
    cal = writable((data.get("calendar") or "").strip())
    start = when(data.get("start"), "start")
    all_day = not isinstance(start, dt.datetime)
    if data.get("end"):
        end = when(data["end"], "end")
        if isinstance(end, dt.datetime) == all_day:
            sys.exit("start and end are both days (all day) or both times.")
        end = end + dt.timedelta(days=1) if all_day else end   # iCalendar's DTEND is the day after
    else:
        end = start + (dt.timedelta(days=1) if all_day else dt.timedelta(hours=1))
    if end <= start:
        sys.exit("end is before start.")
    uid = str(uuid.uuid4()).upper()
    event = icalendar.Event()
    event.add("uid", uid)
    event.add("dtstamp", dt.datetime.now(dt.timezone.utc))
    event.add("created", dt.datetime.now(dt.timezone.utc))
    event.add("summary", title)
    event.add("dtstart", start)
    event.add("dtend", end)
    for key, field in (("location", "location"), ("notes", "description")):
        if (data.get(key) or "").strip():
            event.add(field, data[key].strip())
    ics = icalendar.Calendar()
    ics.add("prodid", PRODID)
    ics.add("version", "2.0")
    ics.add_component(event)
    ics.add_missing_timezones()
    path = Path(cal["path"]) / f"{uid}.ics"
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(ics.to_ical())
    tmp.replace(path)
    synced = sync(cal)
    last = end - dt.timedelta(days=1) if all_day else end
    return {"uid": uid, "calendar": cal["id"], "calendar_name": cal["name"], "title": title, "start": shown(start),
            "end": shown(last), "all_day": all_day, "when": span(start, last), "synced": synced,
            **({} if synced else {"note": "Saved on this computer; the next sync takes it to the server."})}


def event_file(cal, uid):
    """The .ics holding uid: vdirsyncer names files by their UID mostly, but not always. A uid that would name a file
    elsewhere (a /, a leading .) is no event's: the file name is made from it (#1862)"""
    if not uid or "/" in uid or "\0" in uid or uid.startswith("."):
        return None
    folder = Path(cal["path"])
    direct = folder / f"{uid}.ics"
    if direct.is_file():
        return direct
    for path in folder.glob("*.ics"):
        try:
            if f"UID:{uid}" in path.read_text(errors="replace"):
                return path
        except OSError:
            continue
    return None


def delete(calendar_id, uid, check):
    cal = writable(calendar_id)
    path = event_file(cal, uid)
    if path is None:
        sys.exit(f"No event {uid} in {cal['name']}: calendar_events gives the uids.")
    ics = icalendar.Calendar.from_ical(path.read_bytes())
    events = [e for e in ics.walk("VEVENT") if str(e.get("uid")) == uid]
    if not events:
        sys.exit(f"No event {uid} in {cal['name']}.")
    main = next((e for e in events if "recurrence-id" not in e), events[0])
    if "rrule" in main or "rdate" in main or len(events) > 1:
        sys.exit("That event repeats: Calendar doesn't delete a recurring event yet. The user can delete it on "
                 "their phone or at icloud.com.")
    title, start = str(main.get("summary", "")), shown(main.decoded("dtstart"))
    if check is not None and (check.get("title", "").strip() != title.strip() or check.get("start") != start):
        sys.exit(f"Nothing deleted: the event is {title!r} at {start}, not what the card showed. Read it again with "
                 "calendar_events.")
    path.unlink()
    synced = sync(cal)
    return {"deleted": uid, "calendar": cal["id"], "title": title, "start": start, "synced": synced}


def options(argv):
    """--name value pairs to a dict"""
    out, rest = {}, list(argv)
    while rest:
        flag = rest.pop(0)
        if not flag.startswith("--") or not rest:
            sys.exit(__doc__)
        out[flag[2:]] = rest.pop(0)
    return out


def main(argv):
    if not argv or argv[0] not in ("add", "delete", "shared"):
        sys.exit(__doc__)
    if argv[0] == "shared":
        # The calendar add would take, or its reason why none (which add would give too)
        print("yes" if writable((options(argv[1:]).get("calendar") or "").strip())["shared"] else "no")
        return
    as_json = "--json" in argv
    args = [a for a in argv[1:] if a != "--json"]
    if argv[0] == "add":
        data = options(args) if args else json.load(sys.stdin)
        result = add(data)
    else:
        check = "--check" in args
        args = [a for a in args if a != "--check"]
        if len(args) != 2:
            sys.exit("Usage: calendar delete [--check] CALENDAR UID")
        result = delete(args[0], args[1], json.load(sys.stdin) if check else None)
    if as_json:
        print(json.dumps(result, ensure_ascii=False))
    elif "deleted" in result:
        print(f"Deleted: {result['title']} ({result['start']})")
    else:
        print(f"Added to {result['calendar_name']}: {result['title']} ({result['start']} – {result['end']})")
    if not result["synced"]:
        print("Not synced yet: the next sync takes it to the server.", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
