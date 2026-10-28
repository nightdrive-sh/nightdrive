#!/usr/bin/env python3
"""When a task is due, as the command takes it and as it is shown.

    parse(text, now) -> date | datetime     YYYY-MM-DD, YYYY-MM-DD HH:MM (or T), HH:MM (the next such time), today,
                                            tomorrow (with a time or not), +30m, +2h, +3d
    later(due, now) -> date | datetime      what the notification's Later moves a task to
    due_at(due) -> datetime                 when a due task is notified: a date at MORNING
    label(due, now) -> str                  "Today 14:00", "Tomorrow", "Fri 30 Oct", "3 Nov 2027"
"""

import re
from datetime import date, datetime, time, timedelta

MORNING = time(9, 0)   # an all-day task's notification, on its day
LATER = timedelta(hours=1)   # Later on a task with a time; one with only a date goes to the next day


def parse(text, now=None):
    now = now or datetime.now()
    t = " ".join(text.strip().lower().split())
    m = re.fullmatch(r"\+(\d+)\s*([mhd])", t)
    if m:
        n, unit = int(m.group(1)), m.group(2)
        if unit == "d":
            return now.date() + timedelta(days=n)
        return (now + timedelta(minutes=n if unit == "m" else 60 * n)).replace(second=0, microsecond=0)
    m = re.fullmatch(r"(today|tomorrow)(?: (\d{1,2})[:.](\d{2}))?", t)
    if m:
        day = now.date() + timedelta(days=1 if m.group(1) == "tomorrow" else 0)
        return datetime.combine(day, clock(m.group(2), m.group(3))) if m.group(2) else day
    m = re.fullmatch(r"(\d{1,2})[:.](\d{2})", t)
    if m:
        at = datetime.combine(now.date(), clock(m.group(1), m.group(2)))
        return at if at > now else at + timedelta(days=1)
    m = re.fullmatch(r"(\d{4}-\d{2}-\d{2})(?:[ t](\d{1,2}):(\d{2})(?::\d{2})?)?", t)
    if m:
        try:
            day = date.fromisoformat(m.group(1))
        except ValueError:
            raise ValueError(f"No such date: {m.group(1)}") from None
        return datetime.combine(day, clock(m.group(2), m.group(3))) if m.group(2) else day
    raise ValueError(f"Can't read the time {text!r}: give YYYY-MM-DD, YYYY-MM-DD HH:MM, HH:MM, today, tomorrow "
                     "(with HH:MM or not), or +30m, +2h, +3d")


def clock(h, m):
    try:
        return time(int(h), int(m))
    except ValueError:
        raise ValueError(f"No such time: {h}:{m}") from None


def due_at(due):
    return due if isinstance(due, datetime) else datetime.combine(due, MORNING)


def later(due, now=None):
    now = now or datetime.now()
    if due is None or isinstance(due, datetime):
        return (now + LATER).replace(second=0, microsecond=0)
    return now.date() + timedelta(days=1)


def label(due, now=None):
    if due is None:
        return ""
    now = now or datetime.now()
    day = due.date() if isinstance(due, datetime) else due
    diff = (day - now.date()).days
    if diff == 0:
        text = "Today"
    elif diff == 1:
        text = "Tomorrow"
    elif diff == -1:
        text = "Yesterday"
    elif 1 < diff < 7:
        text = day.strftime("%a %-d %b")
    else:
        text = day.strftime("%-d %b" if day.year == now.year else "%-d %b %Y")
    return f"{text} {due:%H:%M}" if isinstance(due, datetime) else text
