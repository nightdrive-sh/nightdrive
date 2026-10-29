#!/usr/bin/env python3
"""Moves the messages of a notmuch query to a sibling folder of the one they are in (the account's Trash, Archive …).

    move.py [--sexp] FOLDER QUERY [FROM …]     e.g. move.py Trash thread:0000000000000005 example/INBOX

QUERY is notmuch's infix syntax (Mail's window), or with --sexp its s-expression syntax (inbox.py, whose ids are
quoted strings there: ids.py).

FROM are the folders files may move from: "account/INBOX" (under ~/Mail), or "INBOX" for that folder in any account.
A message's files elsewhere stay: one mailed between two of your accounts is in both, and only the account being
looked at moves its copy. Without FROM, every file of the message moves.

Each file moves from <account>/<folder>/{cur,new}/ to <account>/FOLDER/cur/, without the ,U= (UID) part of its name
so the sync tool uploads it as a new message there and removes it from where it was. Files already in FOLDER stay, and
a message that has a file in FOLDER already only leaves the other folders (no second copy).

An account with `all-mail = yes` in account.conf (Gmail, whose Archive is All Mail) holds every message in Archive,
and a message deleted there is deleted for good. Its Archive files are never moved or removed: a message found only
there is copied to FOLDER instead, and archiving is leaving the inbox (Gmail keeps the message in All Mail).
Prints {"moved": N, "ids": [the query's message ids]} (for undo) or {"error": "..."}.
"""

import json
import os
import re
import shutil
import subprocess
import sys

import compose
import ids

ARCHIVE = "Archive"


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def all_mail_dirs():
    """The account folders whose Archive is All Mail."""
    try:
        return {a["maildir"] for a in compose.accounts().values() if a.get("all-mail", "no").lower() in ("yes", "true")}
    except SystemExit:
        return set()


def folder(path):
    return os.path.basename(os.path.dirname(os.path.dirname(path)))       # …/<account>/<folder>/cur/<file>


def account_dir(path):
    return os.path.dirname(os.path.dirname(os.path.dirname(path)))


def target(path, dest):
    """Where a file goes in the folder dest: cur/, with no UID, and flags if it came from new/."""
    d = os.path.join(account_dir(path), dest, "cur")
    os.makedirs(d, exist_ok=True)
    name = re.sub(r",U=\d+", "", os.path.basename(path))
    if ":2," not in name:
        name += ":2,S"
    return os.path.join(d, name)


def main():
    args = sys.argv[1:]
    syntax = ["--query=sexp"] if args[:1] == ["--sexp"] else []
    dest, query, sources = args[len(syntax)], args[len(syntax) + 1], args[len(syntax) + 2:]
    root = notmuch("config", "get", "database.path").strip()

    def source(f):
        where = os.path.relpath(os.path.dirname(os.path.dirname(f)), root)      # account/folder
        return not sources or any(s == where or "/" not in s and s == folder(f) for s in sources)

    found_ids = notmuch("search", "--output=messages", "--exclude=false", *syntax, "--", query).split()
    kept = all_mail_dirs()
    moved = 0
    for mid in found_ids:
        # Its own id, quoted: a Message-ID with a quote in it can't widen the search to other mail
        found = notmuch("search", "--output=files", "--exclude=false", "--query=sexp", ids.message(mid)).split("\n")
        files = [f for f in found if f and os.path.exists(f)]
        for acc in {account_dir(f) for f in files}:
            mine = [f for f in files if account_dir(f) == acc]
            src = [f for f in mine if source(f)]
            if not src:
                continue
            protected = [f for f in src if folder(f) == ARCHIVE and os.path.basename(acc) in kept]
            movable = [f for f in src if folder(f) != dest and f not in protected]
            if any(folder(f) == dest for f in mine):
                for f in movable:
                    os.remove(f)
                moved += len(movable)
            elif movable:
                for f in movable:
                    os.rename(f, target(f, dest))
                moved += len(movable)
            elif protected:
                shutil.copy2(protected[0], target(protected[0], dest))
                moved += 1
    if moved:
        notmuch("new", "--quiet", "--no-hooks")
    print(json.dumps({"moved": moved, "ids": [i.removeprefix("id:") for i in found_ids]}))


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, OSError) as e:
        print(json.dumps({"error": str(e)}))
