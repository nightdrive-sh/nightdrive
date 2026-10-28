#!/usr/bin/env python3
"""Due tasks' notifications: nightdrive-tasks-due.timer runs `tasks due` every minute, and each task whose time has
come gets a notification with Done and Later, once for each due time it has (Later moves it on, so it comes again).

    due.py check        notify what has come due since the last check (the timer's)
    due.py notice ID    one task's notification, waiting for its buttons (a process of its own)

A task due on a day without a time comes at when.MORNING. Many at once (a computer that was off) come as one
notification that opens the window, not a wall of them. Each notification waits in a process of its own, started by
systemd-run: the timer's service ends at once, and would take a child of its own with it.
"""

import json
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import cli
import ics
import store
import when

SEEN = store.STATE / "notified.json"   # {uid: the due time it was notified for}
ONE_BY_ONE = 3                         # more due at once come as one notification
ICON = "lucide:list-checks"
TASKS = Path(__file__).resolve().parents[1] / "bin/tasks"


def read_seen():
    try:
        return json.loads(SEEN.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def check():
    now = datetime.now()
    seen = read_seen()
    due, alive = [], {}
    for _, _, task in store.load():
        uid, at = task.get("UID"), task.time("DUE")
        if not uid or at is None or cli.is_done(task):
            continue
        key = ics.as_text(at)
        if when.due_at(at) <= now and seen.get(uid) != key:
            due.append(task)
        if when.due_at(at) <= now:
            alive[uid] = key
    # Only the tasks still due are remembered: one done or moved on is notified again if it comes due again
    store.write(SEEN, json.dumps(alive))
    if len(due) > ONE_BY_ONE:
        titles = [t.get("SUMMARY") for t in due]
        body = "\n".join(titles[:5]) + (f"\n…and {len(titles) - 5} more" if len(titles) > 5 else "")
        spawn(["many", f"{len(due)} tasks are due", body])
    else:
        for task in due:
            spawn(["notice", task.get("UID")])


def spawn(args):
    cmd = [sys.executable, str(Path(__file__).resolve())] + args
    if shutil.which("systemd-run"):
        cmd = ["systemd-run", "--user", "--collect", "--quiet", "--"] + cmd
    subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def notify(tag, summary, body, actions):
    """The action pressed, or None once the row has gone (dismissed, replaced, expired)"""
    cmd = ["notify-send", "-a", "Tasks", "-i", ICON, "-h", f"string:x-dunst-stack-tag:tasks-{tag}", "-w"]
    for key, name in actions:
        cmd += ["-A", f"{key}={name}"]
    try:
        out = subprocess.run(cmd + [summary, body], stdin=subprocess.DEVNULL, capture_output=True, text=True).stdout
    except OSError:
        return None
    return out.strip() or None


def notice(uid):
    try:
        _, _, task = store.find(uid)
    except store.NotFound:
        return
    due = task.time("DUE")
    note = task.get("DESCRIPTION").split("\n")[0]
    body = "\n".join(x for x in [when.label(due), note] if x)
    pressed = notify(uid, task.get("SUMMARY") or "A task is due", body,
                     [("default", "Open"), ("done", "Done"), ("later", "Later")])
    # Through the command, so the open window shows the change too
    if pressed == "done":
        subprocess.run([str(TASKS), "done", uid], stdout=subprocess.DEVNULL)
    elif pressed == "later":
        subprocess.run([str(TASKS), "snooze", uid], stdout=subprocess.DEVNULL)
    elif pressed == "default":
        subprocess.run([str(TASKS), "open"])


def many(summary, body):
    if notify("many", summary, body, [("default", "Open")]) == "default":
        subprocess.run([str(TASKS), "open"])


if __name__ == "__main__":
    cmd, rest = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "check" and not rest:
        check()
    elif cmd == "notice" and len(rest) == 1:
        notice(rest[0])
    elif cmd == "many" and len(rest) == 2:
        many(*rest)
    else:
        sys.exit("usage: due.py check | notice ID | many SUMMARY BODY")
