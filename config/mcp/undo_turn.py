#!/usr/bin/env python3
"""The Undo on Ask Claude's small card (#3157, "say and forget" #3122): the changes one Ask Claude turn made, undone
together. The log marks each change with the conversation its server ran for (`ask`, from NIGHTDRIVE_ASK_ID, which
ask-claude.d/setup.sh puts in the server's env), and a turn's are those made since it started (its nightdrive_turn's
`at`): turns of one conversation run one after another, so a change after the start is this turn's. Claude Code shows
Claude a tool's structured result alone, so the "(Change N: …)" line undo.offer adds never reaches the events the card
reads, and the log is what knows.

It is the user's own button, as the notification's is (undo.perform without claude=True: an undo that asks still shows
its card, Access's Modify No for Claude doesn't apply). Changes already undone (from their notification, or by Claude's
own undo_change in the same turn) are left alone. The changes run newest first, as a batch's Undo does, so a value set
twice goes back to where it was before the first. Each batch they belong to then has its notification row shown again,
which now reads "Undid: …" with Redo, so the row doesn't offer an Undo that would find nothing.

    python3 undo_turn.py list CONVERSATION SINCE_MS   {"changes": [{id, notice, state}]}, oldest first
    python3 undo_turn.py undo CONVERSATION SINCE_MS   {"undone": [notices]}; exit 1 with the reason when one fails
                                                      (those before it stay undone, as with the row's Undo)
"""

import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import batch  # noqa: E402  (after the path above)
import changes  # noqa: E402
import undo  # noqa: E402
from run import ToolError  # noqa: E402

CONVERSATION = re.compile(r"^[0-9a-f-]{36}$")   # Claude Code's session id, as ask-claude's --resume takes it
SLACK = 1   # seconds: the log's times are whole seconds, the turn's start milliseconds


def made(conversation, since_ms):
    """The turn's entries, oldest first: of this conversation, made at or after its start."""
    since = since_ms / 1000 - SLACK
    out = []
    for e in changes.read():
        a = changes.age(e) if e.get("ask") == conversation else None
        if a is not None and time.time() - a >= since:
            out.append(e)
    return out


def listing(conversation, since_ms):
    return {"changes": [{k: e.get(k) for k in ("id", "notice", "state")} for e in made(conversation, since_ms)]}


def undo_turn(conversation, since_ms):
    """Undoes the turn's changes still in place, newest first; {"undone"}. ToolError stops it."""
    todo = [e for e in reversed(made(conversation, since_ms)) if e.get("state") == "done"]
    undone, leads = [], []
    try:
        for entry in todo:
            undo.perform(entry["id"], "undo")
            undone.append(entry["notice"])
            lead = entry.get("batch", entry["id"])
            if lead not in leads:
                leads.append(lead)
    finally:
        refresh(leads)
    return {"undone": undone}


def refresh(leads):
    """Each touched batch's row again, as its changes now stand (batch.row): Redo once all of it is undone."""
    for lead in leads:
        members = changes.batch(lead)
        if members:
            undo.show(lead, batch.row(members)[2])


def parse(argv):
    """(command, conversation, since_ms); ValueError when they aren't that."""
    if len(argv) != 3 or argv[0] not in ("list", "undo") or not CONVERSATION.match(argv[1]) or not argv[2].isdigit():
        raise ValueError
    return argv[0], argv[1], int(argv[2])


def main():
    try:
        cmd, conversation, since_ms = parse(sys.argv[1:])
    except ValueError:
        sys.exit("usage: undo_turn.py list|undo CONVERSATION SINCE_MS")
    try:
        out = listing(conversation, since_ms) if cmd == "list" else undo_turn(conversation, since_ms)
    except ToolError as e:
        sys.exit(str(e))
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()
