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
An undo that does what an act tool does (dnd_off's undo turns Do Not Disturb on, which only the card may allow), or
whose tool says `"undo_asks": true`, runs only once the user allows it on the card, from the notification too (#1860).
An undo that refuses for now (the user is typing) leaves Try again on the row.

    python3 undo.py recent_changes | undo_change     Claude's tools (JSON on stdin, JSON out)
    python3 undo.py undo ID | redo ID                as the notification's buttons do
"""

import json
import re
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))

import access  # noqa: E402  (after the path above)
import changes  # noqa: E402
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
        "area": tool.area, "options_from": tool.spec.get("options_from", []),
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
    ToolError when it can't. An undo that asks waits for the card first, outside the lock: other undos and the log
    don't wait on the user, and the entry is checked again once they have answered."""
    argv, _ = runnable(entry_id, action)
    if action == "undo":
        ask(entry_id, argv)
    with changes.serial():
        argv, stdin = runnable(entry_id, action, shown=argv)
        entry = changes.get(entry_id)
        then = "undone" if action == "undo" else "done"
        where = SimpleNamespace(dir=Path(entry["dir"]), name=entry["tool"], **choices(entry))
        out, err, status = run.execute(where, argv, stdin, entry["timeout"])
        if status != 0:
            why = (err.strip() or out.strip() or "no message")[-run.MESSAGE_MAX:]
            raise ToolError(f"{action.capitalize()} of change {entry_id} ({entry['notice']}) failed "
                            f"({Path(argv[0]).name} exited with {status}): {why}")
        fields = {"undo": redone_undo(entry, out)} if action == "redo" and entry.get("remake") else {}
        changes.mark(entry_id, then, **fields)
        return {**entry, **fields}


def runnable(entry_id, action, shown=None):
    """(argv, stdin) an undo or redo of the entry runs; ToolError when the entry isn't in a state for it, or its argv
    isn't the one the card showed (shown)."""
    entry = changes.get(entry_id)
    if entry is None:
        raise ToolError(f"There's no change {entry_id} in the log (it keeps the last {changes.KEEP}).")
    want = "done" if action == "undo" else "undone"
    if entry["state"] != want:
        now = "undone already" if want == "done" else "in place"
        raise ToolError(f"Change {entry_id} ({entry['notice']}) is {now}.")
    argv, stdin = (entry["undo"], None) if action == "undo" else (entry["do"], entry.get("stdin"))
    if argv is None:
        raise ToolError(f"Change {entry_id} ({entry['notice']}) can't be undone: its redo didn't report what "
                        "undoing it needs.")
    if shown is not None and argv != shown:
        raise ToolError(f"Change {entry_id} ({entry['notice']}) changed while the card was on screen: nothing was "
                        "done.")
    return argv, stdin


def same_command(template, argv):
    """Whether argv is what a command template gives for some values: its words in order, a whole {name} one word or
    more (a list's), a {name} inside a word any text, a group there or not. --json only changes how a command prints,
    so it counts on neither side."""
    def fits(t, a):
        if not t:
            return not a
        head, rest = t[0], t[1:]
        if isinstance(head, list):
            return fits(head + rest, a) or fits(rest, a)
        if head == "--json":
            return fits(rest, a)
        if run.PLACEHOLDER.fullmatch(head):   # an empty list gives no word: a match too, so a card rather than none
            return any(fits(rest, a[n:]) for n in range(len(a) + 1))
        if not a:
            return False
        if run.PLACEHOLDER.search(head):
            parts = run.PLACEHOLDER.split(head)[::2]   # split puts the names at the odd places
            return bool(re.fullmatch(".*".join(map(re.escape, parts)), a[0], re.S)) and fits(rest, a[1:])
        return head == a[0] and fits(rest, a[1:])
    return fits(list(template), [w for w in argv if w != "--json"])


def acts_like(entry, argv):
    """What makes undoing the entry need the card: the act tool whose command the undo is (dnd_off's undo is
    dnd_on's), or True when its own tool says undo_asks or the tools can't be read (an undo that might act doesn't run
    unasked); None when nothing does."""
    try:
        import registry   # here, not at the top: registry imports this module as its seam
        tools, _ = registry.Registry().load()
    except Exception:
        return True
    own = tools.get(entry["tool"])
    if own is not None and own.spec.get("undo_asks") is True:
        return True
    return next((t for t in tools.values() if t.cls == "act" and same_command(t.spec["command"], argv)), None)


def ask(entry_id, argv):
    """The card for an undo that acts (acts_like): returns once the user allowed it, else ToolError."""
    entry = changes.get(entry_id)
    act = acts_like(entry, argv)
    if act is None:
        return
    import confirm   # only now: the card needs Quickshell, a plain undo doesn't
    does = " ".join(argv) if act is True else act.spec.get("title") or act.name
    area = entry.get("area") or "nightdrive"
    card = SimpleNamespace(name=OWN, cls="act", right="modify", area=area, options={},
                           spec={"title": f"Undo: {entry['notice']}", "class": "act", "area": area,
                                 "inputSchema": {"type": "object", "properties": {"does": {"title": "That is"}}}})
    if not confirm.ask(card, {"does": does}):
        raise ToolError(f"The user didn't allow undoing change {entry_id} ({entry['notice']}) on screen, so it "
                        "wasn't undone. Don't try it another way.")


def choices(entry):
    """The Access choices an undo or redo runs with, as the tool's own call would now (run.environment): a redo keeps
    to what applies now (the folders Claude can use, #1849), and a command that gets none refuses what they allow."""
    try:
        rules = access.load()
    except Exception:  # the command then has no choices, and allows least
        return {}
    area = entry.get("area")
    return {"options": rules.options(area) if area else {},
            "options_from": {a: rules.options(a) for a in entry.get("options_from", [])}}


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
        out = subprocess.run(cmd + ["--", summary, body], stdin=subprocess.DEVNULL, capture_output=True,
                             text=True).stdout
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
        while True:
            try:
                perform(entry_id, action)
                break
            except ToolError as e:
                # Try again: an undo that refused for now (the user was typing, #1860) can be run once they stop
                again = notify(entry_id, f"Couldn't {action}: {entry['notice']}", str(e),
                               button=(action, "Try again"))
                if again != action:
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
