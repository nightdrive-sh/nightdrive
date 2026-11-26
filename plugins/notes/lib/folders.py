"""The notes' folders: real folders in ~/Notes, as Files shows them, so a note moved here is moved there too (#2016).
notes.py hands the folder commands to main() here:

    folders [--json]                       every folder (empty ones too) with how many notes are in it and under it,
                                           and every tag (#word in the text, tags.py) with how many notes have it
    mkdir [--json] [--] FOLDER             a new folder, FOLDER its path ("Work", "Work/Plans"); its parents made too
    rmdir [--json] [--] FOLDER             an empty folder taken away (one with anything in it is left as it is)
    move [--json] [--] NOTE FOLDER         the note into FOLDER ("" for the top), its file name kept (a number added when
                                           that is taken); a FOLDER not there yet is made. Its own undo is a move back.

A folder's path is like a note's id without the file: inside the folder, no part hidden (starting with a dot).
"""

import os
from pathlib import Path

import store
import tags as tagging
from store import NoteError

FOLDER_MAX = 80     # characters of a folder's own name


def folder_of(nid):
    """The folder a note is in, "" at the top: "Work/Plans/Q3.md" is in "Work/Plans"."""
    parent = Path(nid).parent.as_posix()
    return "" if parent == "." else parent


def under(folder, sub):
    """Whether sub is folder or inside it ("" holds them all)."""
    return not folder or sub == folder or sub.startswith(folder + "/")


def all_folders():
    """Every folder in the notes' folder, by path: what os.walk sees (links to folders aren't followed, so none leads out),
    nothing hidden."""
    if not store.ROOT.is_dir():
        return []
    found = []
    for dirpath, dirnames, _ in os.walk(store.ROOT):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        found += [(Path(dirpath) / d).relative_to(store.ROOT).as_posix() for d in dirnames]
    return sorted(found, key=str.lower)


def checked(folder, must_exist=True):
    """A folder's path, checked as path_of checks a note's: "" or "/" for the top."""
    folder = folder.strip().strip("/")
    if not folder:
        return ""
    rel = Path(folder)
    if ".." in rel.parts or not store.visible(rel) or any(len(p) > FOLDER_MAX for p in rel.parts):
        raise NoteError(f"{folder!r} can't be a folder of notes: a path inside {store.home(store.ROOT)}, no part "
                        f"starting with a dot, each name at most {FOLDER_MAX} characters.")
    path = store.ROOT / rel
    if path.is_symlink() or (path.exists() and not path.resolve().is_relative_to(store.ROOT.resolve())):
        raise NoteError(f"{folder} is a link, not a folder of notes.")
    if must_exist and not path.is_dir():
        raise NoteError(f"There's no folder {folder} in {store.home(store.ROOT)} (notes folders lists them).")
    return rel.as_posix()


def overview(notes=None):
    """The folders with their notes' counts (each one's own and all under it) and the tags with theirs."""
    if notes is None:
        notes = [store.brief(p) for p in store.all_paths()]
    folders = []
    for f in all_folders():
        own = sum(1 for n in notes if n["folder"] == f)
        folders.append({"path": f, "name": f.rsplit("/", 1)[-1], "depth": f.count("/"), "own": own,
                        "count": sum(1 for n in notes if under(f, n["folder"]))})
    return {"folder": store.home(store.ROOT), "count": len(notes), "folders": folders, "tags": tagging.counts(notes)}


def mkdir(folder):
    folder = checked(folder, must_exist=False)
    if not folder:
        raise NoteError("A new folder needs a name.")
    path = store.ROOT / folder
    if path.exists():
        raise NoteError(f"There's a folder {folder} already.")
    path.mkdir(parents=True)
    return {"path": folder, "made": True}


def rmdir(folder):
    folder = checked(folder)
    if not folder:
        raise NoteError("The notes' own folder stays.")
    try:
        (store.ROOT / folder).rmdir()
    except OSError:
        raise NoteError(f"{folder} isn't empty, so it's left as it is: move its notes out first (or use Files).")
    return {"path": folder, "removed": True}


def move(who, folder):
    """The note's file into the folder, its name kept: os.rename on the same disk, so nothing is copied or half-moved. A
    name taken there gets a number, as a new note's does; the folder is made when it isn't there yet (the window's move
    panel makes one by its name). The answer has what puts it back: a move of id to old_folder."""
    p = store.find(who)
    folder = checked(folder, must_exist=False)
    old = store.note_id(p)
    if folder_of(old) == folder:
        return dict(store.brief(p), old_id=old, old_folder=folder, moved=False)
    target_dir = store.ROOT / folder
    made = not target_dir.exists()
    target_dir.mkdir(parents=True, exist_ok=True)
    target, n = target_dir / p.name, 2
    while os.path.lexists(target):
        target, n = target_dir / f"{p.stem} {n}{store.SUFFIX}", n + 1
    os.rename(p, target)
    return dict(store.brief(target), old_id=old, old_folder=folder_of(old), moved=True, made=made)


# --- the terminal's text and the commands -----------------------------------------------------------------------------

def text_overview(r):
    lines = [f"{'  ' * f['depth']}{f['name']}/  {f['count']}" for f in r["folders"]] or [f"No folders in {r['folder']}."]
    if r["tags"]:
        lines += [""] + [f"#{t['name']}  {t['count']}" for t in r["tags"]]
    return "\n".join(lines)


def main(command, rest, output):
    """The folder commands' words: whole arguments, as a folder's name and a note's title may have spaces."""
    as_json = "--json" in rest
    words = [a for a in rest if a != "--json"]
    if words[:1] == ["--"]:
        words = words[1:]
    if command == "folders":
        output(overview(), as_json, text_overview)
    elif command in ("mkdir", "rmdir"):
        if len(words) != 1:
            raise NoteError(f"Usage: notes {command} FOLDER (quoted if it has spaces)")
        if command == "mkdir":
            output(mkdir(words[0]), as_json, lambda r: f"Made {r['path']}")
        else:
            output(rmdir(words[0]), as_json, lambda r: f"Took {r['path']} away")
    elif command == "move":
        if len(words) != 2:
            raise NoteError('Usage: notes move NOTE FOLDER ("" for the top; quote each one that has spaces)')
        output(move(*words), as_json, lambda r: f"Moved {r['old_id']} to {r['id']}" if r["moved"]
               else f"{r['id']} is there already")
