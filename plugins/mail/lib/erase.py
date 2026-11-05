#!/usr/bin/env python3
"""Deletes the messages of a notmuch query for good: their files in a Trash (or Spam) folder are removed.

    erase.py [--folder Spam] QUERY [FROM …]     e.g. erase.py 'path:"example/Trash/**"' example/Trash

Only files in a folder named Trash (with --folder Spam, Spam) are touched, whatever the query matches, so a wrong query
can't reach the inbox; with FROM ("account/Trash"), only those in it, so another account's copy of the same message
stays.
The sync tool (mbsync's Expunge Both) then deletes them on the server too. There is no undo.
Prints {"erased": N} or {"error": "..."}.
"""

import json
import os
import subprocess
import sys

FOLDERS = ("Trash", "Spam")   # the only folders whose mail may go for good: Empty Trash, Empty Spam


def main():
    args = sys.argv[1:]
    folder = "Trash"
    if args[:1] == ["--folder"]:
        folder, args = args[1], args[2:]
    if folder not in FOLDERS or not args:
        raise ValueError("Usage: erase.py [--folder Trash|Spam] QUERY [FROM …]")
    query, sources = args[0], args[1:]
    root = subprocess.run(["notmuch", "config", "get", "database.path"], capture_output=True, text=True).stdout.strip()
    files = subprocess.run(["notmuch", "search", "--output=files", "--exclude=false", query],
                           capture_output=True, text=True, check=True).stdout.split("\n")
    erased = 0
    for path in filter(None, files):
        # …/<account>/Trash/{cur,new}/<file>
        where = os.path.dirname(os.path.dirname(path))
        if os.path.basename(where) != folder or not os.path.exists(path):
            continue
        if sources and os.path.relpath(where, root) not in sources:
            continue
        os.remove(path)
        erased += 1
    if erased:
        subprocess.run(["notmuch", "new", "--quiet", "--no-hooks"], check=True)
    print(json.dumps({"erased": erased}))


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, OSError, ValueError) as e:
        print(json.dumps({"error": str(e)}))
