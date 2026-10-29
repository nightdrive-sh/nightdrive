#!/usr/bin/env python3
"""The confirmation card of Nightdrive's MCP server: an act tool (sending, devices, installing) runs only after the
user allows it on screen (MCP 5, Dashboard #1766; registry.py calls ask() before running one), and so does any tool
whose right the user set to Ask in Access (#1831): a read, a change, a delete. The card's heading says which, and a
line says what follows from allowing it: a read goes to Anthropic, a change can be undone, a delete maybe not.

The card is Quickshell's (config/quickshell/ClaudeConfirm.qml, IPC target claudeConfirm). It shows exactly what will
be done: the tool, and every argument Claude gave it, as plain text. Enter or Allow allows, Esc or Deny refuses, and
so does everything else: no answer in TIMEOUT seconds, a card that can't be shown (no Quickshell), a card that goes
away before answering (a crash, a reload), a request that changed on its way. It is the server's, so no Claude Code
setting skips it, and text Claude read (a mail, a web page) can't send anything without the user seeing it first.

How it talks to the card:
1. The request goes to a file in a private folder in XDG_RUNTIME_DIR, as ASCII JSON, and `qs ipc call claudeConfirm
   open FILE` shows it. The card answers "shown MD5" with the MD5 of what it read: a file swapped in between would
   show the user something else than what runs, so a different sum refuses. The file is removed at once.
2. The answer stays in the card: `answer ID` is polled until it says allow, deny or timeout. There is no IPC call
   that allows, and no file to write: only a key or a click on the card does.

`python3 confirm.py --demo mail|device|package [--timeout S]` shows a sample card and prints the answer.
"""

import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import areas  # noqa: E402  (after the path above)
from run import ToolError  # noqa: E402

TIMEOUT = 60         # seconds the card waits for an answer; then it is a refusal
QUEUE_WAIT = 60      # seconds to wait while another card (another Claude session's) is on screen
POLL = 0.4           # seconds between asking the card for its answer
IPC_TIMEOUT = 5      # seconds for one `qs ipc call`
TARGET = "claudeConfirm"
LONG = 80            # characters: a longer value, or one with a newline, gets a box of its own

# What could make the text on the card read differently from what runs: control characters, and the ones that
# reorder (bidi) or hide (zero-width) text. They are shown as ⟨U+202E⟩ instead. ZWJ/ZWNJ stay: scripts and emoji
# need them.
HIDDEN = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f؜​‎‏‪-‮⁠⁦-⁩﻿]")


def visible(text):
    """A string as the card may show it: line ends as \\n, and what hides or reorders text spelled out."""
    text = text.replace("\r\n", "\n")
    return HIDDEN.sub(lambda m: f"⟨U+{ord(m.group()):04X}⟩", text)


def label(name, prop):
    """An argument's name on the card: its schema title, else the name in words (reply_to → Reply to)."""
    title = prop.get("title") if isinstance(prop, dict) else None
    if isinstance(title, str) and title.strip():
        return visible(title.strip())
    return visible(name.replace("_", " ").replace("-", " ").capitalize())


def field(name, prop, value):
    """One argument as a row of the card: {label, text, long, mono, lines}."""
    mono = False
    if isinstance(value, bool):
        text = "Yes" if value else "No"
    elif isinstance(value, (int, float)):
        text = json.dumps(value)
    elif isinstance(value, str):
        text = value
    elif isinstance(value, list) and all(isinstance(v, (str, int, float)) and not isinstance(v, bool) for v in value):
        text = "\n".join(v if isinstance(v, str) else json.dumps(v) for v in value)   # recipients: one a line
    elif value is None:
        text = "(none)"
    else:
        text, mono = json.dumps(value, ensure_ascii=False, indent=2), True
    text = visible(text)
    lines = text.count("\n") + 1
    return {"label": label(name, prop), "text": text, "long": "\n" in text or len(text) > LONG or mono,
            "mono": mono, "lines": lines, "chars": len(text)}


# By what the call is: (heading, note, glyph). An act's own title says it ("Send an email"), as it did before Ask
KINDS = {
    "read": ("Claude wants to read", "What it finds is sent to Anthropic for Claude's answer.", "eye"),
    "modify": ("Claude wants to change", "You can undo it from the notification that follows.", "pencil"),
    "delete": ("Claude wants to delete", "It goes to the trash: you can undo it from the notification that follows.",
               "trash-2"),
    "act-delete": ("Claude wants to delete", "Nightdrive can't undo this.", "trash-2"),
    "act": (None, None, "shield-alert"),
}


def kind(tool):
    """The card's kind for a tool: its right, or act (sending, devices, installing) for what can't be undone."""
    cls = getattr(tool, "cls", None) or tool.spec.get("class", "act")
    right = getattr(tool, "right", None) or ("delete" if tool.spec.get("deletes") else
                                             "read" if cls == "read" else "modify")
    if cls == "act":
        return "act-delete" if right == "delete" else "act"
    return right


def card(tool, arguments, timeout=TIMEOUT):
    """What the card shows: the tool, where it is from, and every argument, in the schema's order and then any
    others. Nothing is left out: what the user doesn't see, they didn't allow."""
    props = tool.spec["inputSchema"].get("properties", {})
    names = [n for n in props if n in arguments] + [n for n in arguments if n not in props]
    title = tool.spec.get("title") or tool.name
    heading, note, glyph = KINDS[kind(tool)]
    return {
        "title": visible(str(title)),
        "source": visible(areas.name(tool.area)),
        "tool": tool.name,
        "heading": heading,
        "note": note,
        "glyph": glyph,
        "fields": [field(n, props.get(n), arguments[n]) for n in names],
        "timeout": timeout,
    }


