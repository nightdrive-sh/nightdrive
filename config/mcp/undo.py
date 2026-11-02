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
The notification waits in a helper of its own (notices.py: one for all the rows, #1882), so its button still works once
the server has gone. Undo runs the logged argv as run.py runs a tool: without a shell, in the tool's folder, with its timeout.
The row then reads "Undid: …" with Redo, which runs the tool's command again and rebuilds its undo from that run's
output, as the first run's was (a new draft has a new id); Claude's undo_change shows the same row.
An undo that does what an act tool does (dnd_off's undo turns Do Not Disturb on, which only the card may allow), or
whose tool says `"undo_asks": true`, runs only once the user allows it on the card, from the notification too (#1860).
Claude's undo_change keeps to Access as the tool's own call would now (#1924): the area's Modify No refuses it, Ask
shows the card, whatever it was when the change was made. A redo is the tool's call again, so one its `asks_if` says
reaches further (a speaker on the network, a shared calendar) asks on the tool's own card, from the notification too.
So does Claude's undo that is the tool's own command with other values (sound_output back to an AirPlay speaker,
a light back to its brightness): its asks_if gets the values read off the undo's argv (#1945). One whose tool has an
asks_if but whose undo isn't its command shows the undo's card, as asks_if can't speak for it.
An undo that refuses for now (the user is typing) leaves Try again on the row.
The log is a file of the user's, which what they run can write (Claude Code's own Write too), so an undo or redo runs
only what the tool the entry names, as installed now, would: its undo template word for word, its command with the
logged arguments, in its own folder (#1881). undo_change without an id undoes only this server's own newest change.

    python3 undo.py recent_changes | undo_change     Claude's tools (JSON on stdin, JSON out)
    python3 undo.py undo ID | redo ID                as the notification's buttons do
"""

import json
import os
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
NOTICE_FOR = changes.HOLD  # seconds the row (and its button) stays in the notification history; the log keeps it longer
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


def words(value):
    """A value as the notice says it: a list of texts (a draft's recipients, mails' subjects) one after another."""
    if isinstance(value, list) and all(isinstance(v, str) for v in value):
        return ", ".join(value)
    return run.text(value)


def notice_text(tool, values):
    """The notification's line: the tool's `notice` with its {name}s filled (what it is now: the output's fields, the
    arguments, then the state before), else its title."""
    fallback = tool.spec.get("title") or tool.name.replace("_", " ").capitalize()
    template = tool.spec.get("notice")
    if not isinstance(template, str) or not run.placeholders(template) <= set(values):
        return fallback
    text = run.PLACEHOLDER.sub(lambda m: words(values[m.group(1)]).replace(str(Path.home()), "~"), template)
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
        "deletes": bool(tool.spec.get("deletes")), "server": server_id(os.getpid()),
    })
    show(entry["id"], "undo")
    answer["content"].append({"type": "text", "text": f"(Change {entry['id']}: the user can undo it from the "
                                                      "notification, or you with undo_change.)"})


def show(entry_id, action):
    """The notification for an entry, from the helper that waits for the buttons (notices.py)."""
    import notices   # only now: a call that changes nothing needs no helper
    notices.show(entry_id, action)


def server_id(pid):
    """A process as one run of it: its pid and when it started (/proc's starttime), as a pid is used again; None when
    it can't be read."""
    try:
        return f"{pid}:{Path(f'/proc/{pid}/stat').read_text().rpartition(')')[2].split()[19]}"
    except (OSError, IndexError):
        return None


def perform(entry_id, action, claude=False):
    """Undo (or redo) an entry: its logged argv run as run.py runs a tool, and its state changed. Returns the entry;
    ToolError when it can't. claude: Claude asked for it (undo_change), so Access applies as to the tool's own call;
    the notification's buttons are the user's. One that asks waits for the card first, outside the lock: other undos
    and the log don't wait on the user, and the entry is checked again once they have answered."""
    argv, stdin, tool = runnable(entry_id, action)
    said = ask(entry_id, action, argv, tool, claude)
    with changes.serial():
        argv, stdin, tool = runnable(entry_id, action, shown=(argv, stdin))
        entry = changes.get(entry_id)
        then = "undone" if action == "undo" else "done"
        # The tool's own folder, timeout and Access choices: none of them from the log. What its card said, for a
        # command that checks it acts on that (#1866)
        where = SimpleNamespace(dir=tool.dir, name=tool.name, said=said, **choices(tool))
        out, err, status = run.execute(where, argv, stdin, run.timeout_of(tool))
        if status != 0:
            why = (err.strip() or out.strip() or "no message")[-run.MESSAGE_MAX:]
            raise ToolError(f"{action.capitalize()} of change {entry_id} ({entry['notice']}) failed "
                            f"({Path(argv[0]).name} exited with {status}): {why}")
        fields = {"undo": redone_undo(tool, entry, out)} if action == "redo" else {}
        changes.mark(entry_id, then, **fields)
        return {**entry, **fields}


def runnable(entry_id, action, shown=None):
    """(argv, stdin, tool) an undo or redo of the entry runs; ToolError when the entry isn't in a state for it, its
    argv isn't one its tool would run (registered), or isn't the one the card showed (shown: argv, stdin)."""
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
    tool = registered(entry, action, argv, stdin)
    if shown is not None and (argv, stdin) != shown:
        raise ToolError(f"Change {entry_id} ({entry['notice']}) changed while the card was on screen: nothing was "
                        "done.")
    return argv, stdin, tool


def registered(entry, action, argv, stdin):
    """The tool the entry names, as installed now, once the logged command is one it would run (#1881): an undo must
    fit its `undo` template word for word (same_command, strict), a redo be its command with the logged arguments,
    which its schema still takes. ToolError otherwise: what wrote the log can't have Undo run something else."""
    what = f"Change {entry['id']} ({entry.get('notice')})"
    try:
        import registry   # here, not at the top: registry imports this module as its seam
        tools, _ = registry.Registry().load()
    except Exception as e:
        raise ToolError(f"{what} wasn't {action}ne: its tool couldn't be read ({e}).")
    tool = tools.get(entry.get("tool"))
    if tool is None or tool.cls != "change" or tool.name == OWN or not is_template(tool.spec.get("undo")):
        raise ToolError(f"{what} can't be {action}ne now: {entry.get('tool')!r} isn't a change tool that is "
                        "installed and on.")
    if action == "undo":
        fits = same_command(tool.spec["undo"], argv, strict=True)
    else:
        try:
            run.check(tool, entry.get("arguments") if isinstance(entry.get("arguments"), dict) else {})
            fits = (argv, stdin) == run.prepare(tool, entry["arguments"])
        except (ToolError, KeyError, TypeError):
            fits = False
    if not fits:
        raise ToolError(f"{what} wasn't {action}ne: the log's command for it isn't one {tool.name} would run (the "
                        "log was changed, or the tool since). Nothing was done.")
    return tool


def is_template(value):
    return isinstance(value, list) and bool(value)


# Words that change only how a command prints, or that it checks first what the card showed (calendar_delete's
# --check): an undo without them still does what the act tool does, so it asks on the card too (#1881)
QUIET = {"--json", "--check", "--card"}


def same_command(template, argv, strict=False):
    """Whether argv is what a command template gives for some values: its words in order, a whole {name} one word or
    more (a list's), a {name} inside a word any text, a group there or not. QUIET's words count on neither side.
    strict, for a logged undo checked against its own template (registered): every word counts, a whole {name} gives
    at least one (but the last, an empty list's), and none of them starts with - unless a -- came before it, so a
    value can't be an option the command didn't have, nor a missing one shift the next into its place."""
    def fits(t, a, ended=False):
        if not t:
            return not a
        head, rest = t[0], t[1:]
        if isinstance(head, list):
            return fits(head + rest, a, ended) or fits(rest, a, ended)
        if head in QUIET and not strict:
            return fits(rest, a, ended)
        if run.PLACEHOLDER.fullmatch(head):   # an empty list gives no word: a match too, so a card rather than none
            return any(fits(rest, a[n:], ended) for n in range(1 if strict and rest else 0, len(a) + 1)
                       if not strict or ended or not any(w.startswith("-") for w in a[:n]))
        if not a:
            return False
        if run.PLACEHOLDER.search(head):
            parts = run.PLACEHOLDER.split(head)[::2]   # split puts the names at the odd places
            return bool(re.fullmatch(".*".join(map(re.escape, parts)), a[0], re.S)) and fits(rest, a[1:], ended)
        return head == a[0] and fits(rest, a[1:], ended or head == "--")
    return fits(list(template), list(argv) if strict else [w for w in argv if w not in QUIET])


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


def ask(entry_id, action, argv, tool, claude=False):
    """The card an undo or redo needs, if any (claude: undo_change's): returns once the user allowed it, with what a
    tool's own card command said (confirm.facts), else ToolError. Nothing is run before this has returned."""
    entry = changes.get(entry_id)
    decision = allowed(entry_id, action, tool) if claude else "allow"
    if action == "redo":
        return ask_call(entry, tool, entry.get("arguments") or {}, decision, "redoing")
    act = acts_like(entry, argv)
    if act is None and decision == "allow":
        # Claude's undo reaches as far as the call it is: one that is the tool's command asks when its asks_if says
        # so (#1945). The notification's Undo is the user's own, and puts back what they had
        if not (claude and tool.spec.get("asks_if")):
            return None
        call = as_call(tool.spec["command"], argv)
        if call is not None:
            return ask_call(entry, tool, call, "allow", "undoing")
    import confirm   # only now: the card needs Quickshell, a plain undo doesn't
    does = (act.spec.get("title") or act.name) if act not in (None, True) else " ".join(argv)
    area = tool.area or "nightdrive"
    # An undo that acts says so as an act's card does; one Access asks about is a change, which Redo puts back
    cls = "act" if act is not None else "change"
    card = SimpleNamespace(name=OWN, cls=cls, right="modify", area=area, options={},
                           spec={"title": f"Undo: {entry['notice']}", "class": cls, "area": area,
                                 "inputSchema": {"type": "object", "properties": {"does": {"title": "That is"}}}})
    if not confirm.ask(card, {"does": does}):
        raise ToolError(f"The user didn't allow undoing change {entry_id} ({entry['notice']}) on screen, so it "
                        "wasn't undone. Don't try it another way.")
    return None


def allowed(entry_id, action, tool):
    """allow or ask: what Access says now to Claude undoing or redoing a change of this tool, as to the tool's own call.
    An undo changes its area (Modify, even a deletion's: putting back deletes nothing); a redo is the call again, by
    the tool's own right. No, or an Access that can't be read, refuses: undo_change mustn't reach where the tool
    can't."""
    right = "modify" if action == "undo" else tool.right
    try:
        decision = access.load().decide(tool.cls, tool.area, right)
    except Exception:
        decision = "no"
    if decision not in ("allow", "ask"):
        # Its id and area alone: what it was is the area's, which recent_changes may not show now (#1884)
        raise ToolError(f"Change {entry_id} wasn't {action}ne: the user's Access doesn't let you change "
                        f"{access.areas.name(tool.area)} now ({right.capitalize()}: No). Tell the user; don't try "
                        "it another way.")
    return decision


def ask_call(entry, tool, arguments, decision, doing):
    """A redo is the tool's call again, with the logged arguments, and so is Claude's undo that is its command (with
    the values as_call read off it): the tool's own card when Access asks (decision) or its asks_if says this call
    reaches further than its right (#1887), as the call itself would ask. doing: "redoing" or "undoing"."""
    import registry   # here, not at the top: registry imports this module as its seam
    tool.said = None
    tool.options, tool.options_from = {}, {}
    for name, value in choices(tool).items():
        setattr(tool, name, value)   # the card command and asks_if keep to the area's choices, as the call's did
    ask, first = decision != "allow", None
    if decision == "allow" and tool.spec.get("asks_if"):
        ask, first = registry.asks(tool, arguments)
    if not ask:
        return None
    import confirm
    with registry.first_time(tool, first):   # a calendar Claude hasn't added to yet: allowing it remembers (#1929)
        ok = confirm.ask(tool, arguments)
    if not ok:
        done = "redone" if doing == "redoing" else "undone"
        raise ToolError(f"The user didn't allow {doing} change {entry['id']} ({entry['notice']}) on screen, so it "
                        f"wasn't {done}. Don't try it another way.")
    registry.allowed_once(tool, first)
    return tool.said


def as_call(template, argv):
    """The arguments that make a command template give argv word for word (run.expand), or None when none do: an
    undo that is its tool's own command with other values is that tool's call (#1945). A whole {name} is one word, a
    {name} inside a word any text, a group there or not; what fits is checked by expanding it again, so a reading
    that only looks right (a group's switch taken for a value) is no call."""
    def bind(t, a, got):
        if not t:
            try:
                return got if not a and run.expand(template, got) == list(argv) else None
            except ToolError:
                return None
        head, rest = t[0], t[1:]
        if isinstance(head, list):
            taken = bind(head + rest, a, got)
            return taken if taken is not None else bind(rest, a, got)
        if not a:
            return None
        names = run.PLACEHOLDER.findall(head)
        if not names:
            return bind(rest, a[1:], got) if head == a[0] else None
        parts = run.PLACEHOLDER.split(head)[::2]   # split puts the names at the odd places
        found = re.fullmatch("(.*)".join(map(re.escape, parts)), a[0], re.S)
        if found is None:
            return None
        values = dict(zip(names, found.groups()))
        if any(got.get(n, v) != v for n, v in values.items()):   # a name used twice reads the same both times
            return None
        return bind(rest, a[1:], {**got, **values})
    return bind(list(template), list(argv), {})


def choices(tool):
    """The Access choices an undo or redo runs with, as the tool's own call would now (run.environment): a redo keeps
    to what applies now (the folders Claude can use, #1849), and a command that gets none refuses what they allow."""
    try:
        rules = access.load()
    except Exception:  # the command then has no choices, and allows least
        return {}
    return {"options": rules.options(tool.area),
            "options_from": {a: rules.options(a) for a in tool.spec.get("options_from", [])}}


def redone_undo(tool, entry, out):
    """A redo's undo, built from its own output as offer() builds the first one's, by the tool's own template (not
    the log's remake): running the tool again may make something new (mail_draft: a new draft with a new Message-ID),
    and the first run's undo would miss it. None when the output lacks what the undo needs; undoing then says so
    rather than acting on the old one."""
    try:
        return run.expand(tool.spec["undo"], run.undo_values(entry["arguments"], run.result(out), entry["before"]))
    except ToolError:
        return None


def icon():
    return str(next((f for f in OWN_ICONS if f.is_file()), ICON))


# The notify-send of each row that waits for its button, by entry: retire() ends one (notices.py's helper)
WAITING = {}


def notify(entry_id, summary, body="", button=None):
    """One row for the entry (a new one replaces the last, by its stack tag); the button's action when it's
    pressed, else None once the row has gone (dismissed, replaced, expired, retired)."""
    cmd = ["notify-send", "-a", "Claude", "-i", icon(),
           "-h", f"string:x-dunst-stack-tag:claude-change-{entry_id}", "-h", f"int:x-nightdrive-expires:{NOTICE_FOR}"]
    if button:
        cmd += ["-A", f"{button[0]}={button[1]}", "-w"]
    try:
        proc = subprocess.Popen(cmd + ["--", summary, body], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True)
    except OSError:
        return None  # no notify-send: the log still has it, for Claude
    WAITING[entry_id] = proc
    try:
        out = proc.communicate()[0]
    finally:
        if WAITING.get(entry_id) is proc:
            del WAITING[entry_id]
    return None if proc.returncode and proc.returncode < 0 else out.strip() or None


def retire(entry_id):
    """The entry's row gives up its button, for a newer change's (notices.ROWS_MAX): its wait ends, and the row says
    Claude can still undo it, as the log keeps it."""
    proc = WAITING.pop(entry_id, None)
    if proc is not None:
        proc.terminate()
    entry = changes.get(entry_id)
    if entry is not None and entry.get("state") == "done":
        notify(entry_id, entry["notice"], f"Many changes at once: ask Claude to undo this one (change {entry_id}).")
    elif entry is not None:
        notify(entry_id, f"Undid: {entry['notice']}")


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
    try:
        rules = access.load()
    except Exception:  # then no area is known to be readable: only what each change was
        rules = None
    rows = [listed(e, rules) for e in reversed(changes.read())]
    return {"changes": rows[:limit], "total": len(rows)}


def listed(entry, rules):
    """One change as recent_changes gives it. Its arguments and notice are its area's (a draft's text, a note's): an
    area Claude may not read now without asking, or at all, gives only the tool and its state, as the Nightdrive row
    is read even on Strict (#1884); one whose codes Claude doesn't read gets them masked, as its own reads would."""
    row = {k: entry.get(k) for k in ("id", "time", "notice", "tool", "arguments", "state", "at")}
    area = entry.get("area")
    if rules is None or not area or rules.decide("read", area, "read") != "allow":
        row["notice"] = f"A change made with {entry.get('tool')}"
        row.pop("arguments")
        return row
    if any(o["id"] == "secrets" for o in access.areas.options(area)) and not rules.option(area, "secrets"):
        import mask   # only now: most rows don't need it
        row["notice"] = mask.mask(row["notice"])
        row["arguments"] = masked(row["arguments"], mask.mask)
    return row


def masked(value, how):
    if isinstance(value, str):
        return how(value)
    if isinstance(value, list):
        return [masked(v, how) for v in value]
    if isinstance(value, dict):
        return {k: masked(v, how) for k, v in value.items()}
    return value


def undo_change(args):
    """Claude's undo: the change by id, else the newest one still in place, when this server made it (#1881). The log
    is every session's: another conversation's newest change, or one an Ask Claude run made meanwhile, isn't "that"
    in this one. This runs as the server's child, so its parent is the server that logged its own changes."""
    entry_id = args.get("id")
    if entry_id is None:
        newest = next((e for e in reversed(changes.read()) if e["state"] == "done"), None)
        if newest is None:
            raise ToolError("There's no change of Claude's in place to undo.")
        mine = server_id(os.getppid())
        if mine is None or newest.get("server") != mine:
            # Its id alone: what it was is its area's, which recent_changes may not show (#1884)
            raise ToolError(f"The newest change in place, {newest['id']}, wasn't made in this conversation: find the "
                            "one the user means with recent_changes and give its id.")
        entry_id = newest["id"]
    entry = perform(entry_id, "undo", claude=True)
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
