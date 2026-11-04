#!/usr/bin/env python3
"""Calendar's settings, ~/.config/calendar/settings.json: read by the reminders (remind.py) and shown and changed in the
window's Settings (⌘,) through `calendar reminders on|off|default`, so the window and the timer read one file.

    get() -> dict          every setting, the defaults filled in
    put(key, value)        one changed, written whole (atomically: the timer may read it at that moment)

reminders: notifications of the events' reminders (on by default). default_reminder: minutes before a timed event's
start for one without a reminder of its own, None for no default (Jari 4.11.: none, only the events' own).
"""

import json

import sources

FILE = sources.CONFIG_DIR / "settings.json"
DEFAULTS = {"reminders": True, "default_reminder": None}
DEFAULT_CHOICES = (None, 0, 5, 10, 15, 30, 60)   # what the window offers, and what the command takes


def get():
    try:
        data = json.loads(FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    out = dict(DEFAULTS)
    if isinstance(data, dict):
        out.update({k: v for k, v in data.items() if k in DEFAULTS})
    if out["default_reminder"] not in DEFAULT_CHOICES:   # a hand-edited value the window couldn't show
        out["default_reminder"] = None
    out["reminders"] = bool(out["reminders"])
    return out


def put(key, value):
    data = get()
    data[key] = value
    FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    tmp.replace(FILE)
    return data
