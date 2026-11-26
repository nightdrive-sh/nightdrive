#!/usr/bin/env python3
"""Text that wasn't saved when Text's window was closed, kept for the next time it opens (plugins/text).

⌘W closes the window before the window can ask (Quickshell has no way to refuse a close), so instead of losing what was
written, each unsaved file's text is kept here, and the window opens those files again with it, still unsaved.

  kept.py keep                   stdin's JSON list [{path, text, base}] kept: each file's unsaved text, and base the
                                 md5 of the file's text it started from
  kept.py take                   every one kept, as a JSON list [{path, text, base}], and forgotten here
"""
import hashlib
import json
import os
import sys

STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "nightdrive", "text",
                     "unsaved")


def keep(path, text, base):
    os.makedirs(STATE, exist_ok=True)
    name = os.path.join(STATE, hashlib.md5(path.encode()).hexdigest() + ".json")
    with open(name + ".tmp", "w", encoding="utf-8") as f:
        json.dump({"path": path, "text": text, "base": base}, f)
    os.replace(name + ".tmp", name)


def take():
    out = []
    try:
        names = sorted(os.listdir(STATE))
    except FileNotFoundError:
        return out
    for n in names:
        if not n.endswith(".json"):
            continue
        p = os.path.join(STATE, n)
        try:
            with open(p, encoding="utf-8") as f:
                out.append(json.load(f))
        except (OSError, ValueError):
            pass
        os.remove(p)
    return out


def main(args):
    if args == ["keep"]:
        for k in json.loads(sys.stdin.buffer.read().decode("utf-8")):
            keep(k["path"], k["text"], k["base"])
    elif args == ["take"]:
        print(json.dumps(take()))
    else:
        sys.exit(__doc__.strip())


if __name__ == "__main__":
    main(sys.argv[1:])
