#!/usr/bin/env python3
"""Undo for Claude's changes (MCP 6; plan: Dashboard #1761). A change tool runs at once; the user then gets a
notification "Changed the wallpaper" with Undo, and the call goes in the log (changes.py), so Claude can undo it too
when asked (recent_changes, undo_change: tools/changes.json).

registry.py calls, for a change tool:
    before(tool, arguments) -> dict          before it runs: the state its `before` command reports (the wallpaper
                                             that was set). If that can't be read, ToolError, and nothing is changed:
                                             a change Claude makes must be one the user can undo
    offer(tool, arguments, result, state)    after it ran: the log entry (with its `undo` argv, run.undo_argv) and
                                             the notification
The notification waits in a process of its own (`undo.py notice ID undo`), so its button still works once the server
has gone. Undo runs the logged argv as run.py runs a tool: without a shell, in the tool's folder, with its timeout.
The row then reads "Undid: …" with Redo, which runs the tool's command again and rebuilds its undo from that run's
output, as the first run's was (a new draft has a new id); Claude's undo_change shows the same row.

    python3 undo.py recent_changes | undo_change     Claude's tools (JSON on stdin, JSON out)
    python3 undo.py undo ID | redo ID                as the notification's buttons do
"""

import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))

import changes  # noqa: E402  (after the path above)
import run  # noqa: E402
from run import ToolError  # noqa: E402

HERE = Path(__file__).resolve().parent
OWN = "undo_change"   # tools/changes.json: its row replaces the change's instead of being a change of its own
NOTICE_FOR = 3600     # seconds the row (and its button) stays in the notification history; the log keeps it longer
NOTICE_MAX = 120      # characters of the notice: a long argument (a path, a text) is cut
ICON = "lucide:bot"   # as claude-notify's: the user's own agent icon when there is one
OWN_ICONS = [Path.home() / ".config/nightdrive" / f"agent-icon.{ext}" for ext in ("svg", "png")]


def before(tool, arguments):
    """The state a change tool's `before` command reports, as a dict for its undo's {name}s; {} without one."""
    template = tool.spec.get("before")
    if not template:
        return {}
    argv = run.expand(template, arguments)
    out, err, status = run.execute(tool, argv, None, run.timeout_of(tool))
    if status != 0:
        why = (err.strip() or out.strip() or f"exit status {status}")[-run.MESSAGE_MAX:]
        raise ToolError(f"{tool.name} wasn't run: what it would change couldn't be read first, so it couldn't be "
                        f"undone ({why}).")
    try:
        state = json.loads(out)
    except ValueError:
        state = None
    if not isinstance(state, dict):
        raise ToolError(f"{tool.name} wasn't run: its before command didn't print a JSON object.")
    return state


def notice_text(tool, values):
    """The notification's line: the tool's `notice` with its {name}s filled (what it is now: the output's fields, the
    arguments, then the state before), else its title."""
    fallback = tool.spec.get("title") or tool.name.replace("_", " ").capitalize()
    template = tool.spec.get("notice")
    if not isinstance(template, str) or not run.placeholders(template) <= set(values):
        return fallback
    text = run.PLACEHOLDER.sub(lambda m: run.text(values[m.group(1)]).replace(str(Path.home()), "~"), template)
    return text if len(text) <= NOTICE_MAX else text[:NOTICE_MAX - 1] + "…"


def offer(tool, arguments, answer, state=None):
    """After a change tool ran: the log entry and the notification. Claude's answer gets the entry's id, so it can
    name the change later; a change that couldn't be logged says so instead of failing (it has been made)."""
    if tool.name == OWN and tool.dir == HERE:
        entry_id = (answer.get("structuredContent") or {}).get("id")
        if isinstance(entry_id, int):
            show(entry_id, "redo")
        return
    try:
        argv, stdin = run.prepare(tool, arguments)
        undo = run.undo_argv(tool, arguments, answer, state)
    except ToolError as e:
        answer["content"].append({"type": "text", "text": f"(This change can't be undone: its undo {e})"})
        return
    now = {**(state or {}), **arguments, **(answer.get("structuredContent") or {})}
    entry = changes.add({
        "tool": tool.name, "notice": notice_text(tool, now),
        "arguments": arguments, "before": state or {}, "do": argv, "stdin": stdin, "undo": undo,
        "remake": tool.spec["undo"], "dir": str(tool.dir), "timeout": run.timeout_of(tool),
    })
    show(entry["id"], "undo")
    answer["content"].append({"type": "text", "text": f"(Change {entry['id']}: the user can undo it from the "
                                                      "notification, or you with undo_change.)"})


