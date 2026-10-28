"""The notes themselves: Markdown files in ~/Notes (NOTES_DIR), each one a note. notes.py (the `notes` command) and,
through it, the window and Claude's tools read them only through here, so what counts as a note, its id and its title
are the same everywhere.

A note's id is its path inside the folder, as Apostrophe and Files show it: "Shopping.md", "Work/Plan.md". Only .md
files count, and nothing hidden (no part of the path starts with a dot): Apostrophe's and git's own files stay out, and an
id can't lead out of the folder.
"""

import os
import re
from datetime import datetime
from pathlib import Path

ROOT = Path(os.environ.get("NOTES_DIR") or Path.home() / "Notes")
SUFFIX = ".md"
EXCERPT_MAX = 120     # characters of a note's first line of text in a listing
NAME_MAX = 80         # characters of a new note's file name, from its title


class NoteError(Exception):
    """A note that isn't there or can't be: the message is for a reader (or Claude) to act on."""


def visible(rel):
    return not any(part.startswith(".") for part in rel.parts)


def all_paths():
    """Every note's path, newest first (by when it was last saved)."""
    if not ROOT.is_dir():
        return []
    found = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        found += [p for f in filenames if f.endswith(SUFFIX) and not f.startswith(".")
                  and inside(p := Path(dirpath) / f)]
    return sorted(found, key=lambda p: p.stat().st_mtime, reverse=True)


def inside(path):
    """A link that leads out of the folder isn't a note: an id must never reach a file elsewhere."""
    return path.resolve().is_relative_to(ROOT.resolve())


def note_id(path):
    return path.relative_to(ROOT).as_posix()


def path_of(nid):
    """The file of an id, checked: inside the folder, not hidden, a .md file that is there."""
    rel = Path(nid.strip().lstrip("/"))
    if not nid.strip() or ".." in rel.parts or not visible(rel) or rel.suffix != SUFFIX:
        raise NoteError(f"{nid!r} isn't a note's id: ids are paths inside {home(ROOT)} ending in .md (notes list).")
    path = ROOT / rel
    if not path.is_file() or not inside(path):
        raise NoteError(f"There's no note {nid} in {home(ROOT)} (notes list gives the ids).")
    return path


def find(who):
    """A note by its id, else by its title (case aside), else by its id without .md: Claude and a terminal may say
    either."""
    who = who.strip()
    if who.endswith(SUFFIX):
        return path_of(who)
    paths = all_paths()
    want = who.lower()
    for p in paths:
        if title_of(p).lower() == want or note_id(p)[:-len(SUFFIX)].lower() == want:
            return p
    raise NoteError(f"There's no note {who!r} in {home(ROOT)}: notes list gives the ids, notes search finds by text.")


def read_text(path):
    return path.read_text(encoding="utf-8", errors="replace")


def title_of(path, text=None):
    """The note's first heading (# …) when it starts with one, else its file name."""
    if text is None:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read(4096)
    for line in text.splitlines():
        if line.strip():
            m = re.match(r"#{1,6}\s+(.+?)\s*#*\s*$", line)
            return m.group(1) if m else path.stem
    return path.stem


def plain(line):
    """A line of Markdown as it reads: a link's text, without the marks for bold, code, a list or a quote."""
    line = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", line)
    line = re.sub(r"^(?:[-*+>]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)", "", line)
    return re.sub(r"(\*\*|__|`|~~|(?<!\w)[*_](?=\S)|(?<=\S)[*_](?!\w))", "", line).strip()


def excerpt(text):
    """The first line that isn't a heading, as it reads, as a listing's second line."""
    for line in text.splitlines():
        line = plain(line)
        if line and not line.startswith("#"):
            return line if len(line) <= EXCERPT_MAX else line[:EXCERPT_MAX - 1] + "…"
    return ""


def modified(path):
    return datetime.fromtimestamp(path.stat().st_mtime).astimezone().isoformat(timespec="seconds")


def brief(path, text=None):
    """A row of a listing: what tells notes apart."""
    text = read_text(path) if text is None else text
    return {"id": note_id(path), "title": title_of(path, text), "modified": modified(path),
            "excerpt": excerpt(text), "size": path.stat().st_size}


def new_path(title):
    """Where a new note titled so goes: its title as the file name ("Shopping list.md"), with a number after it when
    that is taken ("Shopping list 2.md")."""
    name = re.sub(r"[/\\\x00-\x1f]", " ", title).strip().lstrip(".").strip()
    name = re.sub(r"\s+", " ", name)[:NAME_MAX].strip() or "Note"
    path, n = ROOT / f"{name}{SUFFIX}", 2
    while path.exists():
        path, n = ROOT / f"{name} {n}{SUFFIX}", n + 1
    return path


def home(path):
    return str(path).replace(str(Path.home()), "~", 1)
