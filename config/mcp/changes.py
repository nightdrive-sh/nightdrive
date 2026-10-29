"""The log of Claude's changes for undo.py: ~/.local/state/nightdrive/claude-changes.jsonl, a JSON object a line,
oldest first. Each change tool's call is an entry with what undoes it (and what does it again), so the notification's
Undo and Claude's undo_change both work from here, also after the server that made the change has gone.

An entry: {id, time, tool, notice, arguments, before, do, stdin, undo, dir, timeout, state, at}
    id         1, 2, 3…: what Claude names in undo_change
    before     the state the tool's `before` command reported (what undo puts back), {} without one
    do, stdin  the command as it ran, for redo; undo the argv that undoes it; both run in dir
    remake     the tool's `undo` template as it was (undo.py now rebuilds a redo's undo by the tool's own)
    state      "done" or "undone", since `at`
    deletes    the tool removes something (files_trash): kept while its Undo is on screen (kept)
    server     the MCP server that made it (undo.server_id): undo_change without an id undoes only its own
"""

import fcntl
import json
import os
import time
from datetime import datetime
from contextlib import contextmanager
from pathlib import Path

FILE = Path.home() / ".local/state/nightdrive/claude-changes.jsonl"
# Older entries leave the log: by then what they changed has likely been changed again, and undoing it would surprise
KEEP = 100
HOLD = 3600       # seconds a change's notification offers Undo (undo.NOTICE_FOR)
HOLD_MAX = 400    # older deletions kept for it at most: a flood of them can't grow the log without end


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def age(entry):
    """Seconds since the entry was made; None when its time can't be read."""
    try:
        return time.time() - datetime.strptime(entry["time"], "%Y-%m-%dT%H:%M:%S%z").timestamp()
    except (KeyError, TypeError, ValueError):
        return None


def kept(entries):
    """What the log keeps: the last KEEP entries, and before them a deletion still in place whose notification still
    offers Undo (#1881). Else a run of cheap changes (a hundred notes) pushes a trashed file's way back out of the log
    while its button is on screen, and pressing it finds nothing."""
    older, recent = entries[:-KEEP], entries[-KEEP:]
    held = [e for e in older if e.get("deletes") is True and e.get("state") == "done"
            and (a := age(e)) is not None and a < HOLD]
    return held[-HOLD_MAX:] + recent


@contextmanager
def flock(name):
    """An exclusive lock beside the log, held for the with block."""
    FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(FILE.parent / f".{name}.lock", "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def read():
    """The entries, oldest first; a line that isn't an entry (a write cut short) is skipped."""
    try:
        lines = FILE.read_text().splitlines()
    except OSError:
        return []
    out = []
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict) and isinstance(entry.get("id"), int):
            out.append(entry)
    return out


def write(entries):
    """The whole log at once (a file beside it, renamed over it), so a reader never sees half of it. Readable by the
    user alone (600): it holds the tools' arguments, a draft's text say (#1837); a log from before gets it here too."""
    tmp = FILE.with_name(FILE.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)   # a .tmp left behind by a crash keeps its old mode through O_CREAT
    with os.fdopen(fd, "w") as f:
        f.write("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in kept(entries)))
    os.replace(tmp, FILE)


def private():
    """The log readable by the user alone, also one from before write() made it so: it stayed 644 until the next change
    (#1865). `nightdrive mcp install` and `status` (the Access window reads it) call it."""
    try:
        if FILE.stat().st_mode & 0o077:
            FILE.chmod(0o600)
    except OSError:
        pass


@contextmanager
def editing():
    """The entries under the log's lock, written back when the block ends: a short lock, never held while a command
    runs (an undo can take minutes, and the server's next change mustn't wait for it)."""
    with flock("claude-changes"):
        entries = read()
        yield entries
        write(entries)


def add(entry):
    """Appends an entry with the next id and the time; returns it."""
    with editing() as entries:
        entry = {"id": max((e["id"] for e in entries), default=0) + 1, "time": now(), **entry, "state": "done"}
        entry["at"] = entry["time"]
        entries.append(entry)
    return entry


def get(entry_id):
    return next((e for e in read() if e["id"] == entry_id), None)


def mark(entry_id, state, **fields):
    """Sets an entry's state (done or undone) and when it got it, and any other fields given (a redo's new undo)."""
    with editing() as entries:
        for e in entries:
            if e["id"] == entry_id:
                e.update(fields)
                e["state"], e["at"] = state, now()


def serial():
    """Held while an undo or redo runs, so the notification's button and Claude can't run the same one twice."""
    return flock("claude-undo")
