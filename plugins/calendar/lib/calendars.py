#!/usr/bin/env python3
"""The calendars on this computer, as the sync has left them in DATA_DIR, and khal's config written from them.

    calendars.py [--json]     the calendars: id, name, colour, source, read_only, shared, events

A calendar is a folder DATA_DIR/<source>/<collection> (vdir: one .ics per event). Its id is "<source>/<collection>";
its name and colour are the files vdirsyncer's metasync writes beside the events (displayname, color), an ICS
source's name its calendars.conf `name`. A CalDAV collection that takes no events (components.py: iCloud's Reminders
lists) isn't a calendar.

khal reads the events (events.py): its config lists every calendar under its id, and is written again whenever the
calendars change, so a calendar added on the phone shows after the next sync.
"""

import json
import os
import sys
from pathlib import Path

import components
import sources

HOME = Path.home()
KHAL_CONFIG = sources.CONFIG_DIR / "khal"
# khal's own index of the events: a cache, rebuilt from the .ics files when missing
KHAL_DB = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "calendar/khal.db"
COLOR_DEFAULT = "#8E8E93"


def read(path, default=""):
    try:
        return path.read_text().strip()
    except OSError:
        return default


def color(text):
    """vdirsyncer keeps iCloud's #RRGGBBAA; khal and QML want #RRGGBB"""
    text = text.strip()
    if len(text) == 9 and text.startswith("#"):
        return text[:7]
    return text if len(text) == 7 and text.startswith("#") else COLOR_DEFAULT


def calendars():
    """[{id, name, color, source, read_only, shared, events, path}], the sources' order, then by name. shared: others
    see it (calendars.conf's `shared`), so what goes in it goes to them too"""
    out = []
    for s in sources.sources():
        base = sources.DATA_DIR / s["name"]
        folders = [base / sources.FEED] if s["kind"] == "ics" else sorted(p for p in base.glob("*") if p.is_dir())
        found = []
        for folder in folders:
            if not folder.is_dir():
                continue
            comps = read(folder / components.COMPONENTS)
            if comps and "VEVENT" not in comps.split():
                continue
            name = s.get("title") if s["kind"] == "ics" else read(folder / "displayname", folder.name)
            found.append({"id": f"{s['name']}/{folder.name}", "name": name, "color": color(s.get("color") or read(folder / "color")),
                          "source": s["name"],
                          "read_only": s["read_only"] or name.lower() in s.get("read_only_calendars", []),
                          "shared": s.get("shared", False) or name.lower() in s.get("shared_calendars", []),
                          "events": sum(1 for _ in folder.glob("*.ics")), "path": str(folder)})
        out += sorted(found, key=lambda c: c["name"].lower())
    return out


def find(calendar_id):
    """The calendar of that id, or None"""
    return next((c for c in calendars() if c["id"] == calendar_id), None)


def quote(text):
    """A value for khal's configobj file: in double quotes, which it can't hold, so they become single"""
    return '"' + text.replace('"', "'") + '"'


def write_khal(found):
    """khal's config for these calendars; the file is rewritten only when it changes (khal reindexes on a change)"""
    lines = [f"# Written by Calendar (plugins/calendar/lib/calendars.py) from the calendars in {sources.DATA_DIR}.",
             "[calendars]"]
    for c in found:
        lines += [f"[[{c['id']}]]", f"path = {quote(c['path'])}", f"color = {quote(c['color'])}",
                  f"readonly = {c['read_only']}"]
    lines += ["[locale]",
              # The formats events.py parses: ISO, whatever the user's locale
              'timeformat = "%H:%M"', 'dateformat = "%Y-%m-%d"', 'longdateformat = "%Y-%m-%d"',
              'datetimeformat = "%Y-%m-%dT%H:%M"', 'longdatetimeformat = "%Y-%m-%dT%H:%M"', "firstweekday = 0",
              "[sqlite]", f"path = {quote(str(KHAL_DB))}"]
    text = "\n".join(lines) + "\n"
    if read(KHAL_CONFIG) != text.strip():
        KHAL_CONFIG.parent.mkdir(parents=True, exist_ok=True)
        KHAL_DB.parent.mkdir(parents=True, exist_ok=True)
        tmp = KHAL_CONFIG.with_suffix(".tmp")
        tmp.write_text(text)
        tmp.replace(KHAL_CONFIG)
    return KHAL_CONFIG


def public(c):
    """A calendar as the command prints it: without its folder"""
    return {k: v for k, v in c.items() if k != "path"}


def main(argv):
    found = calendars()
    if "--json" in argv:
        print(json.dumps({"calendars": [public(c) for c in found]}, ensure_ascii=False))
        return
    if not found:
        print("No calendars yet: calendar sync, or README.md › Your calendars.")
    for c in found:
        print(f"{c['name']:24} {c['events']:5} events  {'read-only' if c['read_only'] else '':9}  ({c['id']})")


if __name__ == "__main__":
    main(sys.argv[1:])
