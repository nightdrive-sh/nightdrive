#!/usr/bin/env python3
"""Text into a VM as key presses, for garage-ctl type (lib/qemu.sh):

    typekeys.py SOCKET VM KEYMAP < TEXT

An installer's console (an ISO's, before ssh is up) has no clipboard, and qemu's SDL window shares none, so the text
is typed: QMP's send-key, one key and its modifiers at a time (#1872). A key press is a key on the guest's keyboard,
not a character, so it goes by the layout the guest's console has: "us", which an installer starts with, or "fi"
(Finnish, PC). The host's own layout doesn't matter. Every character is looked up before anything is typed: one the
layout has no key for stops it all, with its line and column, rather than half a command typed.

Exit 1 with a line the window can show.
"""
import json
import socket
import sys
import time

HOLD_MS = 20        # how long each key is held down
PACE = 0.03         # seconds between keys: qemu drops input events past its queue's limit, so it isn't filled at once
MAX_CHARS = 20000   # a paste that size is a mistake, not a command
TIMEOUT = 5

# Keys by qemu's names (qcodes), which are a US keyboard's: a letter is its key, "shift" or "alt_r" (AltGr) before it a
# modifier held with it. Built from the rows below: the character each key types alone, with Shift, with AltGr
ROW_KEYS = ["grave_accent", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "minus", "equal",
            "bracket_left", "bracket_right", "semicolon", "apostrophe", "backslash", "less", "comma", "dot", "slash"]
LAYOUTS = {
    #       `1234567890-=  []  ;'  \  <  ,./      (US positions)
    "us": ("`1234567890-=" "[]" ";'" "\\" "" ",./",
           "~!@#$%^&*()_+" "{}" ":\"" "|" "" "<>?",
           ""),
    "fi": ("§1234567890+´" "å¨" "öä" "'" "<" ",.-",
           "½!\"#¤%&/()=?`" "Å^" "ÖÄ" "*" ">" ";:_",
           "  @£$€ {[]}\\ " " ~" "  " " " "|" "   "),
}
# Dead keys in the Finnish layout: pressed alone they wait for the next one, so a space after makes the character
DEAD = {"fi": set("´`^~¨")}


def keymap(name):
    alone, shifted, altgr = LAYOUTS[name]
    keys = {}
    for row, mods in ((altgr, ["alt_r"]), (shifted, ["shift"]), (alone, [])):
        # A missing key in a row ("" for the US keyboard's 102nd key) leaves the positions after it where they are
        positions = [k for k in ROW_KEYS if not (name == "us" and k == "less")]
        for key, ch in zip(positions, row):
            if ch != " ":
                keys[ch] = [mods + [key]]
    for c in "abcdefghijklmnopqrstuvwxyz":
        keys[c] = [[c]]
        keys[c.upper()] = [["shift", c]]
    if name == "fi":
        keys["€"] = [["alt_r", "e"]]
    for c in DEAD.get(name, ()):
        if c in keys:
            keys[c] = keys[c] + [["spc"]]
    keys[" "] = [["spc"]]
    keys["\n"] = [["ret"]]
    keys["\t"] = [["tab"]]
    return keys


def presses(text, keys):
    out = []
    for n, line in enumerate(text.split("\n"), 1):
        for col, ch in enumerate(line, 1):
            if ch not in keys:
                sys.exit(f"No key for {ch!r} (line {n}, column {col}) on a {sys.argv[3]} keyboard: nothing was typed")
            out += keys[ch]
        out.append(["ret"])
    return out[:-1]     # the last line's own Enter only if the text ends with a newline


def answer(f):
    while True:
        line = f.readline()
        if not line:
            raise ConnectionError("closed")
        r = json.loads(line)
        if "return" in r or "error" in r:
            return r


def main():
    if len(sys.argv) != 4 or sys.argv[3] not in LAYOUTS:
        sys.exit(__doc__)
    path, vm, layout = sys.argv[1:4]
    text = sys.stdin.read().replace("\r\n", "\n")
    if len(text) > MAX_CHARS:
        sys.exit(f"That is {len(text)} characters: at most {MAX_CHARS} are typed")
    todo = presses(text, keymap(layout))
    try:
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(TIMEOUT)
        s.connect(path)
        f = s.makefile("rw")
        f.readline()
        f.write('{"execute": "qmp_capabilities"}\n')
        f.flush()
        answer(f)
        for keys in todo:
            f.write(json.dumps({"execute": "send-key", "arguments": {
                "keys": [{"type": "qcode", "data": k} for k in keys], "hold-time": HOLD_MS}}) + "\n")
            f.flush()
            r = answer(f)
            if "error" in r:
                sys.exit(f"{vm}: {r['error'].get('desc', r['error'])}")
            time.sleep(PACE)
    except (OSError, ValueError) as e:
        sys.exit(f"{vm} doesn't answer ({getattr(e, 'strerror', None) or e})")


main()