def show(entry_id, action):
    """The notification for an entry, in a process of its own that waits for its button."""
    subprocess.Popen([sys.executable, str(HERE / "undo.py"), "notice", str(entry_id), action],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def perform(entry_id, action):
    """Undo (or redo) an entry: its logged argv run as run.py runs a tool, and its state changed. Returns the entry;
    ToolError when it can't."""
    with changes.serial():
        entry = changes.get(entry_id)
        if entry is None:
            raise ToolError(f"There's no change {entry_id} in the log (it keeps the last {changes.KEEP}).")
        want, then = ("done", "undone") if action == "undo" else ("undone", "done")
        if entry["state"] != want:
            now = "undone already" if want == "done" else "in place"
            raise ToolError(f"Change {entry_id} ({entry['notice']}) is {now}.")
        argv, stdin = (entry["undo"], None) if action == "undo" else (entry["do"], entry.get("stdin"))
        if argv is None:
            raise ToolError(f"Change {entry_id} ({entry['notice']}) can't be undone: its redo didn't report what "
                            "undoing it needs.")
        where = SimpleNamespace(dir=Path(entry["dir"]), name=entry["tool"])
        out, err, status = run.execute(where, argv, stdin, entry["timeout"])
        if status != 0:
            why = (err.strip() or out.strip() or "no message")[-run.MESSAGE_MAX:]
            raise ToolError(f"{action.capitalize()} of change {entry_id} ({entry['notice']}) failed "
                            f"({Path(argv[0]).name} exited with {status}): {why}")
        fields = {"undo": redone_undo(entry, out)} if action == "redo" and entry.get("remake") else {}
        changes.mark(entry_id, then, **fields)
        return {**entry, **fields}


def redone_undo(entry, out):
    """A redo's undo, built from its own output as offer() builds the first one's: running the tool again may make
    something new (mail_draft: a new draft with a new Message-ID), and the first run's undo would miss it. None when
    the output lacks what the undo needs; undoing then says so rather than acting on the old one."""
    try:
        return run.expand(entry["remake"], run.undo_values(entry["arguments"], run.result(out), entry["before"]))
    except ToolError:
        return None


def icon():
    return str(next((f for f in OWN_ICONS if f.is_file()), ICON))


def notify(entry_id, summary, body="", button=None):
    """One row for the entry (a new one replaces the last, by its stack tag); the button's action when it's
    pressed, else None once the row has gone (dismissed, replaced, expired)."""
    cmd = ["notify-send", "-a", "Claude", "-i", icon(),
           "-h", f"string:x-dunst-stack-tag:claude-change-{entry_id}", "-h", f"int:x-nightdrive-expires:{NOTICE_FOR}"]
    if button:
        cmd += ["-A", f"{button[0]}={button[1]}", "-w"]
    try:
        out = subprocess.run(cmd + [summary, body], stdin=subprocess.DEVNULL, capture_output=True, text=True).stdout
    except OSError:
        return None  # no notify-send: the log still has it, for Claude
    return out.strip() or None


def notice(entry_id, action):
    """The helper process: the entry's row, and its button until the row goes. Undo turns it into "Undid: …" with
    Redo, and Redo back."""
    while True:
        entry = changes.get(entry_id)
        if entry is None:
            return
        if action == "undo":
            pressed = notify(entry_id, entry["notice"], button=("undo", "Undo"))
        else:
            pressed = notify(entry_id, f"Undid: {entry['notice']}", button=("redo", "Redo"))
        if pressed != action:
            return
        try:
            perform(entry_id, action)
        except ToolError as e:
            notify(entry_id, f"Couldn't {action}: {entry['notice']}", str(e))
            return
        action = "redo" if action == "undo" else "undo"


def recent_changes(args):
    """Claude's view of the log, newest first."""
    limit = args.get("limit", 10)
    rows = [{k: e.get(k) for k in ("id", "time", "notice", "tool", "arguments", "state", "at")}
            for e in reversed(changes.read())]
    return {"changes": rows[:limit], "total": len(rows)}


def undo_change(args):
    """Claude's undo: the change by id, else the newest one still in place."""
    entry_id = args.get("id")
    if entry_id is None:
        entry_id = next((e["id"] for e in reversed(changes.read()) if e["state"] == "done"), None)
        if entry_id is None:
            raise ToolError("There's no change of Claude's in place to undo.")
    entry = perform(entry_id, "undo")
    return {"id": entry_id, "undone": entry["notice"], "tool": entry["tool"]}


def main():
    cmd, rest = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    try:
        if cmd in ("recent_changes", "undo_change"):
            args = json.loads(sys.stdin.read() or "{}")
            print(json.dumps(globals()[cmd](args), ensure_ascii=False))
        elif cmd in ("undo", "redo") and len(rest) == 1 and rest[0].isdigit():
            entry = perform(int(rest[0]), cmd)
            done = "undone" if cmd == "undo" else "redone"
            print(json.dumps({"id": entry["id"], done: entry["notice"]}, ensure_ascii=False))
        elif cmd == "notice" and len(rest) == 2 and rest[0].isdigit() and rest[1] in ("undo", "redo"):
            notice(int(rest[0]), rest[1])
        else:
            sys.exit("usage: undo.py recent_changes | undo_change | undo ID | redo ID | notice ID undo|redo")
    except ToolError as e:
        sys.exit(str(e))


if __name__ == "__main__":
    main()
