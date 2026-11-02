#!/usr/bin/env python3
"""Changing an event: `calendar edit` (the window's editor and Claude's calendar_update), and `calendar restore`, its undo.

    change.py edit [--json] CALENDAR UID   stdin: a JSON object of what changes, the rest stays as it is:
                                         title, start, end, location, notes ("" clears those two), move_to (a calendar
                                         id or name the event goes to)
    change.py restore [--json] UNDO        puts the event back as it was before the edit that printed UNDO

start and end are write.py's forms (YYYY-MM-DDTHH:MM, or YYYY-MM-DD for all day, whose end is its last day). A start
without an end keeps the event's length, unless it turns a timed event into an all-day one or back (an hour, a day).

The event keeps its UID and everything Calendar doesn't show (alarms, invitees, the phone's own fields): only the fields
above are written, with SEQUENCE one up, so the server and the phone take it as a newer version. A move is the event
written into the other calendar's folder and removed from its own, then both synced, the old one first: iCloud refuses
a UID that is in two calendars of the account at once. A recurring event isn't changed (write.one_event says so).

Each edit keeps the files as they were (STATE_DIR/undo, the last KEEP_UNDO), and restore puts them back only while
they are still as the edit left them: an undo an hour later mustn't write over a change made since, here or on the phone.
"""

import base64
import datetime as dt
import json
import re
import sys
import time
from pathlib import Path

import calendars
import sources
import write

UNDO_DIR = sources.STATE_DIR / "undo"
KEEP_UNDO = 100
FIELDS = ("title", "start", "end", "location", "notes", "move_to")


def aware(value):
    """A floating time (no zone, as some phones write) read as local time, so it can be compared with a typed one"""
    if isinstance(value, dt.datetime) and value.tzinfo is None:
        return value.replace(tzinfo=write.local_zone())
    return value


def old_span(event):
    """The event's start and its DTEND (iCalendar's: an all-day event's day after), from DURATION when it has that"""
    start = aware(event.decoded("dtstart"))
    if "dtend" in event:
        return start, aware(event.decoded("dtend"))
    if "duration" in event:
        return start, start + event.decoded("duration")
    return start, start + (dt.timedelta(hours=1) if isinstance(start, dt.datetime) else dt.timedelta(days=1))


def new_span(data, event):
    """The start and DTEND the edit gives, checked as add() checks them"""
    old_start, old_end = old_span(event)
    start = write.when(data["start"], "start") if "start" in data else old_start
    all_day = not isinstance(start, dt.datetime)
    if data.get("end"):
        end = write.when(data["end"], "end")
        if isinstance(end, dt.datetime) == all_day:
            sys.exit("start and end are both days (all day) or both times.")
        end = end + dt.timedelta(days=1) if all_day else end
    elif isinstance(old_start, dt.datetime) == all_day:   # all day, or not, unlike before
        end = start + (dt.timedelta(days=1) if all_day else dt.timedelta(hours=1))
    else:
        end = start + (old_end - old_start)     # the start moved, or stayed: the length is kept
    if end <= start:
        sys.exit("end is before start.")
    return start, end


def relative(path):
    return str(Path(path).resolve().relative_to(sources.DATA_DIR.resolve()))


def inside(rel):
    """A snapshot's path as the file it names, checked to be an event's file: source/calendar/file.ics under DATA_DIR,
    links resolved. Anything that can write in the state folder could otherwise make an undo write or unlink any
    file the user can (as Tasks' store.inside, #1925)"""
    root = sources.DATA_DIR.resolve()
    parts = Path(rel).parts if isinstance(rel, str) else ()
    if len(parts) != 3 or Path(rel).is_absolute() or any(x in (".", "..") for x in parts) or not rel.endswith(".ics"):
        sys.exit(f"This undo names {rel!r}, not an event's file: nothing was changed.")
    p = (root / rel).resolve()
    if not p.is_relative_to(root) or len(p.relative_to(root).parts) != 3:
        sys.exit(f"This undo names {rel!r}, which leads out of the calendars' folder: nothing was changed.")
    return p


def snapshot(files):
    """files: [{path, before, after}] (bytes, or None for a file not there) to UNDO_DIR; the id restore() takes"""
    UNDO_DIR.mkdir(parents=True, exist_ok=True)
    sid = f"{time.time_ns():x}"
    keep = lambda b: None if b is None else base64.b64encode(b).decode()   # noqa: E731
    data = {"files": [{"path": relative(f["path"]), "before": keep(f["before"]), "after": keep(f["after"])}
                      for f in files]}
    tmp = UNDO_DIR / f"{sid}.tmp"
    tmp.write_text(json.dumps(data))
    tmp.replace(UNDO_DIR / f"{sid}.json")
    for old in sorted(UNDO_DIR.glob("*.json"))[:-KEEP_UNDO]:
        old.unlink(missing_ok=True)
    return sid


