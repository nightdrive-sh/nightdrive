#!/usr/bin/env python3
"""Sorting by dragging: mail dropped into one of your own folders (folders.py) makes its sender's mail go there from
then on, and mail dragged out of it back to the inbox ends that. For Mail's drag, `m` and menu, and Claude's tools.

    sorting.py learn [--domain] ACCOUNT FOLDER ID…   a rule for each ID's sender (or with --domain their domain)
                                                     into FOLDER, then the sender's mail in the inbox, and the IDs'
                                                     own inbox messages, moved there
    sorting.py forget ACCOUNT ID…                    the rules that sort the IDs' senders, gone
    sorting.py undo [JSON]                           takes back a learn or forget: its output, or on stdin

An ID is a message's id or a thread (ids.py). Its sender is the From of its newest message that isn't from one of
your addresses. Prints {"senders": [...], "added": [rules], "removed": [rules], "moved": [message ids],
"account": ID, "folder": FOLDER}: the undo's input. Failures: {"error": "..."}, exit status 1.
"""

import json
import os
import subprocess
import sys

import browse
import compose
import ids
import isync
import rules

HERE = os.path.dirname(os.path.abspath(__file__))


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def yours():
    """Your addresses: every account's, and notmuch's primary_email and other_email."""
    found = {a["address"].lower() for a in compose.accounts().values() if a.get("address")}
    for key in ("user.primary_email", "user.other_email"):
        out = subprocess.run(["notmuch", "config", "get", key], capture_output=True, text=True).stdout
        found |= {x.strip().lower() for x in out.replace(";", "\n").split("\n") if x.strip()}
    return found


def sender(term, mine):
    """The address of the newest message in what term finds that isn't from you, or ""."""
    shown = json.loads(notmuch("show", "--format=json", "--body=false", "--entire-thread=false", "--exclude=false",
                               "--query=sexp", term) or "[]")
    msgs = sorted(browse.walk(shown, []), key=lambda m: m.get("timestamp", 0), reverse=True)
    for m in msgs:
        a = rules.address(m["headers"].get("From", ""))
        if a and a not in mine:
            return a
    return ""


def tag(changes, query):
    """One notmuch tag per change: with --query=sexp, notmuch 0.40 skips a message that has one of the tags being
    added already, so "-inbox +notified" left the inbox tag on mail that was notified before."""
    for change in changes:
        notmuch("tag", "--query=sexp", change, "--", query)


def inbox_of(m):
    return f'(and (tag inbox) (path "{m}/INBOX/**"))'


def from_addresses(query, test):
    """The ids of the messages query finds whose From passes test (notmuch's from: search is by words, so each is
    checked against its header)."""
    shown = json.loads(notmuch("show", "--format=json", "--body=false", "--entire-thread=false", "--exclude=false",
                               "--query=sexp", query) or "[]")
    return [m["id"] for m in browse.walk(shown, []) if test(rules.address(m["headers"].get("From", "")))]


def move(ids_, m, to, back=False):
    """Messages to the account's folder `to` (from INBOX, or from `to` back to INBOX), tagged as moved by hand."""
    if not ids_:
        return
    exact = ids.messages(ids_)
    src = f"{m}/{to}" if back else f"{m}/INBOX"
    out = subprocess.run([sys.executable, os.path.join(HERE, "move.py"), "--sexp", "--unread", "INBOX" if back else to, exact, src],
                         capture_output=True, text=True, check=True).stdout
    result = json.loads(out)
    if result.get("error"):
        raise RuntimeError(result["error"])
    tag(["+inbox" if back else "-inbox", "+notified"], exact)


def account_dir(account):
    acc = compose.accounts().get(account)
    if not acc or not acc.get("maildir"):
        raise ValueError(f"No account {account}")
    return acc["maildir"]


