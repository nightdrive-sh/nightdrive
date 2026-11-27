#!/usr/bin/env python3
"""Claude waits for mail (Dashboard #3735): a session asks to be woken when an awaited email arrives, a reply in a
thread or new mail matching a notmuch query, with an optional time-out ("wake me anyway in 2 hours").

    watch.py add QUERY [--to SESSION] [--timeout WHEN] -- PROMPT    or    add --stdin-json ({query, prompt, to, timeout})
    watch.py card [--to SESSION] [--timeout WHEN] -- QUERY           what mail_watch's card shows, as JSON
    watch.py list [--json]                                           the watches waiting
    watch.py show ID --json | cancel ID [--json] | restore ID [--json]
    watch.py check                                                   after each `notmuch new` (watch_check.py)

A watch is one-shot: the first new message that matches wakes its session (or a new one) with PROMPT and what came,
and the watch is gone. Nothing polls: `nightmail notify`, which notmuch's post-new hook runs after every fetch (IMAP
IDLE's within seconds, the 5-minute timer's), checks them first. The waking itself, and the time-out, are rows of
`nightdrive schedule` messages to Claude, so they behave as schedule_add's do: nothing runs behind the lock, a running
session gets it typed into its window, a closed one is resumed (schedule_claude.py), and `nightdrive schedule list`
shows the time-out waiting.

Without --to the session that asked is woken: Claude's tools run with CLAUDE_CODE_SESSION_ID. A name (Nightdrive
Project Manager) is kept as a name, as schedule keeps it: a new conversation of that name gets it.

What "new" means: notmuch has no arrival time, and lastmod changes with any tag. So a match is a message that matches
QUERY now, changed since the watch began (lastmod), dated at most SLACK before it began (a reply can't be older), and
wasn't among the matches when it began (the baseline: those dated in the same window). Mail you sent or a draft never
matches. Claude's query goes to notmuch as a subquery of an s-expression, with Access › Mail's blocked mail left out
(blocked.py), so a stray parenthesis can't reach past it.
"""

import argparse
import contextlib
import fcntl
import json
import os
import secrets
import shutil
import subprocess
import sys
import time
from pathlib import Path

import blocked
from ids import string

STATE = os.path.expanduser("~/.local/state/nightdrive/mail-watch.json")
SLACK = 86400            # seconds a matching message may be dated before its watch began (clocks, slow servers)
BASELINE_MAX = 2000      # message ids kept from when a watch began; more matched than that in a day is not a watch
KEEP_CANCELLED = 20      # for restore, the undo of a cancel
PROMPT_MAX = 3000        # what Claude asks to be told; schedule's message takes 4000 with the mail's lines
# This checkout's nightdrive (a worktree's own), else the one in PATH: the hook runs from the sync's service
NIGHTDRIVE = Path(__file__).resolve().parents[3] / "bin" / "nightdrive"


def nightdrive():
    return str(NIGHTDRIVE) if NIGHTDRIVE.exists() else shutil.which("nightdrive") or "nightdrive"


def notmuch(*args):
    p = subprocess.run(["notmuch", *args], capture_output=True, text=True)
    if p.returncode:
        raise ValueError((p.stderr or p.stdout).strip() or f"notmuch {args[0]} failed")
    return p.stdout


def schedule(*args, mcp=False):
    """`nightdrive schedule ARGS --json`'s row, or ValueError with its message. mcp: marked as by Claude in its list
    (a watch's rows are Claude's asking, allowed on mail_watch's card)."""
    env = dict(os.environ, NIGHTDRIVE_MCP="1") if mcp else os.environ
    p = subprocess.run([nightdrive(), "schedule", *args], capture_output=True, text=True, env=env)
    if p.returncode:
        raise ValueError((p.stderr or p.stdout).strip() or "nightdrive schedule failed")
    return json.loads(p.stdout) if p.stdout.strip().startswith("{") else {}


