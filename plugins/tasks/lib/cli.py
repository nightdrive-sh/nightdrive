#!/usr/bin/env python3
"""The `tasks` command's work (bin/tasks runs it): reading the tasks, and the changes Claude makes too (mcp.json).

    cli.py lists [--json]
    cli.py list [--json] [--list NAME] [--view open|today|upcoming|done|all] [--query TEXT]
    cli.py add [--json] [--list NAME] [--due WHEN] [--note TEXT] [--priority high|normal|low] TITLE
    cli.py add --json --stdin       the same as JSON on stdin: {title, list, day, time, note, priority} (the window)
    cli.py when [--json] [--day DAY] [--time TIME] [WHEN]     how a due reads: {due, label}
    cli.py edit [--json] [--title T] [--due WHEN | --no-due] [--note T] [--list NAME] [--priority P] ID
    cli.py edit --json --stdin      the same as JSON: {id, and what changes of title, day, time, list, note, priority}
    cli.py done [--json] ID         cli.py undone [--json] ID       cli.py snooze [--json] [--until WHEN] ID
    cli.py trash [--json] ID        cli.py restore [--json] UNDO
    cli.py list-new [--json] NAME   cli.py list-rename [--json] LIST NAME
    cli.py list-remove [--json] [--with-tasks] LIST       (lists.py)

Each change prints, with --json, the task as `list` gives it and `undo`: the id `restore` takes to put back what the
change changed (Claude's undo, config/mcp/undo.py). Errors go to stderr, written for a reader, with exit status 1.
"""

import argparse
import json
import sys
from datetime import datetime

import ics
import lists
import store
import when

VIEWS = ("open", "today", "upcoming", "scheduled", "done", "all")   # scheduled: upcoming's name until #2023
DONE_MAX = 50   # the done view's newest: a list someone keeps for years would be long
PRIORITY = {"high": "1", "normal": "", "low": "9"}


def priority(task):
    p = task.get("PRIORITY", "0")
    n = int(p) if p.isdigit() else 0
    return "high" if 1 <= n <= 4 else "low" if n >= 6 else ""


is_done = store.is_done


def overdue(due, now):
    """Past its time, or a day before today: a task due today without a time isn't late until tomorrow"""
    if due is None:
        return False
    return due < now.date() if ics.is_date(due) else due < now


def row(lst, task, now):
    due = task.time("DUE")
    done = is_done(task)
    return {"id": task.get("UID"), "title": task.get("SUMMARY") or "(no title)", "note": task.get("DESCRIPTION"),
            "list": lst["name"], "list_id": lst["id"], "due": ics.as_text(due), "due_label": when.label(due, now),
            "overdue": overdue(due, now) and not done,
            "priority": priority(task), "done": done, "completed": ics.as_text(task.time("COMPLETED")),
            "created": ics.as_text(task.time("CREATED"))}


def order(r):
    rank = {"high": 0, "": 1, "low": 2}[r["priority"]]
    return (r["due"] is None, (r["due"] or "") + ("" if "T" in (r["due"] or "") else "T00:00"), rank, r["created"] or "")


def view(rows, name, now):
    today = now.date().isoformat()
    if name == "done":
        return sorted([r for r in rows if r["done"]], key=lambda r: r["completed"] or "", reverse=True)[:DONE_MAX]
    if name != "all":
        rows = [r for r in rows if not r["done"]]
    if name == "today":
        rows = [r for r in rows if r["due"] and r["due"][:10] <= today]
    elif name in ("upcoming", "scheduled"):
        rows = [r for r in rows if r["due"]]
    return sorted(rows, key=order)


def lists_json():
    every = store.load()
    return [{"id": l["id"], "name": l["name"],
             "open": sum(1 for x, _, t in every if x["id"] == l["id"] and not is_done(t))} for l in store.lists()]


def cmd_lists(a):
    out = lists_json()
    if a.json:
        return out
    return "\n".join(f"{l['name']:<24} {l['open']} open" for l in out) or "No lists yet: tasks add makes the first."


