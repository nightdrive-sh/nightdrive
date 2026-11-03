#!/usr/bin/env python3
"""Settings › Region for what Tasks writes outside its window: the notifications, `tasks list` and Claude's due_label.

The window formats with the kit's Regional.qml; this is the same region (LC_TIME in locale.conf, the entry of
regions.json), read through hypr/scripts/region so there is one reading of it, and the same patterns (Dates.js):

    current() -> dict          the region's entry: short, day, time …; ISO's when it can't be read
    fmt(d, pattern) -> str     "d.M.", "M/d/yyyy", "h:mm AP" written out, English names as the kit's
"""

import importlib.machinery
import importlib.util
import re
from functools import cache
from pathlib import Path

# The kit's folder is linked into the app (app/kit), and the region script sits beside the kit in the config
KIT = Path(__file__).resolve().parents[1] / "app" / "kit"
SCRIPT = KIT.resolve().parents[1] / "hypr" / "scripts" / "region"
ISO = {"name": "ISO 8601", "order": "ymd", "short": "yyyy-MM-dd", "day": "MM-dd", "medium": "d MMM yyyy",
       "long": "ddd d MMMM yyyy", "time": "HH:mm", "weekStart": 1}   # Regional.qml's own fallback
MONTHS = ("January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
          "November", "December")
DAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")   # date.weekday()'s order


@cache
def current():
    """Once a process, not once a row: each command and each notification is a process of its own, so a change of
    region shows in the next one"""
    try:
        loader = importlib.machinery.SourceFileLoader("nightdrive_region", str(SCRIPT))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        mod = importlib.util.module_from_spec(spec)
        loader.exec_module(mod)
        table = mod.regions()
        return table[mod.current(table)]
    except Exception:   # no script, no regions.json, a broken file: the dates still show, unambiguously
        return ISO


# Longest first, so "MMMM" isn't read as "MM" twice
TOKENS = re.compile(r"yyyy|yy|MMMM|MMM|MM|M|dddd|ddd|dd|d|HH|H|hh|h|mm|AP")


def fmt(d, pattern):
    def one(m):
        t = m.group(0)
        if t == "yyyy": return f"{d.year}"
        if t == "yy": return f"{d.year % 100:02}"
        if t == "MMMM": return MONTHS[d.month - 1]
        if t == "MMM": return MONTHS[d.month - 1][:3]
        if t == "MM": return f"{d.month:02}"
        if t == "M": return f"{d.month}"
        if t == "dddd": return DAYS[d.weekday()]
        if t == "ddd": return DAYS[d.weekday()][:3]
        if t == "dd": return f"{d.day:02}"
        if t == "d": return f"{d.day}"
        h = getattr(d, "hour", 0)
        if t == "HH": return f"{h:02}"
        if t == "H": return f"{h}"
        if t == "hh": return f"{(h % 12 or 12):02}"
        if t == "h": return f"{h % 12 or 12}"
        if t == "mm": return f"{getattr(d, 'minute', 0):02}"
        return "AM" if h < 12 else "PM"
    return TOKENS.sub(one, pattern)