@contextlib.contextmanager
def store():
    """The state file, locked while it is read and written: the hook and Claude's calls may come at once."""
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(STATE, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = {}
        data.setdefault("watches", [])
        data.setdefault("cancelled", [])
        yield data
        tmp = STATE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
        os.replace(tmp, STATE)


def full_query(query, block=None):
    """Claude's QUERY as the s-expression a watch keeps: a subquery of its own, the blocked mail left out."""
    listed = blocked.entries() if block is None else block
    b = blocked.query(listed)
    return blocked.without(query, b) if b else f"(infix {string(query)})"


def fresh(sexp, rev, since):
    """sexp narrowed to what can be new: changed since revision rev, dated since since, not yours, not a draft."""
    return f"(and {sexp} (not (tag sent)) (not (tag draft)) (infix {string(f'lastmod:{rev}.. date:@{since}..')}))"


def revision():
    """The database's revision now: `notmuch count --lastmod` prints count, uuid and revision."""
    return int(notmuch("count", "--lastmod", "*").split()[-1])


def matches(sexp):
    return notmuch("search", "--output=messages", "--query=sexp", sexp).split()


def caller():
    return os.environ.get("CLAUDE_CODE_SESSION_ID", "").strip()


def target(to):
    """The session a watch wakes, as schedule keeps it (an id, or one name), checked by a dry run of a schedule row;
    None for a new session."""
    to = (to or "").strip() or caller()
    if not to:
        return None
    row = schedule(f"@{int(time.time()) + 3600}", "--to", to, "--dry-run", "--json", "--", "check")
    return row.get("to") or to


def deadline(when):
    """A time-out (90m, 2h, 14:45, as schedule takes a time) → Unix time; ValueError for an event or a bad one."""
    row = schedule(when, "--claude", "--dry-run", "--json", "--", "check")
    if not row.get("at_unix"):
        raise ValueError("A time-out is a time: minutes (90m, 2h) or a time of day (14:45), within a week")
    return int(row["at_unix"])


def clock(at):
    return time.strftime("%H:%M" if at - time.time() < 86400 else "%a %d.%m. %H:%M", time.localtime(at))


def timeout_text(w):
    return (f"Mail watch {w['id']}: no new mail matching `{w['query']}` came by {clock(w['deadline'])}, the time-out "
            f"set when it began. It is over now. What you asked then:\n\n{w['prompt']}")


def add(query, prompt, to=None, timeout=None):
    query, prompt = (query or "").strip(), (prompt or "").strip()
    if not query or not prompt:
        raise ValueError("A watch needs a query and a prompt: what to watch for, and what the woken session does")
    if len(prompt) > PROMPT_MAX:
        raise ValueError(f"The prompt is at most {PROMPT_MAX} characters")
    sexp = full_query(query)
    now = int(time.time())
    w = {"id": secrets.token_hex(4), "query": query, "sexp": sexp, "prompt": prompt, "to": target(to),
         "created": now, "rev": revision() + 1, "since": now - SLACK, "deadline": None, "timeout_row": None}
    # Checks the query too: notmuch refuses one it can't read
    dated = string(f"date:@{w['since']}..")
    w["baseline"] = matches(f"(and {sexp} (infix {dated}))")[:BASELINE_MAX]
    if timeout:
        w["deadline"] = deadline(timeout)
        to_args = ["--to", w["to"]] if w["to"] else ["--claude"]
        row = schedule(f"@{w['deadline']}", *to_args, "--json", "--", timeout_text(w), mcp=True)
        w["timeout_row"] = row.get("id")
    with store() as data:
        data["watches"].append(w)
    return public(w)


def public(w):
    return {"id": w["id"], "query": w["query"], "prompt": w["prompt"], "to": w["to"],
            "created": iso(w["created"]), "timeout": iso(w["deadline"]) if w.get("deadline") else None,
            "timeout_row": w.get("timeout_row")}


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(t))


def live(watches, now=None):
    """The watches still waiting: one past its time-out was woken by its schedule row and is over."""
    now = now or time.time()
    return [w for w in watches if not w.get("deadline") or w["deadline"] > now]


def find(rows, wid):
    w = next((w for w in rows if w["id"] == wid), None)
    if not w:
        raise ValueError(f"No mail watch {wid} (nightmail watch list)")
    return w


def cancel(wid):
    with store() as data:
        w = find(data["watches"], wid)
        data["watches"].remove(w)
        data["cancelled"] = (data["cancelled"] + [w])[-KEEP_CANCELLED:]
    if w.get("timeout_row"):
        with contextlib.suppress(ValueError, OSError):
            schedule("cancel", w["timeout_row"])
    return public(w)