def put(path, content):
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(content)
    tmp.replace(path)


def calendar_of(path):
    """The calendar a file of DATA_DIR is in, as calendars.calendars() has it"""
    folder = str(Path(path).parent)
    return next((c for c in calendars.calendars() if str(Path(c["path"]).resolve()) == folder), None)


def edit(calendar_id, uid, data):
    data = {k: v for k, v in data.items() if k in FIELDS}
    cal = write.writable(calendar_id)
    path, ics, event = write.one_event(cal, uid, "change")
    target = write.writable(data["move_to"].strip()) if (data.get("move_to") or "").strip() else cal
    title = data["title"].strip() if "title" in data else str(event.get("summary", ""))
    if not title.strip():
        sys.exit("An event needs a title.")
    start, end = new_span(data, event)
    seq = int(event.get("sequence", 0))
    for key in ("summary", "dtstart", "dtend", "duration", "dtstamp", "last-modified", "sequence"):
        event.pop(key, None)
    event.add("summary", title)
    event.add("dtstart", start)
    event.add("dtend", end)
    for key, field in (("location", "location"), ("notes", "description")):
        if key in data:
            event.pop(field, None)
            if (data[key] or "").strip():
                event.add(field, data[key].strip())
    old = path.read_bytes()
    event.add("sequence", seq + 1)
    now = dt.datetime.now(dt.timezone.utc)
    event.add("dtstamp", now)
    event.add("last-modified", now)
    ics.add_missing_timezones()
    content = ics.to_ical()
    moved = target["id"] != cal["id"]
    dest = Path(target["path"]) / path.name if moved else path
    if moved and dest.exists():
        sys.exit(f"{target['name']} has a file {path.name} already: nothing was changed.")
    sid = snapshot([{"path": path, "before": old, "after": None if moved else content}]
                   + ([{"path": dest, "before": None, "after": content}] if moved else []))
    put(dest, content)
    if moved:
        path.unlink()
    synced = all([write.sync(cal)] + ([write.sync(target)] if moved else []))
    last = end - dt.timedelta(days=1) if not isinstance(start, dt.datetime) else end
    return {"uid": uid, "calendar": target["id"], "calendar_name": target["name"], "title": title,
            "start": write.shown(start), "end": write.shown(last), "all_day": not isinstance(start, dt.datetime),
            "when": write.span(start, last), "moved": moved, "synced": synced, "undo": sid,
            **({} if synced else {"note": "Saved on this computer; the next sync takes it to the server."})}


def restore(sid):
    snap = UNDO_DIR / f"{sid}.json"
    if not re.fullmatch(r"[0-9a-f]+", sid or "") or not snap.is_file():
        sys.exit(f"Nothing to undo with {sid!r}: it is done already, or too old.")
    files = json.loads(snap.read_text())["files"]
    read = lambda b: None if b is None else base64.b64decode(b)   # noqa: E731
    # Every file checked before any is touched: one changed since leaves the whole edit as it is
    checked = [(inside(f["path"]), read(f["before"]), read(f["after"])) for f in files]
    for p, _, after in checked:
        if (p.read_bytes() if p.is_file() else None) != after:
            sys.exit("The event has changed since, so the undo would lose that: nothing was changed. "
                     "Change it back by hand if need be.")
    # Removals first, and their calendars synced first: a move undone must leave the other calendar before the UID
    # comes back to its own (iCloud refuses it in two). The calendars are found before the files change: one the undo
    # empties has no file left to be found by
    checked.sort(key=lambda x: x[1] is not None)
    cals = [c for c in (calendar_of(p) for p, _, _ in checked) if c]
    for p, before, _ in checked:
        if before is None:
            p.unlink(missing_ok=True)
        else:
            put(p, before)
    snap.unlink()
    synced = all([write.sync(c) for c in {c["id"]: c for c in cals}.values()])
    return {"restored": sid, "synced": synced}


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    if args[:1] == ["edit"] and len(args) == 3:
        try:
            data = json.load(sys.stdin)
        except ValueError:
            sys.exit("calendar edit reads what changes as a JSON object on stdin.")
        if not isinstance(data, dict):
            sys.exit("calendar edit reads what changes as a JSON object on stdin.")
        result = edit(args[1], args[2], data)
        text = f"Changed in {result['calendar_name']}: {result['title']} ({result['when']})"
    elif args[:1] == ["restore"] and len(args) == 2:
        result = restore(args[1])
        text = "Put back as it was before the edit."
    else:
        sys.exit(__doc__)
    print(json.dumps(result, ensure_ascii=False) if as_json else text)
    if not result["synced"]:
        print("Not synced yet: the next sync takes it to the server.", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
