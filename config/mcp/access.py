#!/usr/bin/env python3
"""What the user lets Claude use: Settings › Claude › Access, read for Nightdrive's MCP server (plan: Dashboard #1761).

~/.config/nightdrive/claude-access.json (Settings writes it, MCP 7 #1768):
    {"level": "normal", "act": false, "areas": {"mail": "read", "home-assistant": "off"}}
level    strict, normal or open: the preset the rows start from
areas    a row per area, each off, read or change ("reads and changes"); an area left out has its level's value
act      tools with consequences (sending, devices, installing), in the areas set to change; always through the
         confirmation card. Left out: the level's (only open has it)
A tool is listed, and can be called, only when its area allows its class; the server reads this file on every
tools/list and tools/call, so a change applies at once.

The file is written only here (`nightdrive mcp access …` runs this), so Settings and Welcome keep it in one shape:
    access.py                          what applies now, as JSON (Settings › Claude › Access reads it)
    access.py level strict|normal|open a preset: the rows and act go back to the level's
    access.py area NAME off|read|change one row; the level's own value isn't written, so the row follows the level again
    access.py act on|off               actions with consequences, whatever the level
"""

import json
import os
import re
import sys
import tempfile
from pathlib import Path

FILE = Path.home() / ".config/nightdrive/claude-access.json"

# The rows of Settings › Claude › Access, in their order. A plugin's tools may use its own id as an area instead;
# such an area has its level's value until it gets a row.
AREAS = {
    "nightdrive": "Nightdrive's docs and status",
    "mail": "Mail",
    "contacts": "Contacts",
    "calendar": "Calendar",
    "tasks": "Tasks",
    "notes": "Notes",
    "deck": "Deck",
    "ferry": "Ferry",
    "home-assistant": "Home Assistant",
    "notifications": "Notifications",
    "appearance": "Appearance",
    "sound-display": "Sound and display",
    "apps-files": "Apps and files",
    "software": "Software",
}
# The areas that are an app's (the plugin of the same id): Settings shows their rows only while it is installed
APPS = ("mail", "contacts", "calendar", "tasks", "notes", "deck", "ferry", "home-assistant")
VALUES = ("off", "read", "change")
# What each class needs of its area; act needs `act` on top
NEEDS = {"read": "read", "change": "change", "act": "change"}

# The presets: Strict gives only the docs and status, Normal reading and changes that can be undone, Open also the
# actions with consequences (each one still asks on the card)
LEVELS = {
    "strict": {"default": "off", "areas": {"nightdrive": "read"}, "act": False},
    "normal": {"default": "change", "areas": {}, "act": False},
    "open": {"default": "change", "areas": {}, "act": True},
}
# Without a file the user hasn't chosen yet (Welcome asks, #1768): Normal, since installing the server for Claude Code
# (`nightdrive mcp install`) is already the user's choice. A file that can't be read gives Strict: a typo mustn't
# open everything.
UNCHOSEN = "normal"
BROKEN = "strict"


class Access:
    def __init__(self, level=UNCHOSEN, areas=None, act=None, problem=None):
        self.level = level
        self.areas = areas or {}
        self.act = LEVELS[level]["act"] if act is None else act
        self.problem = problem  # why the file wasn't used as such, for the log

    def area(self, name):
        preset = LEVELS[self.level]
        return self.areas.get(name) or preset["areas"].get(name) or preset["default"]

    def allows(self, cls, area):
        """Whether a tool of this class in this area is Claude's to see and call."""
        need = NEEDS.get(cls)
        if need is None or VALUES.index(self.area(area)) < VALUES.index(need):
            return False
        return cls != "act" or self.act

    def summary(self, extra=()):
        """What applies now: every row's value (and those of extra areas, e.g. plugins' own), as JSON for Settings.
        chosen: the user has picked something (else the level is UNCHOSEN's); changed: the rows set apart from the
        level, and whether act is"""
        names = list(AREAS) + [a for a in sorted(set(extra) | set(self.areas)) if a not in AREAS]
        changed = sorted(a for a in self.areas if self.areas[a] != self.preset(a))
        return {"file": str(FILE), "chosen": FILE.exists(), "level": self.level, "act": self.act,
                "areas": {a: self.area(a) for a in names}, "names": AREAS, "apps": APPS,
                "changed": changed, "actChanged": self.act != LEVELS[self.level]["act"],
                **({"problem": self.problem} if self.problem else {})}

    def preset(self, name):
        """The row's value at this level, before the user's own"""
        preset = LEVELS[self.level]
        return preset["areas"].get(name) or preset["default"]


