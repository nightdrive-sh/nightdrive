#!/usr/bin/env python3
"""An invitation from a mail (an .ics: METHOD REQUEST, PUBLISH or CANCEL), read: `calendar invite` (Mail's card on
the message, and Claude's mail_invitation). Putting it in a calendar is invite_write.py's.

    invite.py [FILE|-] [--json]                 what the invitation is, and where its event is already
    invite.py [FILE|-] --add CALENDAR [--json]  its event into CALENDAR, or the copy already in one brought up to date
    invite.py [FILE|-] --remove [--json]        a cancelled event (METHOD:CANCEL) out of the calendar it is in

FILE is the .ics, - (the default) stdin. What it prints:
    method, uid, title, start, end, all_day, location, organizer {name, address}, notes, recurring, occurrence (the
    time of a recurring event the invitation is about, or null), sequence, state, changes, existing, calendars
start and end are write.py's local forms (an all-day event's end is its last day). state:
    new        not in any calendar yet: --add puts it in one
    added      in a calendar already, as the invitation has it
    changed    in a calendar, and the invitation is newer (changes: time, place, title): --add updates it there
    older      in a calendar in a newer version than this one: nothing to do
    cancelled  METHOD:CANCEL, and the event is in a calendar: --remove takes it out
    gone       METHOD:CANCEL, and it isn't in any calendar
    reply      METHOD:REPLY, someone's answer to an invitation of yours: nothing to add
existing: the calendar it is in {calendar, calendar_name, read_only, title, start, end, location}, or null;
calendars: those that take events [{id, name, color}], for the card's picker.

The file comes from a stranger's mail, so it is only read as data: at most MAX_BYTES, its text cut to a length and
without control characters, nothing in it opened or fetched (its URL, ATTACH and alarms aren't even kept).
"""

import datetime as dt
import json
import re
import sys

import icalendar

import calendars
import write

MAX_BYTES = 1_000_000
TEXT_MAX = 300        # a title, a place, a name: longer is no invitation's
NOTES_MAX = 4000
CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f​-‏‪-‮⁦-⁩]")


def clean(value, limit=TEXT_MAX, lines=False):
    """A text of the invitation as plain text a reader can trust to be short and on one line (notes keep theirs)"""
    text = CONTROL.sub("", str(value or ""))
    text = re.sub(r"[ \t]*\n[ \t]*", "\n", text).strip() if lines else " ".join(text.split())
    return text[:limit] + ("…" if len(text) > limit else "")


def read(source):
    """The invitation's calendar; exits with what is wrong with it"""
    try:
        if source == "-":
            data = sys.stdin.buffer.read(MAX_BYTES + 1)
        else:
            with open(source, "rb") as fh:
                data = fh.read(MAX_BYTES + 1)
    except OSError as e:
        sys.exit(f"Can't read the invitation: {e.strerror}.")
    if len(data) > MAX_BYTES:
        sys.exit("The invitation is too big to be one.")
    try:
        ics = icalendar.Calendar.from_ical(data)
    except Exception:   # icalendar raises ValueError mostly, but a broken file can raise nearly anything
        sys.exit("The invitation can't be read: its calendar data is broken.")
    if not any(True for _ in ics.walk("VEVENT")):
        sys.exit("The invitation has no event in it.")
    return ics


def parts(ics):
    """The invitation's first event: its uid and every VEVENT of that uid (a recurring one's changed times too)"""
    first = next(iter(ics.walk("VEVENT")))
    uid = clean(first.get("uid"), 500)
    if not uid:
        sys.exit("The invitation's event has no UID, so it can't be kept apart from others.")
    return uid, [e for e in ics.walk("VEVENT") if clean(e.get("uid"), 500) == uid]


def main_part(events):
    """The event itself, else the one changed time an invitation for a single time of a recurring event has"""
    return next((e for e in events if "recurrence-id" not in e), events[0])


def span(event):
    """start, DTEND (iCalendar's: an all-day event's day after), all_day; a broken time exits"""
    try:
        start = event.decoded("dtstart")
        if "dtend" in event:
            end = event.decoded("dtend")
        elif "duration" in event:
            end = start + event.decoded("duration")
        else:
            end = start + (dt.timedelta(days=1) if not isinstance(start, dt.datetime) else dt.timedelta())
    except (KeyError, ValueError, TypeError):
        sys.exit("The invitation's event has no time that can be read.")
    all_day = not isinstance(start, dt.datetime)
    if all_day and isinstance(end, dt.datetime):
        end = end.date()
    if end < start:
        end = start
    return start, end, all_day


def times(event):
    """The event's start and end the way write.py shows them: an all-day event's end is its last day"""
    start, end, all_day = span(event)
    last = end - dt.timedelta(days=1) if all_day and end > start else end
    return write.shown(start), write.shown(last), all_day


def person(value):
    """ORGANIZER's name (CN) and address (mailto:…)"""
    if not value:
        return None
    address = re.sub(r"^mailto:", "", str(value), flags=re.I)
    name = value.params.get("CN", "") if hasattr(value, "params") else ""
    return {"name": clean(name), "address": clean(address)}


