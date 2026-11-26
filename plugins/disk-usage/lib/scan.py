#!/usr/bin/env python3
"""Disk Usage's scans and places (bin/disk-usage, app/Scanner.qml).

  scan.py scan PATH [N]   walk PATH: progress lines {"p": [files, bytes, folder]}, then the result into the cache and
                          {"done": PATH}. N: the bytes it is expected to hold (the window knows a folder's size)
  scan.py cached PATH     the last scan of PATH as JSON, or nothing
  scan.py places          the sidebar's places: Home, the system disk, mounted disks, the folders you chose
  scan.py remember PATH   a chosen folder into the places (forget PATH takes it out)
  scan.py top PATH [N]    the N biggest entries of PATH, for a terminal

The cache keeps each place's last scan (CACHE_DIR, a file per path), so the window opens on it at once."""

import hashlib
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import walk  # noqa: E402

HOME = os.path.expanduser("~")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME") or HOME + "/.cache", "nightdrive", "disk-usage")
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or HOME + "/.local/state", "nightdrive", "disk-usage")
FOLDERS = os.path.join(STATE_DIR, "folders.json")      # the folders you chose, newest first
MAX_FOLDERS = 6
EARLY_FOLD = 20000     # while walking, an entry under 1/EARLY_FOLD of the expected total folds (memory stays small)
ROWS = 4000            # the finished tree keeps entries of 1/ROWS of the total and up
REMOVABLE = ("/run/media/", "/media/", "/mnt/")         # where other disks are mounted
CACHE_DAYS = 30        # a scan not opened again in this long goes (a closer look's, a folder no longer chosen)


def cache_file(path):
    return os.path.join(CACHE_DIR, hashlib.sha1(path.encode()).hexdigest() + ".json")


def read_cache(path):
    """The last scan of path; reading it keeps it from forget_old()"""
    try:
        with open(cache_file(path)) as f:
            data = json.load(f)
        os.utime(cache_file(path))
        return data
    except (OSError, ValueError):
        return None


def write_json(file, data):
    os.makedirs(os.path.dirname(file), exist_ok=True)
    tmp = file + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    os.replace(tmp, file)


def say(obj):
    print(json.dumps(obj, separators=(",", ":")), flush=True)


def scan(path, progress=True, expect=0):
    path = os.path.realpath(path)
    if not os.path.isdir(path):
        raise SystemExit(f"Not a folder: {path}")
    d = walk.disk(path)
    # What it may come to: as the caller says, the last scan, else the disk's used space (more than any folder on it
    # holds). Too much would fold away detail worth showing; too little only takes more memory.
    last = read_cache(path)
    expect = expect or (last["total"] if last else d["used"])
    s = walk.Scan(path, max(64 * 1024, expect // EARLY_FOLD),
                  (lambda f, b, p: say({"p": [f, b, p]})) if progress else None)
    started = time.monotonic()
    tree = s.run()
    walk.prune(tree, tree["s"] // ROWS)
    result = {"path": path, "scanned": int(time.time()), "took": round(time.monotonic() - started, 1),
              "total": tree["s"], "files": s.files, "unreadable": s.unreadable, "others": s.others[:20],
              "disk": d, "tree": tree}
    write_json(cache_file(path), result)
    forget_old()
    return result


def forget_old():
    old = time.time() - CACHE_DAYS * 86400
    try:
        for e in os.scandir(CACHE_DIR):
            if e.name.endswith(".json") and e.stat().st_mtime < old:
                os.unlink(e.path)
    except OSError:
        pass


def folders():
    try:
        with open(FOLDERS) as f:
            return [p for p in json.load(f) if isinstance(p, str)]
    except (OSError, ValueError):
        return []


def remember(path, add=True):
    path = os.path.realpath(path)
    rest = [p for p in folders() if p != path]
    write_json(FOLDERS, ([path] if add else []) + rest[:MAX_FOLDERS - 1])


def places():
    rows = [{"name": "Home", "path": HOME, "glyph": "house"},
            {"name": "This computer", "path": "/", "glyph": "hard-drive"}]
    for mp, (_, fstype) in sorted(walk.mounts().items()):
        if mp.startswith(REMOVABLE) and fstype not in ("autofs", "tmpfs", "fuse.portal"):
            rows.append({"name": os.path.basename(mp), "path": mp, "glyph": "usb"})
    for p in folders():
        if os.path.isdir(p) and p not in (r["path"] for r in rows):
            rows.append({"name": os.path.basename(p) or p, "path": p, "glyph": "folder", "chosen": True})
    for r in rows:
        r["disk"] = walk.disk(r["path"])
        last = read_cache(r["path"])
        if last:
            r["total"], r["scanned"] = last["total"], last["scanned"]
    return rows


def human(n):
    for unit in ("B", "kB", "MB", "GB", "TB"):
        if n < 1000 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "B" or n >= 100 else f"{n:.1f} {unit}"
        n /= 1000


def top(path, n):
    r = scan(path, progress=False)
    rows = r["tree"].get("c", [])[:n]
    total = max(1, r["total"])
    for k in rows:
        name = f"{k['i']} smaller items" if k["k"] == walk.FOLD_KIND else k["n"] + ("/" if k["k"] == "d" else "")
        print(f"{human(k['s']):>9}  {100 * k['s'] / total:5.1f} %  {name}")
    print(f"{human(r['total']):>9}  in {r['path']} ({r['files']} files, {r['took']} s)")


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    arg = argv[2] if len(argv) > 2 else ""
    if cmd == "scan" and arg:
        r = scan(arg, expect=int(float(argv[3])) if len(argv) > 3 else 0)
        say({"done": r["path"]})
    elif cmd == "cached" and arg:
        r = read_cache(os.path.realpath(arg))
        if r:
            say(r)
    elif cmd == "places":
        say(places())
    elif cmd in ("remember", "forget") and arg:
        remember(arg, cmd == "remember")
    elif cmd == "top" and arg:
        top(arg, int(argv[3]) if len(argv) > 3 else 20)
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.setrecursionlimit(10000)     # a folder nested deeper than Python's 1000 (node_modules in node_modules…)
    sys.exit(main(sys.argv))
