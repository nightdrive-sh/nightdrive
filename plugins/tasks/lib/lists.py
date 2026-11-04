#!/usr/bin/env python3
"""The lists' own changes, for `tasks list-new / list-rename / list-remove` (cli.py adds them to its commands), the
window and Claude's tools (mcp.json). A list is a folder of the vdir with its name in `displayname` (store.py):

- a new one is a new folder, named from its name (store.find_list);
- a rename changes only `displayname`: the folder, which is the list's id and a sync's collection, stays;
- a removal takes the folder away, its tasks to the trash (store.trash, 30 days) and the rest of its files with it.

Each keeps what it changed in a snapshot, so `tasks restore UNDO` puts it back as it was: a removed list comes back
with every task and file it had, and they leave the trash.
"""

import store

NAME_MAX = 100      # characters: a list's name is a sidebar row, not a note


def clean(name):
    """A list's name as it is kept: one line, trimmed, not empty"""
    name = " ".join((name or "").split())
    if not name:
        raise ValueError("A list needs a name.")
    if len(name) > NAME_MAX:
        raise ValueError(f"A list's name is at most {NAME_MAX} characters.")
    return name


def taken(name, but=None):
    """The list that has this name already (any case), other than but's"""
    for l in store.lists():
        if l["name"].lower() == name.lower() and (but is None or l["id"] != but["id"]):
            return l
    return None


def counts(lst):
    """(all, open) tasks in a list"""
    tasks = store.load(lst)
    return len(tasks), sum(1 for _, _, t in tasks if not store.is_done(t))


def out(lst, sid, a, said, **more):
    store.settle(sid, names=True)
    total, open_ = counts(lst) if lst["path"].is_dir() else (more.pop("tasks", 0), more.pop("open", 0))
    r = dict({"id": lst["id"], "name": lst["name"], "tasks": total, "open": open_, "undo": sid}, **more)
    return r if a.json else said


def cmd_new(a):
    name = clean(a.name)
    if taken(name):
        raise ValueError(f"There is a list called {taken(name)['name']!r} already.")
    lst = store.find_list(name, make=True)
    sid = store.snapshot([], made=lst)
    return out(lst, sid, a, f"Made the list {name}.")


def cmd_rename(a):
    lst = store.find_list(a.list)
    name = clean(a.name)
    other = taken(name, but=lst)
    if other:
        raise ValueError(f"There is a list called {other['name']!r} already.")
    if name == lst["name"]:
        raise ValueError(f"The list is called {name!r} already.")
    old = lst["name"]
    named = lst["path"] / "displayname"
    sid = store.snapshot([named])
    store.write(named, name + "\n")
    return out(dict(lst, name=name), sid, a, f"Renamed the list {old} to {name}.", old=old)


def cmd_remove(a):
    """Refuses a list with tasks in it unless --with-tasks says they go too: a removal Claude asks for by a list's name
    mustn't take tasks the user didn't know were in it"""
    lst = store.find_list(a.list)
    total, open_ = counts(lst)
    if total and not a.with_tasks:
        raise ValueError(f"{lst['name']} has {total} task{'s' * (total != 1)} ({open_} open): --with-tasks moves "
                         "them to the trash with it.")
    if any(p.is_dir() for p in lst["path"].iterdir()):
        raise ValueError(f"{lst['name']}'s folder has folders in it, which Tasks doesn't keep: nothing was changed.")
    # Every file the folder has, so the undo makes it again as it was (a sync's own files too); hidden ones are
    # unfinished writes (store.write's) and go with it
    files = sorted(p for p in lst["path"].iterdir() if not p.name.startswith("."))
    try:
        sid = store.snapshot(files)
    except UnicodeDecodeError:
        raise ValueError(f"{lst['name']}'s folder has a file that isn't text, which an undo couldn't put back: "
                         "nothing was changed.") from None
    for p in files:
        if p.suffix == ".ics":
            store.trash(p)
    store.remove_list(lst)
    return out(lst, sid, a, f"Removed the list {lst['name']}" + (f" and its {total} tasks." if total else "."),
               tasks=total, open=open_)


def add_commands(command):
    """The commands in cli.py's parser: command(name, fn) gives a subparser with --json"""
    c = command("list-new", cmd_new)
    c.add_argument("name")
    c = command("list-rename", cmd_rename)
    c.add_argument("list")
    c.add_argument("name")
    c = command("list-remove", cmd_remove)
    c.add_argument("--with-tasks", action="store_true")
    c.add_argument("list")