def learn(account, folder, idents, by_domain):
    m = account_dir(account)
    root = isync.mail_root()
    if not os.path.isdir(os.path.join(root, m, folder, "cur")):
        raise ValueError(f"No folder {folder} in {account}")
    terms = [ids.one(i) for i in idents]
    mine = yours()
    senders = list(dict.fromkeys(filter(None, (sender(t, mine) for t in terms))))
    if not senders:
        raise ValueError("No sender to sort by: these are your own messages")
    kind = "domain" if by_domain else "sender"
    values = list(dict.fromkeys(rules.domain(s) if by_domain else s for s in senders))
    added, removed = [], []
    for v in values:
        change = rules.add(account, folder, kind, v)
        added += change["added"]
        removed += change["removed"]
    # What is in the inbox now from them (and the IDs' own inbox messages) goes along
    current = rules.load()

    def covered(a):
        """Sorted into folder now, by one of the rules just made (a sender's own rule elsewhere wins: rules.match)"""
        if not a or rules.match(current, account, a) != folder:
            return False
        d = rules.domain(a)
        return any(d == v or d.endswith("." + v) for v in values) if by_domain else a in senders
    picked = from_addresses(f"(and {inbox_of(m)} (or {' '.join(terms)}))", lambda a: True)
    # notmuch's from: narrows it down first (by words: news@shop.fi, shop.fi in mail.shop.fi), covered() decides
    words = " ".join(f"(from {ids.string(v)})" for v in values)
    theirs = from_addresses(f"(and {inbox_of(m)} (or {words}))", covered)
    moved = list(dict.fromkeys(picked + theirs))
    move(moved, m, folder)
    return {"account": account, "folder": folder, "senders": senders, "added": added, "removed": removed,
            "moved": moved}


def forget(account, idents):
    account_dir(account)
    mine = yours()
    senders = list(dict.fromkeys(filter(None, (sender(ids.one(i), mine) for i in idents))))
    current = rules.load()
    gone = []
    for s in senders:
        gone += [r for r in rules.covering(current, account, s) if r not in gone]
    if gone:
        rules.save([r for r in current if r not in gone])
    return {"account": account, "folder": "", "senders": senders, "added": [], "removed": gone, "moved": []}


def undo(step):
    rules.restore(step.get("added") or [], step.get("removed") or [])
    if step.get("moved"):
        move(step["moved"], account_dir(step["account"]), step["folder"], back=True)
        notmuch("new", "--quiet", "--no-hooks")
    return {"undone": True}


def line(out):
    """What happened, in a sentence (the notification of Claude's tool)"""
    if not out["added"] and not out["removed"]:
        return "Nothing changed"
    if not out["added"]:
        return "Mail from " + ", ".join(r.get("sender") or "all of " + r["domain"] for r in out["removed"]) + " comes to the inbox again"
    who = ", ".join(r.get("sender") or "all of " + r["domain"] for r in out["added"])
    more = f" ({len(out['moved'])} from the inbox too)" if out["moved"] else ""
    return f"Mail from {who} goes to {out['folder']} from now on{more}"


def main():
    args = sys.argv[1:]
    by_domain = "--domain" in args
    args = [a for a in args if a != "--domain"]
    if args[:1] == ["learn"] and len(args) >= 4:
        out = learn(args[1], args[2], args[3:], by_domain)
    elif args[:1] == ["forget"] and len(args) >= 3:
        out = forget(args[1], args[2:])
    elif args[:1] == ["undo"]:
        out = undo(json.loads(args[1] if len(args) > 1 else sys.stdin.read() or "{}"))
    else:
        sys.exit(__doc__.split("\n\n")[1])
    if "added" in out:
        # The undo's whole input as one string, for Claude's tool (mcp.json mail_sort: its undo argv takes fields)
        out["step"] = json.dumps({k: out[k] for k in ("account", "folder", "added", "removed", "moved")}, ensure_ascii=False)
        out["line"] = line(out)
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        print(json.dumps({"error": f"{os.path.basename(e.cmd[0])} failed: {(e.stderr or '').strip() or e.returncode}"}))
        sys.exit(1)
    except (ValueError, LookupError, RuntimeError, OSError) as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
    except SystemExit as e:
        if not str(e).startswith("{"):
            raise
        print(e)
        sys.exit(1)
