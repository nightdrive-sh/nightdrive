#!/usr/bin/env python3
"""The `notes` command's work on the notes (bin/notes runs it): listing, finding and reading them for the window, a
terminal and Claude's tools (mcp.json), and the three changes Claude can make, each one the user can undo.

    notes.py list [--json] [--limit N]           newest first (N: 50 by default, 0 for all)
    notes.py search [--json] [--limit N] WORDS…  the notes that have every word, in the title or the text
    notes.py read [--json] NOTE                  one note's whole text: NOTE is an id, or a title
    notes.py create [--json] TITLE               a new note: "# TITLE", then the text on stdin
    notes.py append [--json] NOTE                the text on stdin added to the end of the note
    notes.py unappend NOTE BEFORE AFTER          append's undo: back to BEFORE bytes, if it is still AFTER long
    notes.py trash [--json] NOTE                 to the desktop's trash (`nightdrive files trash`), where Files puts
                                                 it back; nothing is deleted for good

Without --json they print text for a terminal. An error goes to stderr in plain words, with exit status 1.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import store
from store import NoteError

LIST_LIMIT = 50       # list's default: the recent ones, which is what Claude and a terminal usually want
SEARCH_LIMIT = 25
MATCH_LINES = 3       # lines of a found note that show where the words are
NIGHTDRIVE = Path(__file__).resolve().parents[3] / "bin/nightdrive"   # this checkout's, for its files trash


def list_notes(limit):
    paths = store.all_paths()
    shown = paths if limit == 0 else paths[:limit]
    return {"folder": store.home(store.ROOT), "count": len(paths), "notes": [store.brief(p) for p in shown]}


def search(query, limit):
    words = query.lower().split()
    found = []
    for p in store.all_paths():
        text = store.read_text(p)
        hay = (store.title_of(p, text) + "\n" + text).lower()
        if all(w in hay for w in words):
            lines = [ln.strip() for ln in text.splitlines() if any(w in ln.lower() for w in words) and ln.strip()]
            found.append(dict(store.brief(p, text), lines=lines[:MATCH_LINES]))
    return {"query": query, "count": len(found), "notes": found[:limit]}


def read(who):
    p = store.find(who)
    text = store.read_text(p)
    return dict(store.brief(p, text), path=str(p), text=text)


def create(title, text):
    title = " ".join(title.split())
    if not title:
        raise NoteError("A new note needs a title.")
    store.ROOT.mkdir(parents=True, exist_ok=True)
    p = store.new_path(title)
    body = text.strip("\n")
    p.write_text(f"# {title}\n" + (f"\n{body}\n" if body else ""), encoding="utf-8")
    return dict(store.brief(p), path=str(p))


def append(who, text):
    """The text at the end, on a line of its own; the sizes before and after are what undoing it checks."""
    if not text.strip():
        raise NoteError("There's nothing to add: the text is empty.")
    p = store.find(who)
    before = p.stat().st_size
    with open(p, "rb") as f:
        f.seek(max(0, before - 1))
        ends_in_newline = before == 0 or f.read(1) == b"\n"
    with open(p, "a", encoding="utf-8") as f:
        f.write(("" if ends_in_newline else "\n") + text.rstrip("\n") + "\n")
    return dict(store.brief(p), size_before=before, size_after=p.stat().st_size)


def unappend(who, before, after):
    """Takes off what append added, only while the note is as append left it: an edit since then is the user's."""
    p = store.path_of(who)
    if p.stat().st_size != after:
        raise NoteError(f"{who} has changed since the text was added, so it's left as it is (Apostrophe can take "
                        "the text out).")
    with open(p, "r+b") as f:
        f.truncate(before)
    return store.brief(p)


def trash(who):
    p = store.find(who)
    note = store.brief(p)
    # Without the MCP server's variables: files would hold a note to the folders Access gives Claude's file tools,
    # which ~/Notes isn't among, and fail every time (#1863). store.find has kept the path to a note in ~/Notes
    env = {k: v for k, v in os.environ.items() if not k.startswith("NIGHTDRIVE_MCP")}
    done = subprocess.run([str(NIGHTDRIVE), "files", "trash", "--json", "--", str(p)],
                          capture_output=True, text=True, env=env)
    if done.returncode != 0:
        raise NoteError(done.stderr.strip() or "The note couldn't be moved to the trash.")
    return dict(json.loads(done.stdout), id=note["id"], title=note["title"])


# --- the terminal's text ----------------------------------------------------------------------------------------------

def when(note):
    return note["modified"][:16].replace("T", " ")


def text_list(result):
    if not result["notes"]:
        return f"No notes in {result['folder']} yet."
    rows = [f"{when(n)}  {n['title']}    ({n['id']})" for n in result["notes"]]
    more = result["count"] - len(result["notes"])
    return "\n".join(rows + ([f"… and {more} more: --limit 0 lists them all"] if more > 0 else []))


def text_search(result):
    if not result["notes"]:
        return f"No note has {result['query']!r}."
    out = []
    for n in result["notes"]:
        out += [f"{n['title']}    ({n['id']})"] + [f"  {ln}" for ln in n["lines"]]
    return "\n".join(out)


def output(result, as_json, text):
    print(json.dumps(result, ensure_ascii=False) if as_json else text(result))


def options(rest, default_limit):
    as_json = "--json" in rest
    rest = [a for a in rest if a != "--json"]
    limit = default_limit
    if "--limit" in rest:
        i = rest.index("--limit")
        try:
            limit = max(0, int(rest[i + 1]))
        except (IndexError, ValueError):
            raise NoteError("--limit takes a number (0 for all).")
        del rest[i:i + 2]
    return as_json, limit, " ".join(rest).strip()


def stdin_text():
    return "" if sys.stdin.isatty() else sys.stdin.read()


def main(argv):
    if not argv:
        sys.exit(__doc__)
    command, rest = argv[0], argv[1:]
    as_json, limit, arg = options(rest, SEARCH_LIMIT if command == "search" else LIST_LIMIT)
    if command == "list":
        output(list_notes(limit), as_json, text_list)
    elif command == "search":
        if not arg:
            raise NoteError("Usage: notes search WORDS…")
        output(search(arg, limit or SEARCH_LIMIT), as_json, text_search)
    elif not arg:
        raise NoteError(f"Usage: notes {command} {'TITLE' if command == 'create' else 'NOTE'} (see notes help)")
    elif command == "read":
        output(read(arg), as_json, lambda n: n["text"].rstrip("\n"))
    elif command == "create":
        output(create(arg, stdin_text()), as_json, lambda n: f"Created {n['path']}")
    elif command == "append":
        output(append(arg, stdin_text()), as_json, lambda n: f"Added to {n['id']}")
    elif command == "unappend":
        try:
            plain = [a for a in rest if a != "--json"]
            who, before, after = plain[0], int(plain[1]), int(plain[2])
        except (IndexError, ValueError):
            raise NoteError("Usage: notes unappend NOTE BEFORE AFTER (sizes in bytes, as append --json gives them)")
        output(unappend(who, before, after), as_json, lambda n: f"Took the added text off {n['id']}")
    elif command == "trash":
        output(trash(arg), as_json, lambda n: f"Moved {n['id']} to the trash")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except NoteError as e:
        sys.exit(str(e))
