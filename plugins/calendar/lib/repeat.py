#!/usr/bin/env python3
"""Recurring events' rules (#2009): a repeat as the user picks it, as an RRULE and back, and the times a series has.

A repeat, as `calendar add`, `calendar edit` and Claude take it (JSON):
    "daily", "weekdays", "weekly", "biweekly", "monthly", "yearly"; null or "none" for none; or an object
    {"every": "day" | "week" | "month" | "year", "interval": N (every N of them, 1–99), "days": ["MO", "TH"] (a weekly
     one's days), "until": "YYYY-MM-DD" (its last day) or "count": N (that many times)}

    spec(value) -> dict | None        the JSON checked and in one form (exits with what is wrong)
    set_rule(vevent, spec)            its RRULE that spec's (or none), for the start it has
    read(vevent) -> dict | None       its RRULE as a spec, with simple (the window's choices say it) and text (in words)
    times(master)                     its times, the first first: a generator, a series may never end
    find(master, value)               the time of the series at value (a date, or an aware datetime), or None
    native(value, master)             such a time in the form the event's DTSTART has: a RECURRENCE-ID or EXDATE

The times are dateutil's, as khal's are, with DTSTART always the first (RFC 5545, as the phone counts it). A rule
set elsewhere (the second Tuesday of a month, two RRULEs) is read and kept, not made here: read() says simple: false.
"""

import datetime as dt

import icalendar
from dateutil import rrule as du

import write

