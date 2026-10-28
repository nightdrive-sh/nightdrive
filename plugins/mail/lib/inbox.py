#!/usr/bin/env python3
"""Archiving and deleting from the inbox without Mail's window: for the notifications' buttons, scripts and Claude's
tools (mcp.json).

    inbox.py archive ID…             the inbox's copies to Archive, as Mail's a does
    inbox.py unarchive ID…           back to the inbox (archive's undo)
    inbox.py delete [--check] ID…    the inbox's copies to Trash, as Mail's d does

An ID is a message's id, or a thread ("thread:0000000000000005"): then its messages in the inbox. Only what is in the
inbox moves, so your own replies stay in Sent, and the moves are move.py's (Gmail's All Mail is kept). Prints
{"moved": N, "ids": [the messages moved], "subjects": "…"}; nothing to move is an error.

delete --check reads {"subjects": […]} on stdin, one for each ID in order, as `nightmail search` or `thread` gave them
(Claude's confirmation card shows them, since an id says nothing to the user), and deletes nothing if one isn't the
subject of its ID. Failures go to stderr with exit status 1.
"""

import json
import os
import subprocess
import sys

import browse

HERE = os.path.dirname(os.path.abspath(__file__))
INBOX = "tag:inbox"
SUBJECTS_MAX = 100   # characters of "subjects", the line of a notification


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def term(ident):
    return ident if ident.startswith("thread:") else f'id:"{ident}"'


def either(terms):
    return "(" + " or ".join(terms) + ")"


def subject(ident):
    found = json.loads(notmuch("search", "--format=json", "--exclude=false", "--limit=1", term(ident)) or "[]")
    if not found:
        raise LookupError(f"No message or thread {ident}")
    return found[0].get("subject", "")


def subjects_of(ident):
    """The subjects a thread (or a message) goes by: the thread's, and each of its messages' ("Re: …")."""
    shown = json.loads(notmuch("show", "--format=json", "--body=false", "--exclude=false", term(ident)) or "[]")
    return {subject(ident).strip()} | {m["headers"].get("Subject", "").strip() for m in browse.walk(shown, [])}


def check(idents, shown):
    """Each ID's subject is one the user was shown for it."""
    if len(shown) != len(idents):
        raise LookupError(f"Nothing deleted: {len(idents)} ids but {len(shown)} subjects; give one subject for each.")
    for ident, said in zip(idents, shown):
        if str(said).strip() not in subjects_of(ident):
            raise LookupError(f"Nothing deleted: {ident}'s subject is {subject(ident)!r}, not {said!r}.")


def move(to, query, source, tag):
    """The query's messages to the folder `to` from `source`; their ids and subjects."""
    ids = notmuch("search", "--output=messages", "--exclude=false", query).split()
    if not ids:
        return [], []
    exact = either(f'id:"{i.removeprefix("id:")}"' for i in ids)
    subjects = [subject(i.removeprefix("id:")) for i in ids]
    out = subprocess.run([sys.executable, os.path.join(HERE, "move.py"), to, exact, source],
                         capture_output=True, text=True, check=True).stdout
    result = json.loads(out)
    if result.get("error"):
        raise RuntimeError(result["error"])
    notmuch("tag", tag, "--", exact)
    return [i.removeprefix("id:") for i in ids], subjects


def summary(subjects):
    text = ", ".join(dict.fromkeys(f"“{s}”" for s in subjects))   # a thread's messages share one subject
    return text if len(text) <= SUBJECTS_MAX else text[:SUBJECTS_MAX - 1] + "…"


def main():
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    idents = [a for a in args if a != "--check"]
    if cmd not in ("archive", "unarchive", "delete") or not idents or ("--check" in args and cmd != "delete"):
        sys.exit("usage: inbox.py archive ID… | unarchive ID… | delete [--check] ID…")
    if "--check" in args:
        check(idents, json.loads(sys.stdin.read() or "{}").get("subjects") or [])
    asked = either(map(term, idents))
    if cmd == "unarchive":
        moved = move("INBOX", f"{asked} and not {INBOX} and folder:/Archive$/", "Archive", "+inbox")
    else:
        moved = move("Archive" if cmd == "archive" else "Trash", f"{asked} and {INBOX}", "INBOX", "-inbox")
    ids, subjects = moved
    if not ids:
        where = "in Archive" if cmd == "unarchive" else "in the inbox"
        raise LookupError(f"Nothing moved: none of {', '.join(idents)} is {where}")
    print(json.dumps({"moved": len(ids), "ids": ids, "subjects": summary(subjects)}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(f"{os.path.basename(e.cmd[0])} failed: {(e.stderr or '').strip() or e.returncode}")
    except (LookupError, RuntimeError, ValueError) as e:
        sys.exit(str(e))
