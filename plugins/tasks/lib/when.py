#!/usr/bin/env python3
"""When a task is due, as the command takes it and as it is shown.

    parse(text, now) -> date | datetime     [DAY] [TIME]: today, tomorrow, fri, +3d, 5.11., 2026-11-05 and 9:30,
                                            930, 14 (a time alone: the next such time), or +30m, +2h
    at(day, time, now) -> … | None          the window's two fields, either may be empty
    later(due, now) -> date | datetime      what the notification's Later moves a task to
    due_at(due) -> datetime                 when a due task is notified: a date at MORNING
    label(due, now, r) -> str               "Today 14:00", "Tomorrow", "Fri 6.11.", "3.11.2027": the region's way
                                            (region.py; r for tests), "Today 2:00 PM", "Fri 11/6" in the US

A time is read with am/pm too (3pm, 3:30 PM, 9 a.m.) in every region, as the kit's Regional.parseTime reads it: a US
user writes 12 h, and anyone may.
"""

import re
import sys
from datetime import date, datetime, time, timedelta
from pathlib import Path

# The kit's region.py (Settings › Region), through the app's link to the kit
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "app" / "kit"))
import region  # noqa: E402

MORNING = time(9, 0)   # an all-day task's notification, on its day
LATER = timedelta(hours=1)   # Later on a task with a time; one with only a date goes to the next day


WEEKDAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
WEEKDAYS_FULL = {d[:3]: d for d in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")}
HELP = ("give a day (today, tomorrow, fri, 5.11., 5.11.2027, 2026-11-05, +3d), a time (9:30, 930, 14, 3pm) or both "
        "(tomorrow 10, fri 930, fri 3:30 pm), or +30m, +2h")
TIME_HELP = "9:30, 930, 14 or 3pm."


def parse(text, now=None):
    """One text, as --due and Claude give it: [DAY] [TIME], or +30m / +2h / +3d. A time alone is the next such time"""
    now = now or datetime.now()
    t = " ".join(text.strip().lower().split())
    t = re.sub(r"^(\d{4}-\d{2}-\d{2})t", r"\1 ", t)    # ISO's 2026-11-05T10:00
    t = re.sub(r"(\d)\s+([ap]\.?(?:m\.?)?)$", r"\1\2", t)   # "3:30 pm" is one word, the time: "3:30pm"
    m = re.fullmatch(r"\+(\d+)\s*([mh])", t)
    if m:
        n = int(m.group(1))
        return (now + timedelta(minutes=n if m.group(2) == "m" else 60 * n)).replace(second=0, microsecond=0)
    words = t.split()
    # The last word is the time when it reads as one. So "5.11" alone is 05:11, and a day in one text needs its last
    # dot (5.11.); the window's day field has no such doubt (at())
    at_ = clock_of(words[-1]) if words else None
    if at_ is not None:
        words = words[:-1]
    elif words and re.fullmatch(r"[\d:.]+[ap]\.?(?:m\.?)?", words[-1]):
        raise ValueError(f"Can't read the time {words[-1]!r}: " + TIME_HELP)   # 14pm: a time, but not one
    if not words:
        if at_ is None:
            raise ValueError(f"Can't read the time {text!r}: " + HELP)
        x = datetime.combine(now.date(), at_)
        return x if x > now else x + timedelta(days=1)
    day = day_of(" ".join(words), now)
    return datetime.combine(day, at_) if at_ is not None else day


def at(day_text, time_text, now=None):
    """The window's two fields, a day and a time, either may be empty: None when both are. A time without a day is the
    next such time, as in parse()"""
    now = now or datetime.now()
    d = " ".join((day_text or "").lower().split())
    t = (time_text or "").strip().lower()
    clk = clock_of(t) if t else None
    if t and clk is None:
        raise ValueError(f"Can't read the time {time_text.strip()!r}: " + TIME_HELP)
    if not d:
        return parse(t, now) if t else None
    day = day_of(d, now)
    return datetime.combine(day, clk) if clk is not None else day


def clock_of(word):
    """9, 14, 930, 9:30, 09.30, 9:30:00, and with am/pm 3pm, 3:30 pm, 9 a.m., 12am (midnight) -> time; None when it
    isn't a time of day. The dots after a/p only with it, so a day's 5.11. never reads as 05:11"""
    m = re.fullmatch(r"(\d{1,2})(?:[:.]?(\d{2}))?(?::\d{2})?(?:\s*([ap])\.?(?:m\.?)?)?", word.strip())
    if not m:
        return None
    h, mi = int(m.group(1)), int(m.group(2) or 0)
    if m.group(3):
        if not 1 <= h <= 12:
            return None   # 14pm, 0am: not a 12 h time
        h = h % 12 + (12 if m.group(3) == "p" else 0)
    return time(h, mi) if h < 24 and mi < 60 else None


def day_of(text, now):
    """today, tomorrow, mon … sun (or monday: the next one, not today), +3d, 2026-11-05, 5.11., 5.11, 5.11.2027 (a day
    without a year is this year's)"""
    t = text.strip().lower()
    if t in ("today", "tomorrow"):
        return now.date() + timedelta(days=1 if t == "tomorrow" else 0)
    if t[:3] in WEEKDAYS and (len(t) == 3 or WEEKDAYS_FULL.get(t[:3]) == t):
        ahead = (WEEKDAYS.index(t[:3]) - now.weekday() - 1) % 7 + 1
        return now.date() + timedelta(days=ahead)
    m = re.fullmatch(r"\+(\d+)\s*d", t)
    if m:
        return now.date() + timedelta(days=int(m.group(1)))
    m = re.fullmatch(r"(\d{4})-(\d{1,2})-(\d{1,2})", t)
    ymd = m.groups() if m else None
    m = re.fullmatch(r"(\d{1,2})\.(\d{1,2})\.?(\d{4})?", t)
    if m:
        ymd = (m.group(3) or str(now.year), m.group(2), m.group(1))
    if ymd is None:
        raise ValueError(f"Can't read the day {text!r}: " + HELP)
    try:
        return date(int(ymd[0]), int(ymd[1]), int(ymd[2]))
    except ValueError:
        raise ValueError(f"No such date: {text.strip()}") from None


def due_at(due):
    return due if isinstance(due, datetime) else datetime.combine(due, MORNING)


def later(due, now=None):
    now = now or datetime.now()
    if due is None or isinstance(due, datetime):
        return (now + LATER).replace(second=0, microsecond=0)
    return now.date() + timedelta(days=1)


def label(due, now=None, r=None):
    if due is None:
        return ""
    now = now or datetime.now()
    r = r or region.current()
    day = due.date() if isinstance(due, datetime) else due
    diff = (day - now.date()).days
    if diff == 0:
        text = "Today"
    elif diff == 1:
        text = "Tomorrow"
    elif diff == -1:
        text = "Yesterday"
    elif 1 < diff < 7:
        text = region.fmt(day, "ddd " + r["day"])   # this week's: "Fri 6.11."
    else:
        text = region.fmt(day, r["day"] if day.year == now.year else r["short"])
    return f"{text} {region.fmt(due, r['time'])}" if isinstance(due, datetime) else text
