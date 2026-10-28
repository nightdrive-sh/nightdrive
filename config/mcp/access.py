#!/usr/bin/env python3
"""What the user lets Claude use: Settings › Claude › Access, read for Nightdrive's MCP server (plan: Dashboard #1761).

~/.config/nightdrive/claude-access.json (Settings writes it, MCP 7 #1768):
    {"level": "normal", "act": false, "areas": {"mail": "read", "home-assistant": "off"}}
level    strict, normal or open: the preset the rows start from
areas    a row per area, each off, read or change ("reads and changes"); an area left out has its level's value
act      tools with consequences (sending, devices, installing), in the areas set to change; always through the
         confirmation card. Left out: the level's (only open has it)
A tool is listed, and can be called, only when its area allows its class; the server reads this file on every
tools/list and tools/call, so a change applies at once. `python3 access.py` prints what applies now, as JSON.
"""

import json
import sys
from pathlib import Path

FILE = Path.home() / ".config/nightdrive/claude-access.json"

# The rows of Settings › Claude › Access, in their order. A plugin's tools may use its own id as an area instead;
# such an area has its level's value until it gets a row.
AREAS = {
    "nightdrive": "Nightdrive's docs and status",
    "mail": "Mail",
    "contacts": "Contacts",
    "calendar": "Calendar",
    "reminders": "Reminders",
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
        """What applies now: every row's value (and those of extra areas, e.g. plugins' own), as JSON for Settings."""
        names = list(AREAS) + [a for a in sorted(set(extra) | set(self.areas)) if a not in AREAS]
        return {"file": str(FILE), "level": self.level, "act": self.act,
                "areas": {a: self.area(a) for a in names}, **({"problem": self.problem} if self.problem else {})}


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


if __name__ == "__main__":
    json.dump(load().summary(), sys.stdout, ensure_ascii=False, indent=2)
    print()
