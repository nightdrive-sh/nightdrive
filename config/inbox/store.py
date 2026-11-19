"""Nightdrive Inbox's messages on disk (#3132): one folder per message, so any session of any project, on either Claude
account, and any app can leave one without a server running.

    ~/.local/share/nightdrive/inbox/<id>/message.json      the message (below)
    ~/.local/share/nightdrive/inbox/<id>/<attachment>      its files, copied in, so they outlive /tmp and the project
    ~/.local/share/nightdrive/inbox/<id>/history/<n>.json  the message before update n, for its undo (revert)
    ~/.local/share/nightdrive/inbox/archive/<id>/          an archived one, as it was

message.json: {v, id, title, body, at, updated, read, from, task, attachments: [{name, type, size}], actions: [...]}
(actions.py says what an action is, sender.py what from is). at and updated are ISO 8601 with the offset; read is the
time it was read, or null. Every write goes through a temporary file and a rename under one lock, so the window, the
command and Claude's tools can work on the same message at once without one write eating another's.
"""
import contextlib
import copy
import fcntl
import json
import os
import re
import secrets
import shutil
import tempfile
import time
from datetime import datetime
from pathlib import Path

VERSION = 1
ARCHIVE = "archive"
HISTORY = "history"
MESSAGE = "message.json"
ID = re.compile(r"^\d{8}-\d{6}-[0-9a-f]{4}$")   # 20261119-095210-a3f1: sorts by time, unique enough per second


class InboxError(Exception):
    """A request the inbox can't do, with the reason for a reader (the CLI prints it, Claude reads it)."""


def root():
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local/share")
    return Path(data) / "nightdrive" / "inbox"


def now_iso():
    return datetime.now().astimezone().isoformat(timespec="seconds")


@contextlib.contextmanager
def locked():
    """One writer at a time, across processes: a message is read, changed and written whole."""
    base = root()
    base.mkdir(parents=True, exist_ok=True)
    with open(base / ".lock", "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield base


def write_json(path, data):
    """Atomically: a reader sees the old file or the new one, never half of one."""
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, path)


def new_id(base):
    while True:
        mid = time.strftime("%Y%m%d-%H%M%S-") + secrets.token_hex(2)
        if not (base / mid).exists() and not (base / ARCHIVE / mid).exists():
            return mid


def folder(mid, archived=None):
    """The message's folder: where it is now (archived=None), or in the inbox or the archive. None when it isn't."""
    base = root()
    places = {False: [base / mid], True: [base / ARCHIVE / mid], None: [base / mid, base / ARCHIVE / mid]}[archived]
    return next((p for p in places if (p / MESSAGE).is_file()), None)


def load(path):
    try:
        msg = json.loads((path / MESSAGE).read_text())
    except (OSError, ValueError) as e:
        raise InboxError(f"message {path.name} can't be read: {e}")
    msg["archived"] = path.parent.name == ARCHIVE
    return msg


def save(path, msg):
    write_json(path / MESSAGE, {k: v for k, v in msg.items() if k != "archived"})


def resolve(ref):
    """A message's id from what was typed: the whole id, or a unique part of its start or end (a3f1)."""
    if ID.match(ref) and folder(ref):
        return ref
    ids = [p.name for p in every_folder()]
    hits = [i for i in ids if ref and (i.startswith(ref) or i.endswith(ref))]
    if len(hits) == 1:
        return hits[0]
    raise InboxError(f"no message {ref}" if not hits else f"{ref} matches {len(hits)} messages: give more of the id")


def every_folder(archived=None):
    base = root()
    places = {False: [base], True: [base / ARCHIVE], None: [base, base / ARCHIVE]}[archived]
    return [p for place in places if place.is_dir()
            for p in place.iterdir() if ID.match(p.name) and (p / MESSAGE).is_file()]


def messages(archived=False):
    """The messages, the most recently changed first (an update brings one back to the top, as it is new again)."""
    found = []
    for p in every_folder(archived):
        try:
            found.append(load(p))
        except InboxError:
            continue   # one broken file shouldn't hide the rest
    return sorted(found, key=lambda m: (m.get("updated") or m.get("at") or "", m["id"]), reverse=True)


def create(title, body, sender, task, actions, attach):
    """A new message; attach(dest_folder) copies its files in and returns their entries."""
    with locked() as base:
        mid = new_id(base)
        tmp = Path(tempfile.mkdtemp(dir=base, prefix=".new-"))
        try:
            stamp = now_iso()
            msg = {"v": VERSION, "id": mid, "title": title, "body": body, "at": stamp, "updated": stamp,
                   "read": None, "from": sender, "task": task, "attachments": attach(tmp, []), "actions": actions}
            save(tmp, msg)
            os.rename(tmp, base / mid)   # appears whole: a listing never sees one without its files
        except BaseException:
            shutil.rmtree(tmp, ignore_errors=True)
            raise
    return load(base / mid)


def update(mid, change):
    """change(msg, folder) edits the message in place; the version before is kept for revert. Returns (msg, rev)."""
    with locked():
        path = folder(mid)
        if path is None:
            raise InboxError(f"no message {mid}")
        msg = load(path)
        history = path / HISTORY
        history.mkdir(exist_ok=True)
        rev = 1 + max((int(p.stem) for p in history.glob("*.json") if p.stem.isdigit()), default=0)
        before = copy.deepcopy(msg)
        change(msg, path)
        write_json(history / f"{rev}.json", {k: v for k, v in before.items() if k != "archived"})
        msg["updated"], msg["read"] = now_iso(), None   # news again: unread, at the top
        save(path, msg)
    return msg, rev


def revert(mid, rev):
    """Back to the message as it was before update rev: that update's undo. Its new files go, later ones too."""
    with locked():
        path = folder(mid)
        if path is None:
            raise InboxError(f"no message {mid}")
        old = path / HISTORY / f"{rev}.json"
        if not old.is_file():
            raise InboxError(f"message {mid} has no update {rev} to undo")
        msg = json.loads(old.read_text())
        keep = {a["name"] for a in msg.get("attachments", [])} | {MESSAGE, HISTORY}
        for p in path.iterdir():
            if p.name not in keep and not p.name.startswith("."):
                p.unlink()
        for p in (path / HISTORY).glob("*.json"):
            if p.stem.isdigit() and int(p.stem) >= rev:
                p.unlink()
        save(path, msg)
    return load(path)


def set_read(mid, read=True):
    with locked():
        path = folder(mid)
        if path is None:
            raise InboxError(f"no message {mid}")
        msg = load(path)
        msg["read"] = (msg.get("read") or now_iso()) if read else None
        save(path, msg)
    return load(path)


def set_archived(mid, archived=True):
    with locked() as base:
        path = folder(mid)
        if path is None:
            raise InboxError(f"no message {mid}")
        dest = (base / ARCHIVE / mid) if archived else (base / mid)
        if path != dest:
            dest.parent.mkdir(parents=True, exist_ok=True)
            os.rename(path, dest)
    return load(dest)


def delete(mid):
    """Gone for good: inbox_post's undo, a message just left. The user's way out is archive."""
    with locked():
        path = folder(mid)
        if path is None:
            raise InboxError(f"no message {mid}")
        msg = load(path)
        shutil.rmtree(path)
    return msg
