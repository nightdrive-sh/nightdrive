#!/usr/bin/env python3
"""The tasks on disk: a vdir (a folder per list, an .ics file per task, the list's name in its `displayname` file), the
layout vdirsyncer keeps a CalDAV calendar in, so a sync can be pointed at it later as it is.

Every change keeps what it changed first (snapshot()) and what it left (settle()), and restore() puts the first back,
only while the files are still as the change left them: the undo of Claude's changes (mcp.json) and of the command's. A task moved to the trash goes to the state folder, out of the vdir, where a sync
wouldn't see it as a task any more.
"""

import json
import os
import re
import shutil
import time
from pathlib import Path

from ics import Task

DATA = Path(os.environ.get("NIGHTDRIVE_TASKS_DIR")
            or Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "nightdrive/tasks")
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "nightdrive/tasks"
UNDO = STATE / "undo"
TRASH = STATE / "trash"
DEFAULT = "Tasks"       # the list a task goes in when none is named, made on the first add
KEEP_UNDO = 200         # snapshots kept, the newest
KEEP_TRASH = 30 * 86400  # seconds a trashed task stays in the state folder


class NotFound(Exception):
    pass


def slug(name):
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return s or "list"


def write(path, text):
    """Atomically, with a hidden temporary name a sync skips"""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def lists():
    """[{id, name, path}] by name: every folder of DATA that isn't hidden"""
    if not DATA.is_dir():
        return []
    out = []
    for d in DATA.iterdir():
        if d.is_dir() and not d.name.startswith("."):
            named = d / "displayname"
            name = named.read_text(encoding="utf-8").strip() if named.is_file() else ""
            out.append({"id": d.name, "name": name or d.name, "path": d})
    return sorted(out, key=lambda l: l["name"].lower())


def find_list(name, make=False):
    """A list by its name or id (any case); make: a new one with that name when there is none"""
    want = (name or DEFAULT).strip()
    for l in lists():
        if want.lower() in (l["name"].lower(), l["id"].lower()):
            return l
    if not make:
        raise NotFound(f"No list called {want!r}. The lists: " + (", ".join(l["name"] for l in lists()) or "none yet"))
    d = DATA / slug(want)
    while d.exists():
        d = d.with_name(d.name + "-1")
    write(d / "displayname", want + "\n")
    return {"id": d.name, "name": want, "path": d, "made": True}


def load(lst=None):
    """[(list, path, Task)] of every list, or of one; a file that isn't a VTODO (an event, a broken file) is skipped"""
    out = []
    for l in ([lst] if lst else lists()):
        for f in sorted(l["path"].glob("*.ics")):
            try:
                out.append((l, f, Task(f.read_text(encoding="utf-8", errors="replace"))))
            except (OSError, ValueError):
                continue
    return out


def find(uid):
    """A task by its UID, or by the start of one when only one task's starts so"""
    every = load()
    exact = [t for t in every if t[2].get("UID") == uid]
    if exact:
        return exact[0]
    near = [t for t in every if uid and t[2].get("UID").startswith(uid)]
    if len(near) == 1:
        return near[0]
    raise NotFound(f"No task with the id {uid!r}" + (" (more than one start so)" if near else "") + ": tasks list gives the ids.")


def path_for(lst, task):
    name = re.sub(r"[^A-Za-z0-9@._-]", "_", task.get("UID")) or "task"
    return lst["path"] / f"{name}.ics"


def snapshot(paths, made=None):
    """Keeps the files as they are now (None for one not there yet) and returns the id restore() takes. made: a list
    the change made, which its undo takes away again"""
    UNDO.mkdir(parents=True, exist_ok=True)
    sid = f"{time.time_ns():x}"
    files = [{"path": str(p.relative_to(DATA)),
              "before": p.read_text(encoding="utf-8") if p.is_file() else None} for p in paths]
    if made:
        files.append({"path": str((made["path"] / "displayname").relative_to(DATA)), "before": None})
    write(UNDO / f"{sid}.json", json.dumps({"files": files}, ensure_ascii=False))
    for old in sorted(UNDO.glob("*.json"))[:-KEEP_UNDO]:
        old.unlink(missing_ok=True)
    return sid


def settle(sid):
    """After the change: the files as it left them (None for one it removed), so restore() can tell an edit made since"""
    snap = UNDO / f"{sid}.json"
    data = json.loads(snap.read_text(encoding="utf-8"))
    for f in data["files"]:
        if Path(f["path"]).name != "displayname":
            p = inside(f["path"])
            f["after"] = p.read_text(encoding="utf-8") if p.is_file() else None
    write(snap, json.dumps(data, ensure_ascii=False))


def inside(rel, root=None):
    """A snapshot's path as the file it names, checked: list/file, links resolved, still in the tasks' folder (or the
    trash). The snapshot is a JSON file in the state folder, and anything that can write there (the user's own
    programs, an editor rule) could otherwise make an Undo write, unlink or rmtree any path the user can (#1925)."""
    root = (root or DATA).resolve()
    parts = Path(rel).parts if isinstance(rel, str) else ()
    if len(parts) != 2 or Path(rel).is_absolute() or any(x in (".", "..") for x in parts):
        raise NotFound(f"This undo names {rel!r}, not a file of the tasks: nothing was changed.")
    p = (root / rel).resolve()
    # Two levels below the root after resolving too: a list folder that is a link to the root itself would make the
    # rmtree of a list the rmtree of every list
    if not p.is_relative_to(root) or len(p.relative_to(root).parts) != 2:
        raise NotFound(f"This undo names {rel!r}, which leads out of the tasks' folder: nothing was changed.")
    return p


def restore(sid):
    """Puts the files of a snapshot back as they were: a task added goes away, one done or moved is as before, one
    trashed comes back. Returns the paths. Refuses, changing nothing, when a file isn't as the change left it: an undo
    an hour later mustn't write over what the user did since (#1860)."""
    if not re.fullmatch(r"[0-9a-f]+", sid or "") or not (UNDO / f"{sid}.json").is_file():
        raise NotFound(f"Nothing to undo with {sid!r}: it is done already, or too old.")
    files = json.loads((UNDO / f"{sid}.json").read_text(encoding="utf-8"))["files"]
    # Every path checked before any is read or touched: one bad path leaves the whole snapshot undone
    paths = [(f, inside(f["path"]), inside(f["path"], TRASH)) for f in files]
    for f, p, _ in paths:
        if "after" in f and (p.read_text(encoding="utf-8") if p.is_file() else None) != f["after"]:
            raise NotFound("The task has changed since, so the undo would lose that: nothing was changed. "
                           "Change it back by hand if need be.")
    out = []
    for f, p, trashed in paths:
        if f["before"] is None and p.name == "displayname":
            # The list the change made, unless a task has gone in it since
            if p.parent.is_dir() and not any(p.parent.glob("*.ics")):
                shutil.rmtree(p.parent)
        elif f["before"] is None:
            p.unlink(missing_ok=True)
        else:
            write(p, f["before"])
            trashed.unlink(missing_ok=True)
        out.append(p)
    (UNDO / f"{sid}.json").unlink()
    return out


def save(path, task):
    task.touch()
    write(path, str(task))


def trash(path):
    """Out of the vdir, into the state folder for KEEP_TRASH; older ones go now"""
    dest = TRASH / path.relative_to(DATA)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(path), dest)
    os.utime(dest)   # the trash's age counts from now
    cutoff = time.time() - KEEP_TRASH
    for old in TRASH.glob("*/*.ics"):
        if old.stat().st_mtime < cutoff:
            old.unlink(missing_ok=True)
