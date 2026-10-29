#!/usr/bin/env python3
"""Keep it or it goes back: after a change that could leave the user without a usable screen or network (a display's
scale or resolution, the network off), Nightdrive's confirmation card asks whether to keep it, as a display settings
dialog does. Enter keeps it; Esc, no answer in time, or a card that can't be shown put it back by running the revert
command. (MCP 13, Dashboard #1774; `display … --keep` and `network … --keep` call it, Claude's act tools in
config/mcp/tools/sound-display.json pass --keep.)

    keep.py --title TEXT [--field LABEL VALUE]... [--seconds N] [--with JSON] [--kept JSON] -- REVERT ARGV...

--kept's JSON array is a command run once the user keeps it (`display` makes the new value last past a restart only
then, #1887): the change is on trial until then, and what a hard restart on a black screen finds is the old one.

The question waits in a process of its own session: whatever happens to the caller (Claude's call cancelled, the
terminal closed), the change still goes back unless the user keeps it. The caller waits for the answer and prints
{"kept": true} or {"kept": false, "reason": …}, after the fields of --with's object (what the change did); exit 1
only when going back failed (stderr says so).
"""

import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import confirm  # noqa: E402  (after the path above)
from run import ToolError  # noqa: E402

SECONDS = 20        # to answer: long enough to find the key, short enough to wait out on a black screen
SETTLE = 1.5        # seconds before asking: a scale change reloads Hyprland, and the card should land on the new screen
REVERT_TIMEOUT = 30


class Question:
    """What confirm.card() reads from a tool: the card's title, the area it names, and the rows as arguments."""

    def __init__(self, title, fields):
        self.name, self.area = "keep", "sound-display"
        props = {f"f{i}": {"type": "string", "title": label} for i, (label, _) in enumerate(fields)}
        self.spec = {"title": title, "inputSchema": {"type": "object", "properties": props}}
        self.arguments = {f"f{i}": value for i, (_, value) in enumerate(fields)}


def parse(args):
    title, fields, seconds, extra, kept = None, [], SECONDS, {}, None
    while args and args[0] != "--":
        flag = args.pop(0)
        if flag == "--title" and args:
            title = args.pop(0)
        elif flag == "--field" and len(args) >= 2:
            fields.append((args.pop(0), args.pop(0)))
        elif flag == "--seconds" and args:
            seconds = int(args.pop(0))
        elif flag == "--with" and args:
            extra = json.loads(args.pop(0))
        elif flag == "--kept" and args:
            kept = json.loads(args.pop(0))
            if not isinstance(kept, list) or not kept or not all(isinstance(a, str) for a in kept):
                sys.exit("keep.py: --kept takes a JSON array of strings, the command")
        else:
            sys.exit(f"keep.py: unknown or incomplete {flag} (see its docstring)")
    revert = args[1:]
    if not title or not revert:
        sys.exit("usage: keep.py --title TEXT [--field LABEL VALUE]... [--seconds N] [--with JSON] [--kept JSON] -- "
                 "REVERT ARGV...")
    return title, fields, seconds, extra, kept, revert


def attempt(argv):
    """A command's failure in words, or None when it ran."""
    try:
        done = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=REVERT_TIMEOUT)
        return done.returncode != 0 and (done.stderr.strip() or f"exit {done.returncode}") or None
    except (OSError, subprocess.TimeoutExpired) as e:
        return str(e)


def watch(title, fields, seconds, _extra, kept_cmd, revert):
    """The detached half: ask, and go back unless kept. Its one line of stdout is the answer for the caller."""
    time.sleep(SETTLE)
    # The card's own words are an act tool's (Allow, "Denied in 20 s"): this row says what they mean here
    question = Question(title, fields + [("Otherwise", "It goes back as it was")])
    try:
        kept = confirm.ask(question, question.arguments, timeout=seconds)
        reason = "" if kept else "the user chose not to keep it"
    except ToolError as e:
        # The card's message is written for an act tool ("… wasn't run: …. Ask them …"): its first sentence is why
        kept, reason = False, str(e).replace("keep wasn't run: ", "").split(". ")[0]
    if kept:
        # Here, not in the caller: a call cancelled meanwhile still keeps what the user kept
        answer = {"kept": True}
        failed = kept_cmd and attempt(kept_cmd)
        if failed:
            answer["keep_failed"] = failed
    else:
        failed = attempt(revert)
        answer = {"kept": False, "reason": reason}
        if failed:
            answer["revert_failed"] = failed
    try:
        print(json.dumps(answer), flush=True)
    except OSError:
        pass   # the caller is gone: the change went back all the same


def main():
    args = sys.argv[1:]
    if args[:1] == ["--watch"]:
        watch(*parse(args[1:]))
        return
    extra = parse(list(args))[3]   # a usage error now, not in the detached half
    child = subprocess.Popen([sys.executable, __file__, "--watch", *args], stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, text=True, start_new_session=True)
    line = child.stdout.readline().strip()
    try:
        answer = json.loads(line)
    except ValueError:
        sys.exit("The keep question ended without an answer; the change may still be in place.")
    print(json.dumps({**extra, **answer}))
    if answer.get("revert_failed"):
        sys.exit(f"Going back failed: {answer['revert_failed']}")


if __name__ == "__main__":
    main()
