#!/usr/bin/env python3
"""Disk Usage's side of Claude's tools (mcp.json): what takes the space, kept to the rules Claude's file tools keep.

  claude.py top [--limit N] [-- PATH]
                             the N biggest entries of PATH (default your home folder, 20) as JSON:
                             {path, total, files, scanned, disk, entries: [{name, kind, size, share}]}
  claude.py card ID…         what Clean up would empty, for the confirmation card: {"Empties": a line per kind}

top keeps to the folders Settings › Claude › Access › Apps and files lets Claude use (config/hypr/scripts/files_rules.py,
the same check as `nightdrive files`): PATH, resolved, is one of them or inside one, in home and not hidden. Hidden
entries (.cache, .local) fold into one row, "hidden items", as Claude sees no hidden names elsewhere either;
disk_usage_cleanable tells what of them Clean up can empty. A scan under MAX_AGE old is reused, so asking twice doesn't
walk the disk twice. Outside Claude (no NIGHTDRIVE_MCP) the folders aren't limited, as for `nightdrive files`."""

import json
import os
import sys
import time

LIB = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, LIB)
import clean  # noqa: E402
import scan  # noqa: E402
import walk  # noqa: E402

# The rules live with the desktop's files command, in the same repo: plugins/disk-usage/lib → config/hypr/scripts
RULES = os.path.join(LIB, "..", "..", "..", "config", "hypr", "scripts")
MAX_AGE = 3600         # seconds a scan is good for here
TOP_MAX = 100
HIDDEN = "hidden"      # an entry's kind for the folded hidden ones


def rules():
    """files_rules, or exit: without the rules nothing is shown (fail closed)"""
    sys.path.insert(0, os.path.realpath(RULES))
    try:
        import files_rules
    except ImportError:
        sys.exit("Disk Usage can't find Nightdrive's file rules, so it shows Claude nothing.")
    return files_rules


def allowed(path):
    """The folder PATH means, resolved, if Claude may look in it; exits with the reason otherwise"""
    r = rules()
    p = r.Path(path).expanduser()
    p = (p if p.is_absolute() else r.HOME / p).resolve()
    folders = r.claude_folders()
    if folders is not None and not r.within(p, folders):
        r.refuse_outside(path, folders)
    if not r.inside_home(p):
        sys.exit(f"{path}: only folders in your home folder, and none hidden.")
    if not p.is_dir():
        sys.exit(f"{path}: not a folder.")
    return str(p)


def last_scan(path):
    """The cached scan of path if it is fresh enough, else a new one"""
    last = scan.read_cache(path)
    if last and time.time() - last.get("scanned", 0) < MAX_AGE:
        return last
    return scan.scan(path, progress=False)


def entries(tree, total, n):
    """The tree's top level as rows, hidden ones folded into one, biggest first"""
    rows, hidden = [], {"name": "", "kind": HIDDEN, "size": 0, "count": 0}
    for k in tree.get("c", []):
        if k["k"] != walk.FOLD_KIND and k["n"].startswith("."):
            hidden["size"] += k["s"]
            hidden["count"] += 1
        elif k["k"] == walk.FOLD_KIND:
            rows.append({"name": "", "kind": "smaller items", "size": k["s"], "count": k["i"]})
        else:
            rows.append({"name": k["n"], "kind": "folder" if k["k"] == "d" else "file", "size": k["s"]})
    if hidden["count"]:
        rows.append(hidden)
    rows.sort(key=lambda r: -r["size"])
    for r in rows:
        r["share"] = round(100 * r["size"] / max(1, total), 1)
    return rows[:n]


def top(path, n):
    path = allowed(path)
    r = last_scan(path)
    return {"path": r["path"], "total": r["total"], "files": r["files"], "scanned": r["scanned"],
            "disk": r["disk"], "entries": entries(r["tree"], r["total"], n)}


def card(ids):
    known = {k[0]: k for k in clean.KINDS}
    bad = [i for i in ids if i not in known]
    if bad or not ids:
        sys.exit(f"Unknown: {' '.join(bad) or '(none)'}; disk_usage_cleanable names them.")
    lines = [f"{known[i][1]}: {clean.human(clean.size(known[i]))}" for i in ids]
    return {"Empties": "\n".join(lines)}


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "top":
        # [--limit N] [-- PATH], as mcp.json passes them: a path that begins with - stays a path
        args, n = argv[2:], 20
        if args[:1] == ["--limit"] and len(args) > 1:
            n, args = int(args[1]), args[2:]
        if args[:1] == ["--"]:
            args = args[1:]
        print(json.dumps(top(args[0] if args else "~", max(1, min(n, TOP_MAX)))))
    elif cmd == "card":
        print(json.dumps(card(argv[2:])))
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.setrecursionlimit(10000)
    sys.exit(main(sys.argv))
