#!/usr/bin/env python3
"""Empty Spam (or Trash) without Mail's window: for scripts and Claude's tool mail_empty_spam (mcp.json).

    empty.py Spam|Trash [--account ID|ADDRESS] [--card]

Deletes every message in the folder for good, in each account or only in the one named (its id in account.conf, or its
address), as Mail's ⌘⇧⌫ does: erase.py removes the files, which touches nothing outside that folder, and the next sync
deletes them on the server. There is no undo. Prints {"erased": N, "threads": T, "accounts": {address: threads}}.

--card deletes nothing: it prints what Claude's confirmation card shows ({"Folder": …, "Deletes for good": …}) and fails when
there is nothing to delete, so an empty folder never shows a card. The call the user then allows gets the card's text
(NIGHTDRIVE_MCP_CARD) and deletes nothing if the folder holds other than it said: mail that came meanwhile wasn't
shown. Failures go to stderr with exit status 1.
"""

import json
import os
import subprocess
import sys

import compose

HERE = os.path.dirname(os.path.abspath(__file__))
FOLDERS = ("Spam", "Trash")


def where(acc, folder):
    """The folder of one account, as Mail's folderQuery (app/shell.qml) and sources() give it."""
    m = acc["maildir"]
    return (f'path:"{m}/{folder}/**"', f"{m}/{folder}") if m else (f"folder:/{folder}$/", folder)


def threads(query):
    out = subprocess.run(["notmuch", "count", "--output=threads", "--exclude=false", query],
                         capture_output=True, text=True, check=True).stdout
    return int(out.strip() or 0)


def chosen(name):
    accs = compose.accounts()
    if not name:
        return list(accs.values())
    found = [a for k, a in accs.items() if name in (k, a.get("address", ""))]
    if not found:
        raise LookupError(f"No account {name!r}: nightmail accounts lists them")
    return found


def plural(n):
    return f"{n} thread" if n == 1 else f"{n} threads"


def main():
    args = sys.argv[1:]
    folder = args[0] if args else ""
    if folder not in FOLDERS:
        sys.exit("usage: empty.py Spam|Trash [--account ID|ADDRESS] [--card]")
    name = args[args.index("--account") + 1] if "--account" in args[:-1] else ""
    counts = {}
    for acc in chosen(name):
        query, source = where(acc, folder)
        counts[acc.get("address") or source] = (query, source, threads(query))
    total = sum(n for _, _, n in counts.values())
    if not total:
        raise LookupError(f"{folder} is empty: nothing to delete")
    held = ", ".join(f"{a}: {plural(n)}" for a, (_, _, n) in counts.items() if n)
    if "--card" in args:
        print(json.dumps({"Folder": folder, "Deletes for good": held,
                          "Undo": "None: deleted here and, at the next sync, on the server"}, ensure_ascii=False))
        return
    said = json.loads(os.environ.get("NIGHTDRIVE_MCP_CARD") or "{}").get("Deletes for good")
    if said is not None and said != held:
        raise LookupError(f"Nothing deleted: {folder} changed since the card showed it ({held} now, not {said})")
    erased = 0
    for query, source, n in counts.values():
        if not n:
            continue
        out = subprocess.run([sys.executable, os.path.join(HERE, "erase.py"), "--folder", folder, query, source],
                             capture_output=True, text=True, check=True).stdout
        result = json.loads(out or "{}")
        if result.get("error"):
            raise RuntimeError(result["error"])
        erased += result.get("erased", 0)
    print(json.dumps({"erased": erased, "threads": total,
                      "accounts": {a: n for a, (_, _, n) in counts.items() if n}}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(f"{os.path.basename(e.cmd[0])} failed: {(e.stderr or '').strip() or e.returncode}")
    except (LookupError, RuntimeError, ValueError) as e:
        sys.exit(str(e))
