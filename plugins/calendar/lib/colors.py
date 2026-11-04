#!/usr/bin/env python3
"""A calendar's own colour, picked here over the one its server or calendars.conf gives (#2031).

    colors.py [--json]                       the palette, and the calendars' colours
    colors.py [--json] ID [NAME|#RRGGBB]     a calendar's colour, or set it (a palette name or any #RRGGBB)
    colors.py [--json] ID reset              back to the server's (or calendars.conf's) colour

The choice is kept in COLORS ({calendar id: "#rrggbb"}), apart from the sync's files: metasync rewrites a calendar's
`color` file on every sync, so a choice written there would be lost, and calendars.conf is the user's own text, which
a rewrite by configparser would strip of its comments. It stays on this computer: the colour on the phone and at
icloud.com doesn't change (writing it back would need a PROPPATCH vdirsyncer doesn't do).

calendars.py applies it, so `calendar calendars`, the events, khal's config and every view of the window follow.
"""

import json
import re
import sys
from pathlib import Path

import sources

COLORS = sources.CONFIG_DIR / "colors.json"
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

# The colours offered: the theme's own, so a calendar looks at home in every theme. The theme colours' main shade
# (config/hypr/scripts/theme, `theme list`), graphite's grey, and Theme.qml's red, orange and green state colours for
# the hues the themes don't have; not rose's, which beside the red was hard to tell apart. Fixed values, not the
# current theme's: a calendar keeps its colour when the theme changes. colors_test.py checks them against the theme.
PALETTE = [
    ("red", "#f7768e"), ("orange", "#ff9e64"), ("amber", "#e8b974"), ("lime", "#9ece6a"), ("green", "#83d998"),
    ("teal", "#7ae2de"), ("blue", "#7198eb"), ("violet", "#c071eb"), ("graphite", "#aeaeae"),
]


def chosen():
    """{calendar id: "#rrggbb"}: the colours picked here; a missing or broken file is none"""
    try:
        data = json.loads(COLORS.read_text())
    except (OSError, ValueError):
        return {}
    return {k: v.lower() for k, v in data.items() if isinstance(v, str) and HEX_RE.match(v)} if isinstance(data, dict) else {}


def save(data):
    """COLORS written whole, by a rename: the window and a sync may read it at any moment"""
    COLORS.parent.mkdir(parents=True, exist_ok=True)
    tmp = COLORS.with_suffix(".tmp")
    tmp.write_text(json.dumps(dict(sorted(data.items())), indent=1) + "\n")
    tmp.replace(COLORS)


def parse(text):
    """A palette name or #RRGGBB as "#rrggbb", or None"""
    text = text.strip().lower()
    named = dict(PALETTE).get(text)
    if named:
        return named
    return text if HEX_RE.match(text) else None


def name_of(hexcol):
    """The palette's name for a colour, or "" for one of its own"""
    return next((n for n, h in PALETTE if h == hexcol.lower()), "")


def set_color(calendar_id, value):
    """Sets (or with "reset" takes away) a calendar's colour; returns {id, name, color, color_name, previous, custom}.
    color_name: the palette's name for it, or "" (one of its own, or the server's)
    previous is the colour picked before, "" for none: what an undo gives back (`reset` for "")"""
    import calendars    # here: calendars imports this module
    cal = calendars.find(calendar_id)
    if not cal:
        raise SystemExit(f"No calendar {calendar_id}: calendar calendars lists them.")
    data = chosen()
    previous = data.get(calendar_id, "")
    if value.strip().lower() in ("reset", ""):
        data.pop(calendar_id, None)
    else:
        hexcol = parse(value)
        if not hexcol:
            raise SystemExit(f"Not a colour: {value} (a #RRGGBB, or one of {', '.join(n for n, _ in PALETTE)}).")
        data[calendar_id] = hexcol
    save(data)
    cal = calendars.find(calendar_id)
    return {"id": cal["id"], "name": cal["name"], "color": cal["color"],
            "color_name": name_of(cal["color"]) if cal["custom"] else "", "previous": previous or "reset",
            "custom": cal["custom"]}


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    import calendars
    if len(args) >= 2:
        out = set_color(args[0], args[1])
        print(json.dumps(out, ensure_ascii=False) if as_json else f"{out['name']}: {out['color']}")
        return
    cals = [{k: c[k] for k in ("id", "name", "color", "custom", "own_color")} for c in calendars.calendars()
            if not args or c["id"] == args[0]]
    if args and not cals:
        raise SystemExit(f"No calendar {args[0]}: calendar calendars lists them.")
    if as_json:
        print(json.dumps({"palette": [{"name": n, "color": h} for n, h in PALETTE], "calendars": cals},
                         ensure_ascii=False))
        return
    for c in cals:
        print(f"{c['name']:24} {c['color']}  {name_of(c['color']):9} {'(own)' if c['custom'] else ''}")
    if not args:
        print("\nColours: " + ", ".join(n for n, _ in PALETTE) + ", or any #RRGGBB")


if __name__ == "__main__":
    main(sys.argv[1:])