def load(path=FILE):
    try:
        data = json.loads(Path(path).read_text())
    except FileNotFoundError:
        return Access()
    except (OSError, ValueError) as e:
        return Access(BROKEN, problem=f"{path} can't be read ({e}): Strict until it's fixed")
    if not isinstance(data, dict):
        return Access(BROKEN, problem=f"{path} isn't a JSON object: Strict until it's fixed")
    level = data.get("level", UNCHOSEN)
    if level not in LEVELS:
        return Access(BROKEN, problem=f"{path}: unknown level {level!r}: Strict until it's fixed")
    areas, bad = {}, []
    rows = data.get("areas", {})
    for name, value in (rows.items() if isinstance(rows, dict) else []):
        if value in VALUES:
            areas[name] = value
        else:
            areas[name] = "off"  # a value we can't read closes its row rather than leaving the level's
            bad.append(name)
    act = data.get("act")
    if not isinstance(act, bool):
        act = None
    problem = f"{path}: unknown value for {', '.join(bad)}: off" if bad else None
    return Access(level, areas, act, problem)


def save(data, path=FILE):
    """Atomic (a temporary file renamed over it): the server may read it at any moment"""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".claude-access.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def write(now, path=FILE):
    """The file from an Access: only what differs from its level is written, so a row the user puts back to the
    level's value follows the level again. Built from what applies now, a broken or missing file starts from its
    level (Strict, Normal), not from nothing."""
    data = {"level": now.level}
    areas = {a: v for a, v in now.areas.items() if v != now.preset(a)}
    if areas:
        data["areas"] = areas
    if now.act != LEVELS[now.level]["act"]:
        data["act"] = now.act
    save(data, path)


def set_level(level, path=FILE):
    if level not in LEVELS:
        raise ValueError(f"unknown level {level!r}: {', '.join(LEVELS)}")
    write(Access(level), path)


def set_area(name, value, path=FILE):
    if value not in VALUES:
        raise ValueError(f"unknown value {value!r}: {', '.join(VALUES)}")
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,63}", name):
        raise ValueError(f"not an area: {name!r}")
    now = load(path)
    now.areas[name] = value
    write(now, path)


def set_act(on, path=FILE):
    now = load(path)
    now.act = on
    write(now, path)


def plugin_areas():
    """The areas of the installed plugins' own tools that have no row (registry.py knows them); none if it can't say"""
    try:
        from registry import Registry
        return {t.area for t in Registry().load()[0].values()}
    except Exception:  # Settings still shows the rows without them
        return set()


def main(argv):
    usage = "usage: access.py [level strict|normal|open | area NAME off|read|change | act on|off]"
    try:
        if not argv:
            json.dump(load().summary(plugin_areas()), sys.stdout, ensure_ascii=False, indent=2)
            print()
        elif argv[0] == "level" and len(argv) == 2:
            set_level(argv[1])
        elif argv[0] == "area" and len(argv) == 3:
            set_area(argv[1], argv[2])
        elif argv[0] == "act" and len(argv) == 2 and argv[1] in ("on", "off"):
            set_act(argv[1] == "on")
        else:
            print(usage, file=sys.stderr)
            return 2
    except (ValueError, OSError) as e:
        print(f"access: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
