"""A message's buttons (#3132). The sender picks how many and what each says ("Start the game", "Before and after");
the kinds are fixed, so the window knows how to show each one safely:

    {"kind": "open",    "label": …, "path": "/abs/file/or/folder"}   opens it in its default app
    {"kind": "url",     "label": …, "url": "https://…"}              opens it in the browser
    {"kind": "run",     "label": …, "argv": ["godot", "--path", …], "dir": "/abs/dir"}
    {"kind": "session", "label": …, "session": "<Claude Code session id>"}   goes to it, or goes on with it
    {"kind": "task",    "label": …, "task": 3132}                    opens the Dashboard task

A run button is running code: it is kept as an argv (never a shell line) with the folder it runs in, and the window
shows the whole command under the button and runs it only after the user confirms it on a card that shows it again.
Nothing here or in the window ever runs one by itself. The sender's own session and task need no button: the window
offers them from the message's `from` and `task`.
"""
import os
import re
import shlex
from pathlib import Path

from store import InboxError

KINDS = ("open", "url", "run", "session", "task")
ACTIONS_MAX = 8
LABEL_MAX = 60
COMMAND_MAX = 4000       # characters of a run button's argv, all of it
SESSION = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
URL = re.compile(r"^https?://[^\s]+$")


def _label(raw, kind):
    label = " ".join(str(raw or "").split())
    if not label:
        raise InboxError(f"a {kind} button needs a label")
    if len(label) > LABEL_MAX:
        raise InboxError(f"a button's label is at most {LABEL_MAX} characters: {label[:LABEL_MAX]}…")
    return label


def _abs(raw, base):
    p = Path(os.path.expanduser(str(raw)))
    return str(p if p.is_absolute() else Path(base) / p)


def task_number(raw):
    """3132 from 3132, "3132" or "#3132"; None for anything else."""
    text = "" if isinstance(raw, bool) or raw is None else str(raw).strip().lstrip("#")
    return int(text) if text.isdigit() and int(text) > 0 else None


def check(action, base_dir):
    """One action as stored, from a dict as a sender gives it (run may give `command`, a line split as a shell would,
    instead of argv); relative paths are taken from base_dir, the sender's folder."""
    if not isinstance(action, dict):
        raise InboxError("each action must be an object")
    kind = action.get("kind")
    if kind not in KINDS:
        raise InboxError(f"unknown action kind {kind!r}: {', '.join(KINDS)}")
    out = {"kind": kind, "label": _label(action.get("label"), kind)}
    if kind == "open":
        path = _abs(action.get("path") or "", base_dir)
        if not action.get("path") or not os.path.exists(path):
            raise InboxError(f"{out['label']}: {action.get('path') or 'a path'} doesn't exist")
        out["path"] = path
    elif kind == "url":
        url = str(action.get("url") or "")
        if not URL.match(url):
            raise InboxError(f"{out['label']}: a url button takes an http(s) address")
        out["url"] = url
    elif kind == "run":
        argv = action.get("argv")
        if argv is None:
            try:
                argv = shlex.split(str(action.get("command") or ""))
            except ValueError as e:
                raise InboxError(f"{out['label']}: the command can't be read ({e})")
        if not isinstance(argv, list) or not argv or not all(isinstance(a, str) and a for a in argv):
            raise InboxError(f"{out['label']}: a run button needs a command")
        if sum(len(a) + 1 for a in argv) > COMMAND_MAX:
            raise InboxError(f"{out['label']}: the command is longer than {COMMAND_MAX} characters")
        out["argv"] = argv
        out["dir"] = _abs(action.get("dir") or base_dir, base_dir)
        if not os.path.isdir(out["dir"]):
            raise InboxError(f"{out['label']}: the folder {out['dir']} doesn't exist")
    elif kind == "session":
        sid = str(action.get("session") or "")
        if not SESSION.match(sid):
            raise InboxError(f"{out['label']}: a session button takes a Claude Code session id")
        out["session"] = sid
    else:
        out["task"] = task_number(action.get("task"))
        if not out["task"]:
            raise InboxError(f"{out['label']}: a task button takes a Dashboard task number")
    return out


def check_all(actions, base_dir, already=0):
    if not isinstance(actions, list):
        raise InboxError("actions must be a list")
    if already + len(actions) > ACTIONS_MAX:
        raise InboxError(f"at most {ACTIONS_MAX} buttons per message")
    return [check(a, base_dir) for a in actions]


def from_cli(triples):
    """--action KIND LABEL VALUE, as dicts for check(): VALUE is the path, url, command line, session or task."""
    field = {"open": "path", "url": "url", "run": "command", "session": "session", "task": "task"}
    out = []
    for kind, label, value in triples:
        if kind not in field:
            raise InboxError(f"unknown action kind {kind!r}: {', '.join(KINDS)}")
        out.append({"kind": kind, "label": label, field[kind]: value})
    return out


def describe(action):
    """One line for a terminal: what the button does, the whole command for run."""
    kind = action["kind"]
    what = {"open": lambda a: a["path"], "url": lambda a: a["url"],
            "run": lambda a: f"{shlex.join(a['argv'])}   (in {a['dir']})",
            "session": lambda a: f"session {a['session']}", "task": lambda a: f"task #{a['task']}"}[kind](action)
    return f"[{action['label']}] {kind}: {what}"