FREQS = {"day": "DAILY", "week": "WEEKLY", "month": "MONTHLY", "year": "YEARLY"}
EVERY = {v: k for k, v in FREQS.items()}
DAYS = ("MO", "TU", "WE", "TH", "FR", "SA", "SU")
DAY_NAMES = dict(zip(DAYS, ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")))
WEEKDAYS = ["MO", "TU", "WE", "TH", "FR"]
PRESETS = {"daily": ("day", 1, []), "weekdays": ("week", 1, WEEKDAYS), "weekly": ("week", 1, []),
           "biweekly": ("week", 2, []), "monthly": ("month", 1, []), "yearly": ("year", 1, [])}
INTERVAL_MAX = 99
COUNT_MAX = 999
SIMPLE = {"FREQ", "INTERVAL", "BYDAY", "UNTIL", "COUNT", "WKST"}   # the parts the window's choices can say
KEYS = {"every", "interval", "days", "until", "count"}


def number(value, name, most):
    try:
        n = int(value)
    except (TypeError, ValueError):
        n = 0
    if isinstance(value, bool) or not 1 <= n <= most:
        raise SystemExit(f"repeat's {name} is a whole number from 1 to {most}, not {value!r}.")
    return n


def spec(value):
    """{every, interval, days, until (a date or None), count (or None)}, or None for no repeat"""
    if value is None or (isinstance(value, str) and value.strip().lower() in ("", "none")):
        return None
    if isinstance(value, str):
        key = value.strip().lower()
        if key not in PRESETS:
            raise SystemExit(f"repeat is one of {', '.join(PRESETS)}, none, or an object {{every, interval, days, "
                             f"until, count}}: not {value!r}.")
        every, interval, days = PRESETS[key]
        return {"every": every, "interval": interval, "days": list(days), "until": None, "count": None}
    if not isinstance(value, dict):
        raise SystemExit("repeat is a word (weekly) or an object {every, interval, days, until, count}.")
    if set(value) - KEYS:
        raise SystemExit(f"repeat takes every, interval, days, until and count, not {', '.join(sorted(set(value) - KEYS))}.")
    every = value.get("every")
    if every not in FREQS:
        raise SystemExit(f"repeat's every is day, week, month or year, not {every!r}.")
    interval = number(value.get("interval", 1), "interval", INTERVAL_MAX)
    days = value.get("days") or []
    if not isinstance(days, list) or any(str(d).upper() not in DAYS for d in days):
        raise SystemExit(f"repeat's days are a list of {', '.join(DAYS)}.")
    if days and every != "week":
        raise SystemExit("repeat's days are a weekly repeat's: every week.")
    days = [d for d in DAYS if d in {str(x).upper() for x in days}]
    until, count = value.get("until"), value.get("count")
    if until and count:
        raise SystemExit("repeat ends on a day (until) or after a number of times (count), not both.")
    if until:
        try:
            until = dt.date.fromisoformat(str(until))
        except ValueError:
            raise SystemExit(f"repeat's until is its last day, YYYY-MM-DD, not {until!r}.")
    return {"every": every, "interval": interval, "days": days, "until": until or None,
            "count": number(count, "count", COUNT_MAX) if count else None}


def local_day(value):
    """The day of a start, as the user sees it: a date, or an aware or floating time's local day"""
    if isinstance(value, dt.datetime):
        return (value.astimezone(write.local_zone()) if value.tzinfo else value).date()
    return value


def rule(s, start):
    """The vRecur of spec s for an event that starts at start"""
    day = local_day(start)
    if s["days"] and DAYS[day.weekday()] not in s["days"]:
        names = ", ".join(DAY_NAMES[d] for d in s["days"])
        raise SystemExit(f"It starts on a {day.strftime('%A')}, not on one of its days ({names}): start it on one.")
    r = {"FREQ": FREQS[s["every"]]}
    if s["interval"] > 1:
        r["INTERVAL"] = s["interval"]
    if s["days"]:
        r["BYDAY"] = list(s["days"])
    if s["until"]:
        if s["until"] < day:
            raise SystemExit("repeat's until is before the event starts.")
        # A timed event's UNTIL is UTC (RFC 5545): the last moment of that day here, so the day's time is in
        r["UNTIL"] = s["until"] if not isinstance(start, dt.datetime) else dt.datetime.combine(
            s["until"], dt.time(23, 59, 59), tzinfo=write.local_zone()).astimezone(dt.timezone.utc)
    if s["count"]:
        r["COUNT"] = s["count"]
    return icalendar.vRecur(r)


def set_rule(vevent, s):
    vevent.pop("rrule", None)
    if s is not None:
        vevent.add("rrule", rule(s, vevent.decoded("dtstart")))


def part(r, key):
    """A rule's part as a list: a vRecur read from a file has lists, one just made the values as given"""
    v = r.get(key)
    return [] if v is None else list(v) if isinstance(v, (list, tuple)) else [v]


def rules(vevent):
    found = vevent.get("rrule")
    return [] if found is None else found if isinstance(found, list) else [found]


def describe(s):
    """A spec in words: "Every weekday", "Every 2 weeks on Mon, Thu, until 2027-06-01", "Every month, 10 times" """
    if s["every"] == "week" and s["interval"] == 1 and s["days"] == WEEKDAYS:
        text = "Every weekday"
    else:
        text = f"Every {s['every']}" if s["interval"] == 1 else f"Every {s['interval']} {s['every']}s"
        if s["days"]:
            text += " on " + ", ".join(DAY_NAMES[d] for d in s["days"])
    if s["until"]:
        text += f", until {s['until']}"
    if s["count"]:
        text += f", {s['count']} times"
    return text


def read(vevent):
    """The event's repeat as spec() gives it (until as YYYY-MM-DD), with simple and text; None when it doesn't repeat"""
    found = rules(vevent)
    if not found:
        return {"simple": False, "text": "On days of its own"} if "rdate" in vevent else None
    r = found[0]
    every = EVERY.get(str((part(r, "FREQ") or [""])[0]).upper())
    days = [str(d).upper() for d in part(r, "BYDAY")]
    until = (part(r, "UNTIL") or [None])[0]
    s = {"every": every or "", "interval": int((part(r, "INTERVAL") or [1])[0]),
         "days": [d for d in DAYS if d in days], "until": local_day(until) if until else None,
         "count": int(part(r, "COUNT")[0]) if part(r, "COUNT") else None}
    simple = (every is not None and len(found) == 1 and set(k.upper() for k in r) <= SIMPLE and "rdate" not in vevent
              and all(d in DAYS for d in days) and (not days or every == "week"))
    text = describe(s) if every else "Repeating"
    return {**s, "until": s["until"].isoformat() if s["until"] else None, "simple": simple,
            "text": text if simple else text + " (a rule of its own)"}


def first(vevent):
    """DTSTART as the times are counted: an all-day event's day as a midnight without a zone, a floating time as local
    time (dateutil needs one kind of value throughout)"""
    start = vevent.decoded("dtstart")
    if not isinstance(start, dt.datetime):
        return dt.datetime.combine(start, dt.time())
    return start if start.tzinfo else start.replace(tzinfo=write.local_zone())


def like(value, start):
    """An EXDATE, RDATE, RECURRENCE-ID or UNTIL value as the same kind as start (first()'s)"""
    if start.tzinfo is None:   # all day: a day
        return dt.datetime.combine(local_day(value), dt.time())
    if not isinstance(value, dt.datetime):
        return dt.datetime.combine(value, start.timetz())
    return value if value.tzinfo else value.replace(tzinfo=write.local_zone())


def values(vevent, name):
    found = vevent.get(name)
    out = []
    for item in [] if found is None else found if isinstance(found, list) else [found]:
        out += [x.dt for x in getattr(item, "dts", [])]
    return out


def ruleset(master):
    start = first(master)
    rs = du.rruleset()
    for r in rules(master):
        parts = {k: v for k, v in r.items() if k.upper() != "UNTIL"}
        one = du.rrulestr(icalendar.vRecur(parts).to_ical().decode(), dtstart=start)
        if part(r, "UNTIL"):
            until = part(r, "UNTIL")[0]
            if not isinstance(until, dt.datetime) and start.tzinfo:   # a day: all of it
                until = dt.datetime.combine(until, dt.time(23, 59, 59), tzinfo=write.local_zone())
            one = one.replace(until=like(until, start))
        rs.rrule(one)
    rs.rdate(start)
    for v in values(master, "rdate"):
        rs.rdate(like(v, start))
    for v in values(master, "exdate"):
        rs.exdate(like(v, start))
    return rs


def times(master):
    return iter(ruleset(master))


def find(master, value):
    """The time of the series at value (first()'s kind), or None: one excluded (EXDATE) is none"""
    start = first(master)
    at = like(value, start)
    found = ruleset(master).between(at - dt.timedelta(seconds=1), at + dt.timedelta(seconds=1), inc=True)
    return found[0] if found else None


def native(value, master):
    """A time of times() or find() as the event's DTSTART has it: a day, a time in its zone, or a floating one"""
    start = master.decoded("dtstart")
    if not isinstance(start, dt.datetime):
        return value.date()
    if start.tzinfo is None:
        return value.astimezone(write.local_zone()).replace(tzinfo=None)
    return value.astimezone(start.tzinfo)
