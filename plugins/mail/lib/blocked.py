#!/usr/bin/env python3
"""The mail Claude never gets: Settings › Claude › Access › Mail's list of senders, domains and tags (Dashboard
#1789). Claude's tools (mcp.json) run with NIGHTDRIVE_MCP=1 and the area's choices in NIGHTDRIVE_MCP_OPTIONS
({"blocked": ["maija@example.com", "bank.fi", "tag:health"]}); the terminal's commands don't, and give everything.

    an address    mail from it or to it (your replies quote it)
    a domain      the same for every address at it or under it (bank.fi, @bank.fi: also mail.bank.fi)
    tag:NAME      mail with that notmuch tag

The list becomes one notmuch query in its s-expression syntax, and what Claude asks is put in it as a subquery of its
own: `(and (infix "QUERY") (not BLOCKED))`. Glued as text, a query with a stray parenthesis or quote could open the
block up ("x) or (tag:bank"); as a subquery it can't reach outside itself.

    blocked.py notifications    Mail's notifications on stdin ([{summary, body, time}]): prints a list of true or
                                false, true for one of a blocked message (`nightdrive notifications` asks it for
                                Claude: the sender's name and subject would tell it what the block hides)
"""

import json
import os
import re
import subprocess
import sys
from datetime import datetime

from notify import name

# One entry, as access.py checks it (config/mcp/areas.py has the same pattern): nothing that could leave its string
ENTRY = re.compile(r'(?:tag:[^\s"()\\]{1,100}|(?:[^\s"()\\@<>]{0,64}@)?[^\s"()\\@<>.]{1,63}(?:\.[^\s"()\\@<>.]{1,63})+)')
SLACK = 3 * 86400   # seconds before a notification's time its message may be dated (notify.py announces 2 days back)


def entries():
    """The list, for Claude's calls only; [] in a terminal. One that isn't an entry fails: the block isn't guessed at."""
    if os.environ.get("NIGHTDRIVE_MCP") != "1":
        return []
    try:
        listed = json.loads(os.environ.get("NIGHTDRIVE_MCP_OPTIONS") or "{}").get("blocked") or []
    except (ValueError, AttributeError):
        raise ValueError("Access's list of blocked mail can't be read: nothing is shown")
    bad = [e for e in listed if not isinstance(e, str) or not ENTRY.fullmatch(e)]
    if bad:
        raise ValueError(f"Access's list of blocked mail has {bad[0]!r}, which isn't an address, a domain or "
                         "tag:NAME: nothing is shown")
    return listed


def string(text):
    """A string of the s-expression syntax."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def query(listed):
    """The s-expression that finds the blocked mail; None for an empty list."""
    terms = []
    for e in listed:
        if e.startswith("tag:"):
            terms.append(f"(tag {string(e[4:])})")
        else:
            # A phrase of the address: example.com matches anything@example.com and @mail.example.com too
            who = string(e.lstrip("@"))
            terms += [f"(from {who})", f"(to {who})"]
    return f"(or {' '.join(terms)})" if terms else None


def tags(listed):
    return {e[4:] for e in listed if e.startswith("tag:")}


def without(infix, blocked):
    """An infix query (Claude's, or a thread's) as an s-expression that leaves the blocked mail out."""
    return f"(and (infix {string(infix)}) (not {blocked}))"


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def among(ids, blocked):
    """Which of these message ids are blocked mail."""
    if not ids or not blocked:
        return set()
    found = notmuch("search", "--output=messages", "--exclude=false", "--query=sexp",
                    f"(and (or {' '.join(f'(id {string(i)})' for i in ids)}) {blocked})")
    return {line.removeprefix("id:") for line in found.split()}


def walk(nodes, out):
    for n in nodes:
        if isinstance(n, dict) and "headers" in n:
            out.append(n)
        elif isinstance(n, list):
            walk(n, out)
    return out


def notifications(rows, blocked):
    """For each of Mail's notifications, whether its message is blocked mail: notify.py shows the sender's name and the
    subject, so a blocked message with both the same is it. A name and subject a message that isn't
    blocked shares go too: better one notification too few than one of mail the user kept from Claude."""
    if not blocked or not rows:
        return [False] * len(rows)
    # Found by their subjects, a phrase each; one without words (none, "!!!") by the time instead, which an older
    # history's rows don't have: then all the blocked mail is read
    by_time = [r for r in rows if not re.search(r"\w", r.get("body", "")) or r.get("body") == "(no subject)"]
    terms = [f"(subject {string(b)})" for b in sorted({r.get("body", "") for r in rows if r not in by_time})]
    if by_time:
        since = max(0, min(int(r.get("time") or 0) for r in by_time) - SLACK)
        terms.append(f"(infix {string(f'date:@{since}..')})")
    out = notmuch("show", "--format=json", "--body=false", "--entire-thread=false", "--exclude=false",
                  "--query=sexp", f"(and {blocked} (or {' '.join(terms)}))")
    seen = {(name(m["headers"].get("From", "")), m["headers"].get("Subject", "") or "(no subject)")
            for m in walk(json.loads(out or "[]"), [])}
    return [(r.get("summary", ""), r.get("body", "")) in seen for r in rows]


def seconds(when):
    """A notification's time (ISO 8601, `nightdrive notifications list --json`) as seconds; 0 if it has none."""
    try:
        return int(datetime.fromisoformat(when).timestamp())
    except (TypeError, ValueError):
        return 0


def main():
    if sys.argv[1:] != ["notifications"]:
        sys.exit("usage: blocked.py notifications < JSON")
    rows = [{**r, "time": seconds(r.get("time"))} for r in json.loads(sys.stdin.read() or "[]")]
    print(json.dumps(notifications(rows, query(entries()))))


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.exit(f"notmuch failed: {(e.stderr or '').strip() or e.returncode}")
    except ValueError as e:
        sys.exit(str(e))
