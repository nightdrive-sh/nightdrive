"""A message's button pressed (#3178): `nightdrive inbox press ID N`, which the window runs on a click, so what a button
does is decided here once and not again in QML. N is the button's place among the message's actions (0 the first), or
`session` / `task` for its sender's own session and task, which the window offers without a button.

    open      the file or folder in its default app (xdg-open)
    url       the address in the browser (xdg-open)
    run       the argv in its folder, in the background, its output in a log; only with --yes, which the window passes
              after the user has seen the whole command and its folder on its card and confirmed it
    session   the session's terminal brought forward, or the session resumed in one (`nightdrive sessions resume`)
    task      the Dashboard task, at the address in ~/.config/nightdrive/inbox.json's task_url ("…/tasks/{n}");
              without one, "#N" is copied, to paste where tasks are kept

Each starts its program apart from this one (a session of its own), so the window doesn't wait for it, nor does
closing the window end it.
"""
import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

from store import InboxError

REPO = Path(__file__).resolve().parent.parent.parent
HISTORY = REPO / "config/topbar/scripts/claude-history"


def settings():
    conf = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "nightdrive" / "inbox.json"
    try:
        data = json.loads(conf.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def log_dir():
    state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    return state / "nightdrive" / "inbox-runs"


def spawn(argv, cwd=None, log=None):
    """Started on its own, not waited for. False when there is no such program."""
    if not shutil.which(argv[0]) and not os.path.isfile(argv[0]):
        return False
    out = open(log, "ab") if log else subprocess.DEVNULL
    try:
        subprocess.Popen(argv, cwd=cwd, stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT if log else out,
                         start_new_session=True)
    finally:
        if log:
            out.close()
    return True


def target(msg, which):
    """The action button N stands for, or the sender's own session or task as one."""
    sender = msg.get("from") or {}
    if which == "session":
        if sender.get("kind") != "claude" or not sender.get("session"):
            raise InboxError("this message isn't from a Claude session")
        return {"kind": "session", "label": "Session", "session": sender["session"]}
    if which == "task":
        if not msg.get("task"):
            raise InboxError("this message names no task")
        return {"kind": "task", "label": f"#{msg['task']}", "task": msg["task"]}
    actions = msg.get("actions") or []
    if not str(which).isdigit() or int(which) >= len(actions):
        raise InboxError(f"no button {which}: the message has {len(actions)}")
    return actions[int(which)]


def press(msg, which, yes=False):
    """Does what the button says; returns what happened, for --json."""
    action = target(msg, which)
    kind = action["kind"]
    out = {"id": msg["id"], "kind": kind, "label": action["label"]}
    if kind in ("open", "url"):
        what = action["path"] if kind == "open" else action["url"]
        if kind == "open" and not os.path.exists(what):
            raise InboxError(f"{what} isn't there any more")
        if not spawn(["xdg-open", what]):
            raise InboxError("xdg-open isn't installed")
        return {**out, "opened": what}
    if kind == "run":
        if not yes:
            raise InboxError("a run button runs only with --yes, once its command and folder have been seen")
        if not os.path.isdir(action["dir"]):
            raise InboxError(f"the folder {action['dir']} isn't there any more")
        logs = log_dir()
        logs.mkdir(parents=True, exist_ok=True)
        log = logs / f"{msg['id']}-{datetime.now().strftime('%H%M%S')}.log"
        if not spawn(action["argv"], cwd=action["dir"], log=log):
            raise InboxError(f"{action['argv'][0]}: no such command")
        return {**out, "ran": action["argv"], "dir": action["dir"], "log": str(log)}
    if kind == "session":
        if not spawn([str(HISTORY), "resume", action["session"]]):
            raise InboxError("the sessions' command is missing")
        return {**out, "session": action["session"]}
    url = str(settings().get("task_url") or "")
    if "{n}" in url:
        spawn(["xdg-open", url.replace("{n}", str(action["task"]))])
        return {**out, "opened": url.replace("{n}", str(action["task"]))}
    text = f"#{action['task']}"
    if not spawn(["wl-copy", text]):
        raise InboxError("no task_url in ~/.config/nightdrive/inbox.json, and wl-copy isn't there to copy the number")
    return {**out, "copied": text}
