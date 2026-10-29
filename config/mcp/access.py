#!/usr/bin/env python3
"""What the user lets Claude use: Settings › Claude › Access, read by Nightdrive's MCP server (plan: Dashboard #1761,
the model #1831).

~/.config/nightdrive/claude-access.json (the Access window and Welcome write it, through this file only):
    {"version": 2, "level": "normal", "areas": {"mail": {"read": "allow"}, "software": {"modify": "no"}},
     "options": {"home-assistant": {"unlock": true}}}
level    strict, normal or open (levels.py): what every area's rights are to begin with
areas    the user's own: per area, read / modify / delete, each allow, ask or no. Only what differs from the level is
         written, so a right put back to the level's value follows the level again
options  the user's own of an area's own choices (areas.options: Home Assistant's locks, #1830), true or false, the
         same way. What can't be read is off: these only ever allow more
A tool belongs to one right of its area (registry.Tool.right). No: it isn't listed and can't be called. Ask: it runs
only after the user allows that call on Nightdrive's card. Allow: it runs (a change with Undo). A tool with
consequences (class act) is at most Ask. The server reads this file on every tools/list and tools/call, so a change
applies at once.

Version 1 (until #1831: a row per area off, read or change, and act on or off) is read as version 2 and written as
such on the next change: off → all No; read → Modify and Delete No, and reading follows the level (Normal asks for
the private areas); change → the level's; act is gone, the card's Ask is built in.

    access.py                                  what applies, as JSON (the Access window and the launcher read it)
    access.py level strict|normal|open         a level: your own values go back to it
    access.py set AREA read|modify|delete allow|ask|no
    access.py option AREA OPTION on|off
"""

import json
import os
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import areas  # noqa: E402  (after the path above)
from areas import AREAS, RIGHTS  # noqa: E402,F401  (registry.py checks a tool's area against AREAS)
from levels import LEVELS, VALUES, option_preset, preset  # noqa: E402

FILE = Path.home() / ".config/nightdrive/claude-access.json"
VERSION = 2
# Without a file: Normal, since installing the server for Claude Code (`nightdrive mcp install`, Welcome's or Access's
# switch) is already the user's choice. A file that can't be read gives Strict: a typo mustn't open everything.
UNCHOSEN = "normal"
BROKEN = "strict"
AREA_ID = re.compile(r"[a-z][a-z0-9-]{0,63}")


class Access:
    def __init__(self, level=UNCHOSEN, own=None, problem=None, own_options=None):
        self.level = level
        self.own = own or {}          # {area: {right: value}}: the user's, apart from the level
        self.own_options = own_options or {}   # {area: {option: bool}}: the same for the areas' own choices
        self.problem = problem        # why the file wasn't used as such, for the log

    def preset(self, area, right):
        return preset(self.level, area, right)

    def value(self, area, right):
        """The right's value as set: the user's own, else the level's."""
        return self.own.get(area, {}).get(right) or self.preset(area, right)

    def decide(self, cls, area, right):
        """allow, ask or no for a call of a tool of this class and right in this area. A tool with consequences
        never runs without the card."""
        value = self.value(area, right)
        return "ask" if value == "allow" and cls == "act" else value

    def option(self, area, option):
        """Whether one of an area's own choices is on: the user's, else the level's."""
        own = self.own_options.get(area, {}).get(option)
        return own if own is not None else option_preset(self.level, area, option)

    def options(self, area):
        """All of an area's own choices as {id: bool}: what its tools' commands get (run.environment)."""
        return {o["id"]: self.option(area, o["id"]) for o in areas.options(area)}

    def count_own(self):
        own = sum(len(v) for v in self.own.values())
        return own + sum(on != option_preset(self.level, area, option)
                         for area, chosen in self.own_options.items() for option, on in chosen.items())

    def summary(self, tools=()):
        """What applies now, for the Access window and the launcher: every area that has tools, with its rights, and
        each right's tools; a right without tools isn't there. tools: registry's Tool objects (the installed ones)."""
        by_area = {}
        for t in tools:
            by_area.setdefault(t.area, {}).setdefault(t.right, []).append(t)
        names = [a for a in AREAS if a in by_area] + sorted(a for a in by_area if a not in AREAS)
        rows = []
        for a in names:
            rights = {}
            for r in RIGHTS:
                found = by_area[a].get(r)
                if not found:
                    continue
                consequential = all(t.cls == "act" for t in found)
                # Where every tool asks anyway, Allow shows as the Ask it is
                shown = (lambda v: "ask" if consequential and v == "allow" else v)
                rights[r] = {
                    "value": shown(self.value(a, r)), "preset": shown(self.preset(a, r)),
                    "own": shown(self.value(a, r)) != shown(self.preset(a, r)),
                    # Allow isn't offered where every tool asks anyway: it would say something that isn't so
                    "choices": ["ask", "no"] if consequential else list(VALUES),
                    "words": areas.words(a, r),
                    "tools": [{"name": t.name, "title": t.spec.get("title") or t.name,
                               "asks": t.cls == "act", "undo": t.cls == "change"} for t in found],
                }
            options = [{**o, "value": self.option(a, o["id"]), "preset": option_preset(self.level, a, o["id"]),
                        "own": self.option(a, o["id"]) != option_preset(self.level, a, o["id"])}
                       for o in areas.options(a)]
            rows.append({"id": a, "name": areas.name(a), "glyph": areas.glyph(a), "rights": rights,
                         "options": options})
        return {"file": str(FILE), "chosen": FILE.exists(), "level": self.level, "levels": list(LEVELS),
                "own": self.count_own(), "areas": rows, **({"problem": self.problem} if self.problem else {})}