def qs(*args):
    """One `qs ipc call claudeConfirm …` to the desktop's Quickshell: its output, or None when it can't be reached."""
    try:
        out = subprocess.run(["qs", "ipc", "call", TARGET, *args], capture_output=True, text=True,
                             timeout=IPC_TIMEOUT, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def show(request):
    """Shows the card: its id, or ToolError when it can't be shown as written."""
    folder = Path(tempfile.mkdtemp(prefix="nightdrive-confirm-", dir=os.environ.get("XDG_RUNTIME_DIR") or None))
    try:
        path = folder / "request.json"
        # ASCII, so the card's MD5 of the text it read is the MD5 of these bytes whatever the encodings
        data = json.dumps(request, ensure_ascii=True)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(data)
        want = hashlib.md5(data.encode()).hexdigest()
        waited = time.monotonic() + QUEUE_WAIT
        while True:
            said = qs("open", str(path))
            if said is None:
                raise ToolError(f"{request['tool']} wasn't run: Nightdrive's confirmation card couldn't be shown "
                                "(Quickshell isn't running on this desktop, or is a version without the card). "
                                "Tell the user; it can't be run without their answer on screen.")
            if said != "busy":
                break
            if time.monotonic() > waited:
                raise ToolError(f"{request['tool']} wasn't run: another confirmation stayed on screen for "
                                f"{QUEUE_WAIT} s. Try again once the user has answered it.")
            time.sleep(POLL)
        shown, _, digest = said.partition(" ")
        if shown != "shown" or digest != want:
            qs("close", request["id"])
            raise ToolError(f"{request['tool']} wasn't run: the confirmation card didn't show the request as it "
                            "was sent.")
        return request["id"]
    finally:
        shutil.rmtree(folder, ignore_errors=True)   # what the card shows, mail text say, doesn't stay on disk


def wait(cid, tool, timeout):
    """The card's answer: True to allow, False to deny; ToolError for no answer."""
    deadline = time.monotonic() + timeout + 3   # the card's own countdown ends first; this is in case it hangs
    try:
        while time.monotonic() < deadline:
            said = qs("answer", cid)
            if said == "allow":
                return True
            if said == "deny":
                return False
            if said == "timeout":
                break
            if said != "pending":
                # None or gone: Quickshell stopped or reloaded, and the card with it
                raise ToolError(f"{tool} wasn't run: the confirmation card closed without an answer (Quickshell "
                                "restarted?). Ask the user whether to try again.")
            time.sleep(POLL)
    except BaseException:
        qs("close", cid)   # the client gave up (Ctrl+C, the call cancelled): the card mustn't stay to allow nothing
        raise
    qs("close", cid)
    raise ToolError(f"{tool} wasn't run: the user didn't answer the confirmation card in {timeout} s. Ask them in "
                    "the chat whether to try again.")


def ask(tool, arguments, timeout=TIMEOUT):
    """registry.py's seam: True only when the user allowed this call of an act tool on the card. A refusal is False;
    a card that couldn't ask raises ToolError with the reason, so Claude can tell the user why nothing happened."""
    request = card(tool, arguments, timeout)
    request["id"] = secrets.token_hex(8)
    cid = show(request)
    return wait(cid, tool.name, timeout)


DEMOS = {
    "mail": ({"title": "Send an email", "class": "act", "area": "mail",
              "inputSchema": {"type": "object", "properties": {
                  "to": {"type": "array", "items": {"type": "string"}}, "subject": {"type": "string"},
                  "body": {"type": "string"}}}},
             {"to": ["Maija Meikäläinen <maija@example.com>", "team@example.com"],
              "subject": "Re: <b>Friday</b>",
              "body": "Hi Maija,\n\nFriday works for me: 14:00 at the office. <i>Not markup</i> &amp; not an entity.\n"
                      "Hidden: ‮evil‬ and a zero​width space.\n\n" + "A long line. " * 30 +
                      "\n\nBest,\nJari"}),
    "device": ({"title": "Turn a device on or off", "class": "act", "area": "home-assistant",
                "inputSchema": {"type": "object", "properties": {
                    "entity": {"type": "string", "title": "Device"}, "state": {"type": "string"}}}},
               {"entity": "switch.sauna", "state": "on"}),
    "read": ({"title": "Search mail", "class": "read", "area": "mail",
              "inputSchema": {"type": "object", "properties": {
                  "query": {"type": "string", "title": "Search"}, "account": {"type": "string"}}}},
             {"query": "invoice from:telia", "account": "all"}),
    "trash": ({"title": "Move a note to the trash", "class": "change", "area": "notes", "deletes": True,
               "inputSchema": {"type": "object", "properties": {"path": {"type": "string", "title": "Note"}}}},
              {"path": "Shopping.md"}),
    "package": ({"title": "Install software", "class": "act", "area": "software",
                 "inputSchema": {"type": "object", "properties": {
                     "package": {"type": "string"}, "source": {"type": "string"}, "options": {"type": "object"}}}},
                {"package": "org.gimp.GIMP", "source": "flatpak", "options": {"system": False, "branch": "stable"}}),
}


class Demo:
    def __init__(self, name, spec):
        self.name, self.spec, self.area = name, spec, spec["area"]


def main():
    args = sys.argv[1:]
    if len(args) < 2 or args[0] != "--demo" or args[1] not in DEMOS:
        sys.exit(f"usage: confirm.py --demo {'|'.join(DEMOS)} [--timeout S]")
    timeout = int(args[3]) if args[2:3] == ["--timeout"] and len(args) > 3 else TIMEOUT
    spec, arguments = DEMOS[args[1]]
    try:
        print("allow" if ask(Demo(f"demo_{args[1]}", spec), arguments, timeout) else "deny")
    except ToolError as e:
        print(f"refused: {e}")


if __name__ == "__main__":
    main()
