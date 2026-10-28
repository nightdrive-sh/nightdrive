"""The log of Claude's changes for undo.py: ~/.local/state/nightdrive/claude-changes.jsonl, a JSON object a line,
oldest first. Each change tool's call is an entry with what undoes it (and what does it again), so the notification's
Undo and Claude's undo_change both work from here, also after the server that made the change has gone.

An entry: {id, time, tool, notice, arguments, before, do, stdin, undo, dir, timeout, state, at}
    id         1, 2, 3…: what Claude names in undo_change
    before     the state the tool's `before` command reported (what undo puts back), {} without one
    do, stdin  the command as it ran, for redo; undo the argv that undoes it; both run in dir
    state      "done" or "undone", since `at`
"""

import fcntl
import json
import os
import time
from contextlib import contextmanager
from pathlib import Path

FILE = Path.home() / ".local/state/nightdrive/claude-changes.jsonl"
# Older entries leave the log: by then what they changed has likely been changed again, and undoing it would surprise
KEEP = 100


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


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
    """The whole log at once (a file beside it, renamed over it), so a reader never sees half of it."""
    tmp = FILE.with_name(FILE.name + ".tmp")
    tmp.write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in entries[-KEEP:]))
    os.replace(tmp, FILE)


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


def mark(entry_id, state):
    """Sets an entry's state (done or undone) and when it got it."""
    with editing() as entries:
        for e in entries:
            if e["id"] == entry_id:
                e["state"], e["at"] = state, now()


def serial():
    """Held while an undo or redo runs, so the notification's button and Claude can't run the same one twice."""
    return flock("claude-undo")
