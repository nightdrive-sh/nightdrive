"""Claude's changes in a row as one notification (#3223). Seven tasks_add calls used to give seven rows with an Undo
each; now the changes one conversation makes in one area close together share a row, "Added 7 tasks", which updates
as they come and whose Undo undoes them all. The log keeps every change apart (changes.py), so recent_changes and
undo_change see and undo each one as before.

Which changes go together is changes.py's (changes.batch_for, under the log's lock): an entry's `batch` is the id of
its batch's first entry, the row's id. This module is the row: its text, and what its buttons run.
"""

import changes
from run import ToolError

LISTED = 4   # notices the row's body lists, newest last; the rest are "and N more"


def summary(members):
    """The row's line for these changes: one is its own notice; more of one tool say it with the tool's
    `notice_many` ("Added {count} tasks"), else how many changes in which area ("3 changes in Tasks"). The area's
    name, not the tools': a batch may mix them (a task added, another marked done)."""
    if len(members) == 1:
        return members[0]["notice"]
    count = str(len(members))
    many = members[-1].get("many")
    if isinstance(many, str) and "{count}" in many and len({m.get("tool") for m in members}) == 1:
        return many.replace("{count}", count)
    import areas   # only now: a single change needs no names
    return f"{count} changes in {areas.name(members[-1].get('area') or 'nightdrive')}"


def listing(members):
    """The row's body for a batch: what each change was, the last few, so the user sees what Undo takes back."""
    if len(members) < 2:
        return ""
    lines = [m["notice"] for m in members[-LISTED:]]
    if len(members) > LISTED:
        lines.insert(0, f"…and {len(members) - LISTED} more")
    return "\n".join(lines)


def row(members):
    """(summary, body, action) of the batch's row as its changes stand: Undo for those still in place, else
    "Undid: …" with Redo. One Claude undid by itself (undo_change) leaves the rest's Undo, and says so."""
    done = [m for m in members if m["state"] == "done"]
    if not done:
        return f"Undid: {summary(members)}", listing(members), "redo"
    body = listing(done)
    if len(done) < len(members):
        body = "\n".join(filter(None, [body, f"({len(members) - len(done)} undone already)"]))
    return summary(done), body, "undo"


def targets(members, action):
    """The entries a button runs on, in the order that puts things back: an undo newest first (the volume set
    three times goes back to where it was before the first), a redo oldest first."""
    if action == "undo":
        return [m for m in reversed(members) if m["state"] == "done"]
    return [m for m in members if m["state"] == "undone"]


def perform(lead, action, one):
    """Undo or redo the batch: one(entry_id, action) on each target (undo.perform, with its cards and checks).
    The first that fails stops it with its ToolError; those before it stay undone, and Try again runs the rest."""
    todo = targets(changes.batch(lead), action)
    if not todo:
        raise ToolError(f"Change {lead}: nothing left to {action}.")
    for entry in todo:
        one(entry["id"], action)


def ids(members):
    """The batch's change ids as the retired row names them: "change 5", "changes 5–11"."""
    first, last = members[0]["id"], members[-1]["id"]
    return f"change {first}" if first == last else f"changes {first}–{last}"
