"""Making a folder, and moving or renaming files and folders (#1995): `nightdrive files mkdir|move|rename`, and
`move-back`, which undoes any of them. Claude's files_mkdir, files_move and files_rename run these
(config/mcp/tools/apps-files.json), so they keep files_rules.py's rules, both ways:

- What moves is checked as a trash checks it (files_rules.checked): in home, not hidden, not home's own folders, in
  Claude's folders, nothing out of your mail, notes, projects, a mail folder or a git repository.
- Where it goes is too (files_rules.destination): a folder in home, not hidden, in Claude's folders and in none of
  those places, by where it really is: a link to a folder counts where it leads, so it can't lead a move out.
- Nothing is overwritten: a name already at the destination stops the whole call, which says every one in the way.
- All or none: a move that fails halfway puts back what it moved, and the folder it made goes.
- Only a rename on the same disk (os.rename): nothing is copied, so a move is exact and its undo too.
- move-back keeps the same rules (Undo runs it with Claude's Access as it is now), so an undo edited by hand in the
  log can't move anything anywhere a move couldn't. It moves back only what is still where the move put it, into a
  place that is free again, and removes a folder the move made only while it is empty.

  files mkdir PATH [--json] [--check]
                                   one new folder (its folder must exist); --json: {made, back: [], what, in}
  files move --into FOLDER PATH… [--json] [--check] [--asks]
                                   into FOLDER, which is made when it isn't there; --json: {moved: [new paths], back:
                                   [new, old, …], made: the folder made or "", what, into}. --check: the card's lines;
                                   --asks: yes when the move reaches further than Modify's Allow should cover alone
  files rename PATH NAME [--json] [--check]
                                   a new name in the same folder; --json: {renamed, back: [new, old], made: "", what, name}
  files move-back [--made FOLDER] [-- NEW OLD …]
                                   each NEW back to OLD, then FOLDER removed if empty: the undo of all three
"""
import json, os
from pathlib import Path

from files_rules import (HOME, checked, claude_folders, count, destination, die, guarded, shown, valid_name,
                         what_goes, what_of, within)

# A move asks on the card though Access allows it (apps-files.json's asks_if) when it takes a folder, more files than
# this, or moves from one of Claude's folders into another: tidying a folder runs with Undo, reshaping home asks
ASK_FILES = 50
GUARDED_MOVE = "move anything out of there or into it"


def same_disk(path, folder):
    """Dies unless a rename can take path into folder: a copy across disks isn't a move Undo can take back exactly."""
    if path.lstat().st_dev != folder.stat().st_dev:
        die(f"{shown(path)} is on another disk than {shown(folder)}: it isn't moved (only within one disk).")


def rename_all(pairs, made=None):
    """Renames each (old, new), all or none: on a failure what moved goes back, the folder made goes, and it dies."""
    done = []
    for old, new in pairs:
        try:
            if os.path.lexists(new):   # came in since the checks
                raise FileExistsError(17, "something is there now", str(new))
            os.rename(old, new)
            done.append((old, new))
        except OSError as e:
            for o, n in reversed(done):
                os.rename(n, o)
            if made:
                os.rmdir(made)
            die(f"{shown(old)} couldn't be moved to {shown(new)} ({e.strerror}); nothing was.")


def show(out, json_out, text):
    print(json.dumps(out, ensure_ascii=False) if json_out else text)


# --- mkdir ------------------------------------------------------------------------------------------------------

def cmd_mkdir(a):
    path, _ = destination(a.path, new=True)
    if a.check:
        print(json.dumps({"New folder": shown(path)}, ensure_ascii=False))
        return
    try:
        os.mkdir(path)
    except OSError as e:
        die(f"{a.path} couldn't be made ({e.strerror}).")
    show({"made": str(path), "back": [], "what": path.name, "in": shown(path.parent) if path.parent != HOME else "~"},
         a.json, f"Made {path}")


# --- move -------------------------------------------------------------------------------------------------------

def planned(a):
    """The checked move: (folder, whether it is made, [(old, new)]); dies with every reason it can't go."""
    folder, make = destination(a.into)
    sources = list(dict.fromkeys(checked(p, moving=True, doing=GUARDED_MOVE) for p in a.paths))
    blocked, pairs, names = [], [], {}
    for src in sources:
        new = folder / src.name
        if src == folder or src in folder.parents:
            die(f"{shown(src)} can't be moved into itself.")
        if src.parent == folder:
            die(f"{shown(src)} is in {shown(folder)} already.")
        if os.path.lexists(new) or src.name in names:
            blocked.append(src.name)
        elif guarded(new) and claude_folders() is not None:
            die(f"{shown(new)} would be in {guarded(new)}: Claude doesn't {GUARDED_MOVE}.")
        names[src.name] = src
        pairs.append((src, new))
    if blocked:
        die(f"Already in {shown(folder)}: {', '.join(blocked)}. Nothing was moved and nothing is overwritten: ask "
            "the user for another name, or rename first.")
    for src, _ in pairs:
        same_disk(src, folder if not make else folder.parent)
    return folder, make, pairs