def from_v1(data, path):
    """A version 1 file's rows as version 2's own values (see the docstring); what can't be read closes its area."""
    own, bad = {}, []
    rows = data.get("areas", {})
    for name, value in (rows.items() if isinstance(rows, dict) else []):
        if value == "change":
            continue
        if value not in ("off", "read"):
            bad.append(name)
        closed = ("modify", "delete") if value == "read" else RIGHTS
        own[name] = {r: "no" for r in closed}
    # The picture of a window was Apps and files' until it got a row of its own
    if "apps-files" in own and "read" in own["apps-files"]:
        own["screen"] = {"read": "no"}
    problem = f"{path}: unknown value for {', '.join(bad)}: off" if bad else None
    return own, problem


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
    version = data.get("version", 1)
    if version == 1:
        own, problem = from_v1(data, path)
        return Access(level, own, problem)
    if version != VERSION:
        return Access(BROKEN, problem=f"{path}: version {version!r} is newer than this Nightdrive: Strict until "
                                      "it's updated")
    own, bad = {}, []
    rows = data.get("areas", {})
    for name, rights in (rows.items() if isinstance(rows, dict) else []):
        if not isinstance(rights, dict):
            own[name] = {r: "no" for r in RIGHTS}   # what we can't read closes its area rather than opening it
            bad.append(name)
            continue
        for right, value in rights.items():
            if right not in RIGHTS:
                bad.append(f"{name}.{right}")
            elif value in VALUES:
                own.setdefault(name, {})[right] = value
            else:
                own.setdefault(name, {})[right] = "no"
                bad.append(f"{name}.{right}")
    own_options = {}
    rows = data.get("options", {})
    for name, chosen in (rows.items() if isinstance(rows, dict) else []):
        for option, value in (chosen.items() if isinstance(chosen, dict) else []):
            if isinstance(value, bool):
                own_options.setdefault(name, {})[option] = value
            else:
                own_options.setdefault(name, {})[option] = False   # off: an option only ever allows more
                bad.append(f"{name}.{option}")
        if not isinstance(chosen, dict):
            own_options[name] = {o["id"]: False for o in areas.options(name)}
            bad.append(name)
    problem = f"{path}: unknown value for {', '.join(bad)}: No" if bad else None
    return Access(level, own, problem, own_options)


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
    """The file from an Access, as version 2 with only what differs from the level. A broken or missing file starts
    from its level (Strict, Normal), not from nothing."""
    data = {"version": VERSION, "level": now.level}
    own = {}
    for area, rights in sorted(now.own.items()):
        kept = {r: v for r, v in rights.items() if v != now.preset(area, r)}
        if kept:
            own[area] = {r: kept[r] for r in RIGHTS if r in kept}
    if own:
        data["areas"] = own
    options = {}
    for area, chosen in sorted(now.own_options.items()):
        kept = {o: v for o, v in sorted(chosen.items()) if v != option_preset(now.level, area, o)}
        if kept:
            options[area] = kept
    if options:
        data["options"] = options
    save(data, path)


def set_level(level, path=FILE):
    if level not in LEVELS:
        raise ValueError(f"unknown level {level!r}: {', '.join(LEVELS)}")
    write(Access(level), path)


def set_value(area, right, value, path=FILE):
    if not AREA_ID.fullmatch(area):
        raise ValueError(f"not an area: {area!r}")
    if right not in RIGHTS:
        raise ValueError(f"unknown right {right!r}: {', '.join(RIGHTS)}")
    if value not in VALUES:
        raise ValueError(f"unknown value {value!r}: {', '.join(VALUES)}")
    now = load(path)
    now.own.setdefault(area, {})[right] = value
    write(now, path)


def set_option(area, option, value, path=FILE):
    known = [o["id"] for o in areas.options(area)]
    if option not in known:
        raise ValueError(f"{area} has no option {option!r}" + (f": {', '.join(known)}" if known else ""))
    if value not in ("on", "off"):
        raise ValueError(f"unknown value {value!r}: on, off")
    now = load(path)
    now.own_options.setdefault(area, {})[option] = value == "on"
    write(now, path)


def installed_tools():
    """The tools of the core and the installed plugins (registry.py knows them); none if it can't say."""
    try:
        from registry import Registry
        return list(Registry().load()[0].values())
    except Exception:  # the window still shows the levels without them
        return []


def main(argv):
    usage = ("usage: access.py [level strict|normal|open | set AREA read|modify|delete allow|ask|no | "
             "option AREA OPTION on|off]")
    try:
        if not argv:
            json.dump(load().summary(installed_tools()), sys.stdout, ensure_ascii=False, indent=2)
            print()
        elif argv[0] == "level" and len(argv) == 2:
            set_level(argv[1])
        elif argv[0] == "set" and len(argv) == 4:
            set_value(*argv[1:])
        elif argv[0] == "option" and len(argv) == 4:
            set_option(*argv[1:])
        else:
            print(usage, file=sys.stderr)
            return 2
    except (ValueError, OSError) as e:
        print(f"access: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
