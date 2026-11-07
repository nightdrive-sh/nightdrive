#!/usr/bin/env python3
"""A recurring event's file changed (#2009): one of its times, or all of them. change.py (edit) and write.py (delete)
call these; the rules themselves are repeat.py's.

A series is the VEVENTs of one UID in one file: the event itself (the master: its RRULE, EXDATEs) and its changed times
(a RECURRENCE-ID each, the time they replace). So
- one time changed is such a changed copy, made from the master the first time and changed after that;
- one time deleted is an EXDATE on the master, and its changed copy gone; with no time left, the whole file goes;
- every time changed is the master: moved by as much as the time the user changed moved, so "an hour later" or "on
  Wednesday" means the same for each, and the EXDATEs and changed times move with it (an occurrence's RECURRENCE-ID
  is the master's time it replaces). Changed times the new rule no longer has go, or khal would show them alone.

An occurrence is named by its start as calendar_events gives it (YYYY-MM-DDTHH:MM local, or YYYY-MM-DD): a changed
time's own start, else the series' time. A changed time's RECURRENCE-ID, written the same way, names it too.
"""

import copy
import datetime as dt
import sys
import uuid

import repeat
import write

SCOPES = ("this", "all")


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


def recurring(events):
    return len(events) > 1 or any("rrule" in e or "rdate" in e or "recurrence-id" in e for e in events)


def scope(events, data):
    """"this" or "all" for a recurring event (data's scope; exits without one), None for a single one"""
    master = next((e for e in events if "recurrence-id" not in e), None)
    if not recurring(events) or (master is None and len(events) == 1):   # one time of a series, alone (an invitation)
        return None
    s = (data.get("scope") or "").strip().lower()
    if s == "all" and master is None:
        sys.exit("Only some times of this event are here, not the event itself: change them one at a time (scope this).")
    if s not in SCOPES:
        sys.exit("That event repeats: say which, scope this (one time: occurrence is its start as calendar_events "
                 "gives it) or all (every time).")
    if s == "this" and not (data.get("occurrence") or "").strip():
        sys.exit("scope this needs occurrence: the time's start, as calendar_events gives it.")
    return s


def changed(events):
    return [e for e in events if "recurrence-id" in e]


def locate(master, events, occurrence):
    """(RECURRENCE-ID, its changed copy or None) of the time occurrence names; exits when the series has none there"""
    text = (occurrence or "").strip()
    for key in ("dtstart", "recurrence-id"):
        for e in changed(events):
            if key in e and write.shown(aware(e.decoded(key))) == text:
                return e.decoded("recurrence-id"), e
    if master is not None and text:
        found = repeat.find(master, write.when(text, "occurrence"))
        if found is not None:
            return repeat.native(found, master), None
    sys.exit(f"The event has no time at {text!r}: give its start as calendar_events gives it.")


def seen(master, events, occurrence):
    """The start and DTEND of the time the user looked at (its changed copy's own), or the series' first"""
    if not (occurrence or "").strip():
        return old_span(master)
    rid, found = locate(master, events, occurrence)
    if found is not None:
        return old_span(found)
    start, end = old_span(master)
    return aware(rid), aware(rid) + (end - start)


def override(ics, master, events, occurrence):
    """The changed copy of one time, made from the master (its fields, alarms and all) when it has none yet"""
    rid, found = locate(master, events, occurrence)
    if found is not None:
        return found
    start, end = old_span(master)
    e = copy.deepcopy(master)
    for key in ("rrule", "rdate", "exdate", "dtstart", "dtend", "duration"):
        e.pop(key, None)
    e.add("dtstart", rid)
    e.add("dtend", aware(rid) + (end - start) if isinstance(rid, dt.datetime) else rid + (end - start))
    e.add("recurrence-id", rid)
    for alarm in e.walk("VALARM"):   # a copy's alarms are alarms of their own
        if "uid" in alarm:
            alarm.pop("uid")
            alarm.add("uid", str(uuid.uuid4()).upper())
    ics.add_component(e)
    return e


def bump(event):
    seq = int(event.get("sequence", 0))
    now = dt.datetime.now(dt.timezone.utc)
    for key in ("sequence", "dtstamp", "last-modified"):
        event.pop(key, None)
    event.add("sequence", seq + 1)
    event.add("dtstamp", now)
    event.add("last-modified", now)


def drop(ics, master, events, occurrence):
    """One time out: an EXDATE, and its changed copy gone. False when the series has no time left (the file goes)"""
    rid, found = locate(master, events, occurrence)
    if found is not None:
        ics.subcomponents = [c for c in ics.subcomponents if c is not found]
    if master is None:
        return any(c is not found for c in changed(events))
    master.add("exdate", rid)
    bump(master)
    left = next(repeat.times(master), None) is not None
    return left or any(c is not found for c in changed(events))


def shifter(was, now):
    """A function moving a time of the series as was moved to now: by as many days, to now's time of day"""
    days = repeat.local_day(now) - repeat.local_day(was)

    def move(value):
        day = repeat.local_day(value) + days
        if not isinstance(now, dt.datetime):
            return day
        return dt.datetime.combine(day, now.astimezone(write.local_zone()).timetz())
    return move, days.days


def move_all(ics, master, events, was, now):
    """Every time moved as the one the user changed was (start, DTEND) to now: the master's new start and DTEND,
    with its EXDATEs and its changed times' RECURRENCE-IDs moved along. Nothing moves when only the length changed"""
    start, end = old_span(master)
    if was[0] == now[0] and (isinstance(was[0], dt.datetime) == isinstance(now[0], dt.datetime)):
        return start, start + (now[1] - now[0])
    move, days = shifter(was[0], now[0])
    new_start = move(start)
    exdates = [move(v) for v in repeat.values(master, "exdate")]
    master.pop("exdate", None)
    for v in exdates:
        master.add("exdate", v)
    for e in changed(events):
        rid = move(e.decoded("recurrence-id"))
        e.pop("recurrence-id")
        e.add("recurrence-id", rid)
    for r in repeat.rules(master):
        byday = [str(d).upper() for d in repeat.part(r, "BYDAY")]
        if days % 7 and byday and all(d in repeat.DAYS for d in byday):
            # Weekly on Tue moved a day on: on Wed. Other rules (the second Tuesday) keep their days
            r["BYDAY"] = [repeat.DAYS[(repeat.DAYS.index(d) + days) % 7] for d in byday]
        until = (repeat.part(r, "UNTIL") or [None])[0]
        if until is not None and isinstance(until, dt.datetime) != isinstance(new_start, dt.datetime):
            day = repeat.local_day(until)   # all day now, or timed now: UNTIL is the same kind as DTSTART
            r["UNTIL"] = [day if not isinstance(new_start, dt.datetime) else dt.datetime.combine(
                day, dt.time(23, 59, 59), tzinfo=write.local_zone()).astimezone(dt.timezone.utc)]
    return new_start, new_start + (now[1] - now[0])


def set_repeat(ics, master, events, s):
    """The series' rule replaced (s from repeat.spec); none makes it a single event, its exceptions gone"""
    repeat.set_rule(master, s)
    if s is None:
        master.pop("rdate", None)
        master.pop("exdate", None)
        ics.subcomponents = [c for c in ics.subcomponents if not any(c is e for e in changed(events))]


def prune(ics, master, events):
    """Changed times the rule no longer has out: the time they replace is gone"""
    gone = [e for e in changed(events) if repeat.find(master, e.decoded("recurrence-id")) is None]
    ics.subcomponents = [c for c in ics.subcomponents if not any(c is g for g in gone)]