def restore(wid):
    """A cancelled watch back (mail_watch_cancel's undo), its time-out again; mail that came meanwhile wakes it."""
    with store() as data:
        w = find(data["cancelled"], wid)
        if w.get("deadline") and w["deadline"] <= time.time():
            raise ValueError(f"Mail watch {wid}'s time-out has passed: it can't come back")
        if w.get("timeout_row"):
            to_args = ["--to", w["to"]] if w["to"] else ["--claude"]
            w["timeout_row"] = schedule(f"@{w['deadline']}", *to_args, "--json", "--", timeout_text(w),
                                        mcp=True).get("id")
        data["cancelled"].remove(w)
        data["watches"].append(w)
    return public(w)


def session_name(key):
    """An id's session by its name on the card, as `nightdrive sessions` has it; a name, or one not found, as it is."""
    try:
        p = subprocess.run([nightdrive(), "sessions", "--json"], capture_output=True, text=True, timeout=30)
        found = json.loads(p.stdout or "[]")
    except (OSError, subprocess.SubprocessError, ValueError):
        return key
    return next((s.get("name") or key for s in found if s.get("id") == key), key)


def card(query, to=None, timeout=None):
    """mail_watch's card: whom it wakes, and what matches now (which won't wake it), said before the user allows it."""
    sexp = full_query(query)
    now_matching = int(notmuch("count", "--query=sexp", sexp).strip() or 0)
    who = target(to)
    rows = {"Wakes": f"{session_name(who)}" + (" (this session)" if who == caller() else "") if who
            else "A new Claude session",
            "Matching now": f"{now_matching} message{'' if now_matching == 1 else 's'}, which don't wake it"
            if now_matching else "Nothing yet"}
    rows["Time-out"] = f"At {clock(deadline(timeout))}, if no mail came" if timeout else "None: it waits for the mail"
    return rows


def main(argv):
    p = argparse.ArgumentParser(prog="nightmail watch", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add")
    a.add_argument("query", nargs="?")
    a.add_argument("prompt", nargs="*")
    a.add_argument("--to")
    a.add_argument("--timeout")
    a.add_argument("--stdin-json", action="store_true")
    a.add_argument("--json", action="store_true")
    c = sub.add_parser("card")
    c.add_argument("query")
    c.add_argument("--to")
    c.add_argument("--timeout")
    sub.add_parser("list").add_argument("--json", action="store_true")
    for name in ("show", "cancel", "restore"):
        s = sub.add_parser(name)
        s.add_argument("id")
        s.add_argument("--json", action="store_true")
    sub.add_parser("check")
    args = p.parse_args(argv)
    if args.cmd == "check":
        import watch_check   # the hook's half: only it needs the waking
        return watch_check.check()
    try:
        if args.cmd == "add":
            if args.stdin_json:
                given = json.load(sys.stdin)
                out = add(given.get("query"), given.get("prompt"), given.get("to"), given.get("timeout"))
            else:
                out = add(args.query, " ".join(args.prompt), args.to, args.timeout)
        elif args.cmd == "card":
            out = card(args.query, args.to, args.timeout)
        elif args.cmd == "list":
            with store() as data:
                data["watches"] = live(data["watches"])
                out = {"watches": [public(w) for w in data["watches"]]}
        elif args.cmd == "show":
            with store() as data:
                out = public(find(live(data["watches"]), args.id))
        else:
            out = cancel(args.id) if args.cmd == "cancel" else restore(args.id)
    except ValueError as e:
        print(f"nightmail watch: {e}", file=sys.stderr)
        return 1
    if getattr(args, "json", False) or args.cmd == "card":
        print(json.dumps(out, ensure_ascii=False))
    elif args.cmd == "list":
        for w in out["watches"]:
            print(f"{w['id']}  {w['query']}  → {w['to'] or 'a new session'}"
                  + (f"  (time-out {w['timeout'][11:16]})" if w["timeout"] else ""))
        if not out["watches"]:
            print("No mail watches")
    else:
        print(f"{args.cmd.capitalize() if args.cmd != 'add' else 'Watching'}: {out['id']}  {out['query']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
