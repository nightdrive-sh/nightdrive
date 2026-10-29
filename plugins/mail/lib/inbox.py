#!/usr/bin/env python3
"""Archiving and deleting from the inbox without Mail's window: for the notifications' buttons, scripts and Claude's
tools (mcp.json).

    inbox.py archive ID…             the inbox's copies to Archive, as Mail's a does
    inbox.py unarchive ID…           back to the inbox (archive's undo: the ids it printed, whatever they hold)
    inbox.py delete [--check] ID…    the inbox's copies to Trash, as Mail's d does

An ID is a message's id, or a thread ("thread:0000000000000005"): then its messages in the inbox. Each must have
exactly that form and find one message or thread (ids.py), or nothing moves: an id is never a query. Only what is in the
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
import ids

HERE = os.path.dirname(os.path.abspath(__file__))
INBOX = "(tag inbox)"
ARCHIVED = '(folder (rx "Archive$"))'
SUBJECTS_MAX = 100   # characters of "subjects", the line of a notification


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def subject(query):
    """The subject of what an s-expression (ids.py) finds: a thread's, or a message's."""
    found = json.loads(notmuch("search", "--format=json", "--exclude=false", "--limit=1", "--query=sexp", query) or "[]")
    if not found:
        raise LookupError("No such message or thread")
    return found[0].get("subject", "")


def subjects_of(query):
    """The subjects a thread (or a message) goes by: the thread's, and each of its messages' ("Re: …")."""
    shown = json.loads(notmuch("show", "--format=json", "--body=false", "--exclude=false", "--query=sexp", query) or "[]")
    return {subject(query).strip()} | {m["headers"].get("Subject", "").strip() for m in browse.walk(shown, [])}


def check(idents, terms, shown):
    """Each ID's subject is one the user was shown for it."""
    if len(shown) != len(idents):
        raise LookupError(f"Nothing deleted: {len(idents)} ids but {len(shown)} subjects; give one subject for each.")
    for ident, query, said in zip(idents, terms, shown):
        if str(said).strip() not in subjects_of(query):
            raise LookupError(f"Nothing deleted: {ident}'s subject is {subject(query)!r}, not {said!r}.")


def move(to, query, source, tag):
    """The s-expression query's messages to the folder `to` from `source`; their ids and subjects."""
    found = [i.removeprefix("id:") for i in notmuch("search", "--output=messages", "--exclude=false", "--query=sexp",
                                                    query).split()]
    if not found:
        return [], []
    # Each message by its own id, quoted: a Message-ID with a quote in it stays one id
    exact = ids.messages(found)
    subjects = [subject(ids.message(i)) for i in found]
    out = subprocess.run([sys.executable, os.path.join(HERE, "move.py"), "--sexp", to, exact, source],
                         capture_output=True, text=True, check=True).stdout
    result = json.loads(out)
    if result.get("error"):
        raise RuntimeError(result["error"])
    notmuch("tag", "--query=sexp", tag, "--", exact)
    return found, subjects


def summary(subjects):
    text = ", ".join(dict.fromkeys(f"“{s}”" for s in subjects))   # a thread's messages share one subject
    return text if len(text) <= SUBJECTS_MAX else text[:SUBJECTS_MAX - 1] + "…"


def main():
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    idents = [a for a in args if a != "--check"]
    if cmd not in ("archive", "unarchive", "delete") or not idents or ("--check" in args and cmd != "delete"):
        sys.exit("usage: inbox.py archive ID… | unarchive ID… | delete [--check] ID…")
    # Before anything else: an id that isn't one stops it all. unarchive is archive's undo, given the ids archive
    # printed, as the database has them (ids.exact)
    terms = [ids.exact(i) if cmd == "unarchive" else ids.one(i) for i in idents]
    if "--check" in args:
        check(idents, terms, json.loads(sys.stdin.read() or "{}").get("subjects") or [])
    asked = f"(or {' '.join(terms)})"
    if cmd == "unarchive":
        moved = move("INBOX", f"(and {asked} (not {INBOX}) {ARCHIVED})", "Archive", "+inbox")
    else:
        moved = move("Archive" if cmd == "archive" else "Trash", f"(and {asked} {INBOX})", "INBOX", "-inbox")
    done, subjects = moved
    if not done:
        where = "in Archive" if cmd == "unarchive" else "in the inbox"
        raise LookupError(f"Nothing moved: none of {', '.join(idents)} is {where}")
    print(json.dumps({"moved": len(done), "ids": done, "subjects": summary(subjects)}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(f"{os.path.basename(e.cmd[0])} failed: {(e.stderr or '').strip() or e.returncode}")
    except (LookupError, RuntimeError, ValueError) as e:
        sys.exit(str(e))
