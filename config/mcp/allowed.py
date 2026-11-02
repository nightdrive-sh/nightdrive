#!/usr/bin/env python3
"""What the user allowed once on Nightdrive's card for good (#1929): a tool's `asks_if` that prints `first KEY` asks
the first time Claude calls it for KEY (a calendar Claude hasn't added to yet), and once the user allows that call,
the same tool runs for KEY without the card from then on. A refusal or a timeout remembers nothing.

~/.config/nightdrive/claude-allowed.json, beside Access's file (access.py), written by the MCP server only:
    {"version": 1, "allowed": {"calendar_add": ["Family (icloud/home)"]}}

What can't be read is nothing allowed: every call then asks again, which is the safe side. The user forgets one with
`nightdrive mcp access forget TOOL [KEY]` (without KEY, all of the tool's), and `nightdrive mcp access allowed` lists
them.
"""

import json
import os
import re
import tempfile
from pathlib import Path

FILE = Path.home() / ".config/nightdrive/claude-allowed.json"
VERSION = 1
# A key is one line a card can show: what the tool prints, which may be a server's text (a calendar's name)
KEY = re.compile(r"[^\x00-\x1f\x7f]{1,200}")


def path_of(path):
    return Path(FILE if path is None else path)   # FILE when called, not when defined: tests point it elsewhere


def load(path=None):
    """{tool: [key, …]}; a missing or broken file is none."""
    try:
        data = json.loads(path_of(path).read_text())
    except (OSError, ValueError):
        return {}
    found = data.get("allowed") if isinstance(data, dict) else None
    if not isinstance(found, dict):
        return {}
    return {tool: [k for k in keys if isinstance(k, str)] for tool, keys in found.items()
            if isinstance(tool, str) and isinstance(keys, list)}


def save(allowed, path=None):
    """Atomic (a temporary file renamed over it): the server may read it at any moment"""
    path = path_of(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {"version": VERSION, "allowed": {t: sorted(set(k)) for t, k in sorted(allowed.items()) if k}}
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".claude-allowed.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def has(tool, key, path=None):
    return key in load(path).get(tool, [])


def remember(tool, key, path=None):
    if not KEY.fullmatch(key):
        raise ValueError(f"not a key: {key!r}")
    allowed = load(path)
    if key not in allowed.get(tool, []):
        allowed.setdefault(tool, []).append(key)
        save(allowed, path)


def forget(tool, key=None, path=None):
    """Forget one key of a tool, or all of them: the next call asks again. How many were forgotten."""
    allowed = load(path)
    keys = allowed.get(tool, [])
    gone = [k for k in keys if key is None or k == key]
    if gone:
        allowed[tool] = [k for k in keys if k not in gone]
        save(allowed, path)
    return len(gone)


def lines(path=None):
    """What `nightdrive mcp access allowed` prints: a tool and a key a line"""
    return [f"{tool}\t{key}" for tool, keys in sorted(load(path).items()) for key in sorted(keys)]