def top_folder(path, folders):
    """The deepest of Claude's folders path is in, to tell a move within one from a move between two."""
    return max((f for f in folders if within(path, [f])), key=lambda f: len(f.parts), default=None)


def asks(folder, pairs):
    """Whether a move asks on the card though Access allows it (ASK_FILES)."""
    folders = claude_folders()
    if folders is None:
        return False
    files = 0
    for src, _ in pairs:
        if src.is_dir() and not src.is_symlink():
            return True
        files += 1
    if files > ASK_FILES:
        return True
    to = top_folder(folder, folders)
    return any(top_folder(src, folders) != to for src, _ in pairs)


def cmd_move(a):
    folder, make, pairs = planned(a)
    into = shown(folder) if folder != HOME else "~"
    if a.asks:
        print("yes" if asks(folder, pairs) else "no")
        return
    if a.check:
        print(json.dumps({"Move": "\n".join(what_goes(src) for src, _ in pairs),
                          "Into": into + ("  (a new folder)" if make else "")}, ensure_ascii=False))
        return
    what = what_of([src for src, _ in pairs])   # before the move: a folder moved away is no folder here
    if make:
        try:
            os.mkdir(folder)
        except OSError as e:
            die(f"{a.into} couldn't be made ({e.strerror}); nothing was moved.")
    rename_all(pairs, folder if make else None)
    out = {"moved": [str(n) for _, n in pairs], "back": [str(p) for o, n in pairs for p in (n, o)],
           "made": str(folder) if make else "", "what": what, "into": into}
    show(out, a.json, "\n".join(f"Moved {o} to {n}" for o, n in pairs))


# --- rename -----------------------------------------------------------------------------------------------------

def cmd_rename(a):
    src = checked(a.path, moving=True, doing="rename anything there")
    name = valid_name(a.name)
    new = src.parent / name
    if new == src:
        die(f"{shown(src)} has that name already.")
    if os.path.lexists(new):
        die(f"{shown(new)} exists already: nothing is overwritten. Ask the user for another name.")
    if claude_folders() is not None and guarded(new):
        die(f"{shown(new)} would be in {guarded(new)}: Claude doesn't rename anything into it.")
    if a.check:
        print(json.dumps({"Rename": what_goes(src), "To": name}, ensure_ascii=False))
        return
    rename_all([(src, new)])
    show({"renamed": str(new), "back": [str(new), str(src)], "made": "", "what": src.name, "name": name},
         a.json, f"Renamed {src} to {new}")


# --- move-back (the undo of all three) --------------------------------------------------------------------------

def back_to(arg):
    """Where a move-back puts one thing: a free place in a folder a move could go into, by the same rules."""
    p = Path(arg)
    if not p.is_absolute():
        die(f"{arg} isn't an absolute path.")
    folder, _ = destination(str(p.parent), new=False)
    path = folder / valid_name(p.name, arg)
    if os.path.lexists(path):
        die(f"Something new is at {shown(path)}: nothing was moved back.")
    return path


def cmd_move_back(a):
    if len(a.back) % 2:
        die("move-back takes pairs: where each thing is now, then where it was.")
    pairs = []
    for now, was in zip(a.back[::2], a.back[1::2]):
        if not os.path.lexists(now):
            die(f"{now} isn't there any more: nothing was moved back.")
        src = checked(now, moving=True, doing=GUARDED_MOVE)
        old = back_to(was)
        same_disk(src, old.parent)
        pairs.append((src, old))
    made = destination(a.made, new=False)[0] if a.made else None
    rename_all(pairs)
    for src, old in pairs:
        print(f"Moved {src} back to {old}")
    if made:
        try:
            os.rmdir(made)
            print(f"Removed the folder {made}")
        except OSError:
            if not pairs:   # mkdir's undo: removing it is all it does
                die(f"{shown(made)} has files in it now: it stays.")
            print(f"{made} has files in it now: it stays.")


def add_parsers(sub):
    """files's subcommands from here."""
    p = sub.add_parser("mkdir"); p.add_argument("path")
    p.add_argument("--json", action="store_true"); p.add_argument("--check", action="store_true")
    p.set_defaults(fn=cmd_mkdir)
    p = sub.add_parser("move"); p.add_argument("--into", required=True); p.add_argument("paths", nargs="+")
    p.add_argument("--json", action="store_true"); p.add_argument("--check", action="store_true")
    p.add_argument("--asks", action="store_true"); p.set_defaults(fn=cmd_move)
    p = sub.add_parser("rename"); p.add_argument("path"); p.add_argument("name")
    p.add_argument("--json", action="store_true"); p.add_argument("--check", action="store_true")
    p.set_defaults(fn=cmd_rename)
    p = sub.add_parser("move-back"); p.add_argument("--made", default=""); p.add_argument("back", nargs="*")
    p.set_defaults(fn=cmd_move_back)