def cmd_list(a):
    now = datetime.now().replace(second=0, microsecond=0)
    lst = store.find_list(a.list) if a.list else None
    rows = [row(l, t, now) for l, _, t in store.load(lst)]
    words = (a.query or "").lower().split()
    rows = [r for r in rows if all(w in (r["title"] + "\n" + r["note"]).lower() for w in words)]
    rows = view(rows, a.view, now)
    if a.json:
        return {"now": now.strftime("%Y-%m-%dT%H:%M"), "view": a.view, "list": lst["name"] if lst else None,
                "lists": lists_json(), "count": len(rows), "tasks": rows}
    return "\n".join(text_row(r) for r in rows) or "No tasks."


def text_row(r):
    mark = "[x]" if r["done"] else "[ ]"
    due = f"  ({r['due_label']})" if r["due"] else ""
    return f"{mark} {r['title']}{due}  · {r['list']}  {r['id'][:8]}"


def changed(lst, task, sid, a, verb):
    store.settle(sid)
    r = dict(row(lst, task, datetime.now().replace(second=0, microsecond=0)), undo=sid)
    return r if a.json else f"{verb}: {text_row(r)}"


def from_stdin(a):
    """The window's new task as JSON on stdin, so a title that starts with "--" is no option, and the day and the time
    come as the two fields they were typed in (when.at)"""
    try:
        d = json.load(sys.stdin)
    except ValueError:
        raise ValueError("The new task wasn't readable JSON.") from None
    a.title = [str(d.get("title") or "")]
    a.list, a.note = d.get("list") or None, d.get("note") or ""
    a.priority = d.get("priority") or "normal"
    if a.priority not in PRIORITY:
        raise ValueError(f"No priority {a.priority!r}: high, normal or low.")
    return when.at(d.get("day"), d.get("time"))


def cmd_add(a):
    due = from_stdin(a) if a.stdin else when.parse(a.due) if a.due else None
    title = " ".join(a.title).strip()
    if not title:
        raise ValueError("A task needs a title.")
    task = ics.Task.new(title)
    if due is not None:
        task.set_time("DUE", due)
    task.set("DESCRIPTION", a.note or "")
    task.set("PRIORITY", PRIORITY[a.priority])
    lst = store.find_list(a.list, make=True)
    path = store.path_for(lst, task)
    sid = store.snapshot([path], made=lst if lst.get("made") else None)
    store.save(path, task)
    return changed(lst, task, sid, a, "Added")


def cmd_when(a):
    """The window's reading of its day and time fields as they are typed (or a --due text): what the task will say"""
    due = when.at(a.day, a.time) if a.day is not None or a.time is not None else when.parse(" ".join(a.text))
    now = datetime.now()
    out = {"due": ics.as_text(due), "label": when.label(due, now) if due is not None else ""}
    return out if a.json else out["label"] or "No due"


def set_due(task, due):
    """A new due, or none; a DTSTART after it would make the task invalid, so it goes (an earlier one stays)"""
    task.set_time("DUE", due)
    start = task.time("DTSTART")
    if start is not None and (due is None or when.due_at(start) > when.due_at(due)):
        task.remove("DTSTART")


def edit_stdin(a):
    """The window's edit as JSON: only the keys of what was changed, so a field left alone (a low priority, a due in
    another zone) stays exactly as the file has it"""
    try:
        d = json.load(sys.stdin)
    except ValueError:
        raise ValueError("The change wasn't readable JSON.") from None
    a.id = str(d.get("id") or "")
    a.title = d.get("title")
    a.note = d.get("note")
    a.list = d.get("list")
    a.priority = d.get("priority")
    if "day" in d or "time" in d:
        a.due_value = when.at(d.get("day"), d.get("time"))
        a.due_set = True


def cmd_edit(a):
    a.due_set = False
    if a.stdin:
        edit_stdin(a)
    elif a.no_due or a.due:
        a.due_set, a.due_value = True, None if a.no_due else when.parse(a.due)
    if a.priority is not None and a.priority not in PRIORITY:
        raise ValueError(f"No priority {a.priority!r}: high, normal or low.")
    if a.title is None and a.note is None and a.list is None and a.priority is None and not a.due_set:
        raise ValueError("Nothing to change: give --title, --due (or --no-due), --note, --list or --priority.")
    lst, path, task = store.find(a.id)
    if a.title is not None:
        if not a.title.strip():
            raise ValueError("A task needs a title.")
        task.set("SUMMARY", a.title.strip())
    if a.note is not None:
        task.set("DESCRIPTION", a.note.strip())
    if a.priority is not None:
        task.set("PRIORITY", PRIORITY[a.priority])
    if a.due_set:
        set_due(task, a.due_value)
    # Another list is another folder: the same file name there, the old one gone, both in the snapshot so the undo
    # puts it back where it was
    dest_list = store.find_list(a.list, make=True) if a.list is not None else lst
    dest = dest_list["path"] / path.name
    if dest != path and dest.exists():
        raise ValueError(f"{dest_list['name']} has a task with this file name already: nothing was changed.")
    sid = store.snapshot([path] if dest == path else [path, dest], made=dest_list if dest_list.get("made") else None)
    store.save(dest, task)
    if dest != path:
        path.unlink()
    return changed(dest_list, task, sid, a, "Changed")