def seq(event):
    try:
        return int(event.get("sequence", 0))
    except (TypeError, ValueError):
        return 0


def find(uid):
    """(calendar, path, the stored VEVENTs of uid) of the calendar the event is in already, or None"""
    for cal in calendars.calendars():
        path = write.event_file(cal, uid)
        if path is None:
            continue
        try:
            stored = icalendar.Calendar.from_ical(path.read_bytes())
        except Exception:
            continue
        events = [e for e in stored.walk("VEVENT") if str(e.get("uid")) == uid]
        if events:
            return cal, path, stored, events
    return None


def matching(events, target):
    """The stored VEVENT the invitation's target is about: the same changed time, or the event itself"""
    rid = target.get("recurrence-id")
    if rid is None:
        return next((e for e in events if "recurrence-id" not in e), None)
    want = write.shown(rid.dt)
    return next((e for e in events if "recurrence-id" in e and write.shown(e["recurrence-id"].dt) == want), None)


def describe(ics):
    method = clean(ics.get("method", "PUBLISH")).upper()
    uid, events = parts(ics)
    target = main_part(events)
    start, end, all_day = times(target)
    rid = target.get("recurrence-id")
    out = {"method": method, "uid": uid, "title": clean(target.get("summary")) or "(no title)",
           "start": start, "end": end, "all_day": all_day, "location": clean(target.get("location")),
           "organizer": person(target.get("organizer")), "notes": clean(target.get("description"), NOTES_MAX, True),
           "recurring": any("rrule" in e or "rdate" in e for e in events) or rid is not None,
           "occurrence": write.shown(rid.dt) if rid is not None else None, "sequence": seq(target),
           "changes": [], "existing": None,
           "calendars": [{"id": c["id"], "name": c["name"], "color": c["color"]}
                         for c in calendars.calendars() if not c["read_only"]]}
    found = find(uid)
    stored = matching(found[3], target) if found else None
    if found:
        cal = found[0]
        shown = stored if stored is not None else main_part(found[3])
        s, e, _ = times(shown)
        out["existing"] = {"calendar": cal["id"], "calendar_name": cal["name"], "read_only": cal["read_only"],
                           "title": clean(shown.get("summary")), "start": s, "end": e,
                           "location": clean(shown.get("location"))}
    if method == "REPLY":
        out["state"] = "reply"
    elif method == "CANCEL":
        out["state"] = "cancelled" if found and (stored is not None or rid is not None) else "gone"
    elif not found:
        out["state"] = "new"
    elif stored is None:
        out["state"] = "changed"   # a time of it the stored event doesn't have changed yet
        out["changes"] = ["time"]
    else:
        ex = out["existing"]
        out["changes"] = [name for name, a, b in (("time", (start, end), (ex["start"], ex["end"])),
                                                   ("place", out["location"], ex["location"]),
                                                   ("title", out["title"], ex["title"])) if a != b]
        if seq(target) < seq(stored):
            out["state"] = "older"
        else:
            out["state"] = "changed" if out["changes"] or seq(target) > seq(stored) else "added"
    return out


def text(info):
    a, b = info["start"].replace("T", " "), info["end"].replace("T", " ")
    when = a if a == b else f"{a}–{b[11:]}" if a[:10] == b[:10] and len(a) > 10 else f"{a} – {b}"
    lines = [info["title"], when]
    if info["location"]:
        lines.append(info["location"])
    if info["organizer"]:
        o = info["organizer"]
        lines.append("From " + (f"{o['name']} <{o['address']}>" if o["name"] else o["address"]))
    ex = info["existing"]
    state = {"new": "Not in a calendar yet.", "reply": "An answer to an invitation: nothing to add.",
             "gone": "Cancelled, and not in a calendar.", "older": f"{ex and ex['calendar_name']} has a newer version.",
             "added": f"In {ex and ex['calendar_name']}.", "cancelled": f"Cancelled: still in {ex and ex['calendar_name']}.",
             "changed": f"Changed ({', '.join(info['changes'])}): {ex and ex['calendar_name']} has the old version."}
    return "\n".join(lines + [state[info["state"]]])


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    action = None
    if "--remove" in args:
        args.remove("--remove")
        action = ("remove", None)
    if "--add" in args:
        i = args.index("--add")
        if i + 1 >= len(args):
            sys.exit("Usage: calendar invite [FILE|-] --add CALENDAR")
        action = ("add", args[i + 1])
        del args[i:i + 2]
    if len(args) > 1:
        sys.exit(__doc__)
    ics = read(args[0] if args else "-")
    if action:
        import invite_write   # only when it writes: reading stays this file alone
        result = invite_write.run(ics, *action)
        print(json.dumps(result, ensure_ascii=False) if as_json else result["said"])
        return
    info = describe(ics)
    print(json.dumps(info, ensure_ascii=False) if as_json else text(info))


if __name__ == "__main__":
    main(sys.argv[1:])
