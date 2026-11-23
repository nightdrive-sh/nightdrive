#!/usr/bin/env python3
"""Contacts' settings, ~/.config/contacts/settings.json: read by cards.py, shown and changed in the window's Settings
(⌘,) through `contacts sort`, so the window and the command read one file.

    settings.py sort [first|last] [--json]    the list's order: by first name (the default) or by last name

sort: "first" orders the list by the name as it is shown (Anna Virtanen under A), "last" by the family name, then the
given name (Anna Virtanen under V). A card without a family name (a company) goes by its name either way.
"""

import json
import os
import sys
from pathlib import Path

FILE = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "contacts/settings.json"
DEFAULTS = {"sort": "first"}
SORTS = ("first", "last")


def get():
    """Every setting, the defaults filled in; a value the window couldn't show goes back to its default"""
    try:
        data = json.loads(FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    out = dict(DEFAULTS)
    if isinstance(data, dict):
        out.update({k: v for k, v in data.items() if k in DEFAULTS})
    if out["sort"] not in SORTS:
        out["sort"] = DEFAULTS["sort"]
    return out


def put(key, value):
    """One setting changed, the file written whole (atomically: cards.py may be reading it)"""
    data = get()
    data[key] = value
    FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    tmp.replace(FILE)
    return data


def main(args):
    as_json = "--json" in args
    args = [a for a in args if a != "--json"]
    if not args or args[0] != "sort" or len(args) > 2:
        sys.exit(__doc__)
    if len(args) == 2:
        if args[1] not in SORTS:
            sys.exit(f"contacts sort: first or last, not {args[1]!r}")
        put("sort", args[1])
    sort = get()["sort"]
    print(json.dumps({"sort": sort}) if as_json else f"Sorted by {sort} name")


if __name__ == "__main__":
    main(sys.argv[1:])