def cmd_done(a):
    lst, path, task = store.find(a.id)
    if is_done(task):
        raise ValueError(f"{task.get('SUMMARY')!r} is done already.")
    sid = store.snapshot([path])
    task.set("STATUS", "COMPLETED")
    task.put(ics.Line("COMPLETED", {}, ics.stamp()))
    task.put(ics.Line("PERCENT-COMPLETE", {}, "100"))
    store.save(path, task)
    return changed(lst, task, sid, a, "Done")


def cmd_undone(a):
    """Back among the open ones, as before it was ticked: the window's Space in Done"""
    lst, path, task = store.find(a.id)
    if not is_done(task):
        raise ValueError(f"{task.get('SUMMARY')!r} isn't done.")
    sid = store.snapshot([path])
    task.set("STATUS", "NEEDS-ACTION")
    task.remove("COMPLETED")
    task.remove("PERCENT-COMPLETE")
    store.save(path, task)
    return changed(lst, task, sid, a, "Not done")


def cmd_snooze(a):
    lst, path, task = store.find(a.id)
    now = datetime.now()
    due = when.parse(a.until, now) if a.until else when.later(task.time("DUE"), now)
    sid = store.snapshot([path])
    set_due(task, due)
    store.save(path, task)
    return changed(lst, task, sid, a, "Moved")


def cmd_trash(a):
    lst, path, task = store.find(a.id)
    sid = store.snapshot([path])
    store.trash(path)
    return changed(lst, task, sid, a, "Moved to the trash")


def cmd_restore(a):
    paths = store.restore(a.undo)
    out = {"restored": [str(p.relative_to(store.DATA)) for p in paths]}
    return out if a.json else "Put back as it was."


def parser():
    p = argparse.ArgumentParser(prog="tasks")
    sub = p.add_subparsers(dest="cmd", required=True)

    def command(name, fn):
        c = sub.add_parser(name)
        c.add_argument("--json", action="store_true")
        c.set_defaults(fn=fn)
        return c

    command("lists", cmd_lists)
    c = command("list", cmd_list)
    c.add_argument("--list")
    c.add_argument("--view", choices=VIEWS, default="open")
    c.add_argument("--query")
    c = command("add", cmd_add)
    c.add_argument("--list")
    c.add_argument("--due")
    c.add_argument("--note")
    c.add_argument("--priority", choices=tuple(PRIORITY), default="normal")
    c.add_argument("--stdin", action="store_true")
    c.add_argument("title", nargs="*")
    c = command("when", cmd_when)
    c.add_argument("--day")
    c.add_argument("--time")
    c.add_argument("text", nargs="*")
    c = command("edit", cmd_edit)
    c.add_argument("--title")
    c.add_argument("--due")
    c.add_argument("--no-due", action="store_true")
    c.add_argument("--note")
    c.add_argument("--list")
    c.add_argument("--priority", choices=tuple(PRIORITY))
    c.add_argument("--stdin", action="store_true")
    c.add_argument("id", nargs="?", default="")
    command("done", cmd_done).add_argument("id")
    command("undone", cmd_undone).add_argument("id")
    c = command("snooze", cmd_snooze)
    c.add_argument("--until")
    c.add_argument("id")
    command("trash", cmd_trash).add_argument("id")
    command("restore", cmd_restore).add_argument("undo")
    lists.add_commands(command)
    return p


def main(argv):
    a = parser().parse_args(argv)
    try:
        out = a.fn(a)
    except (ValueError, store.NotFound) as e:
        sys.exit(str(e))
    print(json.dumps(out, ensure_ascii=False, indent=1) if a.json else out)


if __name__ == "__main__":
    main(sys.argv[1:])
