#!/usr/bin/env python3
"""How many different people Claude has had from the contacts lately (Dashboard #1884): lookup.py's find and card
count them here for Claude's calls, and refuse past PER_HOUR.

A search needs a word of 2 characters, but "aa", "ab" … "zz" (or "358 a" …) still reads the whole address book in a
few dozen calls, and on Open no card asks about any of them. Finding someone, or the handful a task needs, is far
below the limit; reading everyone isn't. Only the people's ids and when Claude first got each one are kept, in the
user's own state folder, for WINDOW seconds.
"""

import fcntl
import json
import os
import time
from pathlib import Path

PER_HOUR = 100   # different people Claude gets in WINDOW: a task's handful, not an address book
WINDOW = 3600    # seconds
FILE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "nightdrive/contacts-claude.json"


def read():
    try:
        data = json.loads(FILE.read_text())
    except (OSError, ValueError):
        return {}
    return {k: v for k, v in data.items() if isinstance(v, (int, float))} if isinstance(data, dict) else {}


def write(data):
    tmp = FILE.with_name(FILE.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)
    os.replace(tmp, FILE)


def take(ids, now=None):
    """Counts ids as given to Claude now. LookupError, and nothing counted, when the new ones would make more than
    PER_HOUR different people in WINDOW."""
    ids = [i for i in dict.fromkeys(ids) if isinstance(i, str) and i]
    if not ids:
        return
    now = time.time() if now is None else now
    FILE.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with open(FILE.parent / ".contacts-claude.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)   # two calls at once mustn't both fit under the limit
        seen = {k: t for k, t in read().items() if now - WINDOW < t <= now}
        new = [i for i in ids if i not in seen]
        if len(seen) + len(new) > PER_HOUR:
            frees = time.strftime("%H:%M", time.localtime(min(seen.values(), default=now) + WINDOW))
            raise LookupError(f"Not given: Claude has had {len(seen)} different people from the contacts in the last "
                              f"hour, and {PER_HOUR} is the most, so the address book can't be read search by "
                              f"search. More from {frees}; or the user can look them up in Contacts.")
        seen.update({i: now for i in new})
        write(seen)
