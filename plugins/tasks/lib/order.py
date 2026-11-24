#!/usr/bin/env python3
"""A list's tasks in the user's own order (#3507): X-APPLE-SORT-ORDER, an integer per VTODO, lowest first.

That property, not one of our own, because the CalDAV clients a sync (#2024) would meet read and write it: Nextcloud
Tasks, tasks.org (DAVx5), Apple's CalDAV Reminders. A task without one sorts by when it was made, as Nextcloud reads
it: the seconds from 2001-01-01 (Apple's epoch) to its CREATED, so a new task comes last and nothing needs writing
until the user moves one.

A move writes the moved task alone, with a value between its new neighbours'. A task is one file, and Hub merges a
file field by field (merge.py), so two computers that each moved a different task both keep their move; renumbering
the whole list on every move would have made every file a conflict. Only when the neighbours leave no integer between
them is the list renumbered, STEP apart.
"""

from datetime import datetime, timezone

import ics

FIELD = "X-APPLE-SORT-ORDER"
EPOCH = datetime(2001, 1, 1)
STEP = 1024     # the gap a renumbered list, and a move to either end, leaves: many moves between two before the next


def key(task):
    """The task's place: its own value, else the seconds from 2001 to its CREATED (0 without one)"""
    v = task.get(FIELD).strip()
    if v.lstrip("-").isdigit():
        return int(v)
    made = task.time("CREATED")
    if made is None:
        return 0
    if not isinstance(made, datetime):
        made = datetime.combine(made, datetime.min.time())
    # In UTC, as Nextcloud counts: computers in two zones then agree on the tasks no one has moved yet
    utc = made.astimezone(timezone.utc).replace(tzinfo=None)
    return int((utc - EPOCH).total_seconds())


def sort_key(task):
    """Ties (two made in the same second, or values copied from another app) by CREATED, then the UID, so every
    computer shows the same order"""
    return key(task), ics.as_text(task.time("CREATED")) or "", task.get("UID")


def ordered(tasks):
    return sorted(tasks, key=sort_key)


def place(others, at):
    """{task: new value} that puts a task at index `at` among `others` (the list without it, in order): one entry when
    there is room between the neighbours, the whole list renumbered when there isn't"""
    before = others[at - 1] if at > 0 else None
    after = others[at] if at < len(others) else None
    if before is None and after is None:
        return {None: 0}
    if before is None:
        return {None: key(after) - STEP}
    if after is None:
        return {None: key(before) + STEP}
    lo, hi = key(before), key(after)
    if hi - lo >= 2:
        return {None: (lo + hi) // 2}
    # No room: every task STEP apart from the first's value, the moved one (None) at `at`
    rows = others[:at] + [None] + others[at:]
    base = key(others[0])
    out = {}
    for i, t in enumerate(rows):
        v = base + i * STEP
        if t is None or key(t) != v:
            out[t] = v
    return out


def target(rows, moving, up=False, down=False, top=False, bottom=False, before=None, after=None):
    """The index among the others (rows without the moved task) it goes to, or None when it would stay where it is.
    before/after: another task of the list, by UID"""
    uids = [t.get("UID") for t in rows]
    i = uids.index(moving)
    others = [u for u in uids if u != moving]
    if up:
        at = i - 1
    elif down:
        at = i + 1
    elif top:
        at = 0
    elif bottom:
        at = len(others)
    else:
        near = before or after
        if near not in others:
            raise ValueError(f"No other open task with the id {near!r} in this list.")
        at = others.index(near) + (1 if after else 0)
    if at < 0 or at > len(others) or at == i:
        return None
    return at


def write(task, value):
    task.put(ics.Line(FIELD, {}, str(value)))
