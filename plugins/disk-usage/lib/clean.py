#!/usr/bin/env python3
"""Disk Usage's Clean up (app/CleanPanel.qml, `disk-usage clean`): what can go without losing anything of yours.

  clean.py list [--text]      each kind with the space it takes now, as JSON (--text: a line each, for a terminal)
  clean.py run [--text] ID…   empty them (all: every kind); {"freed": bytes, "failed": [what couldn't go]}

Only what an app makes again by itself, or what you already threw away (the Trash), and only these named folders: never
the whole of ~/.cache, where some apps keep what isn't a cache (Spotify's offline songs, Poetry's environments,
Playwright's browsers, Nightdrive's own theme and plugin lists). A folder is emptied, not removed, and never through a
link: one that is a link to elsewhere is left alone."""

import glob
import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import walk  # noqa: E402

HOME = os.path.expanduser("~")
CACHE = os.environ.get("XDG_CACHE_HOME") or HOME + "/.cache"
DATA = os.environ.get("XDG_DATA_HOME") or HOME + "/.local/share"
UID = os.getuid()

# Browsers' caches, in ~/.cache and in their Flatpaks' own (~/.var/app/ID/cache). Only browsers': another Flatpak can
# keep there what isn't a cache (Spotify's offline songs).
BROWSERS = ["mozilla", "google-chrome", "chromium", "BraveSoftware", "microsoft-edge", "vivaldi", "epiphany", "librewolf"]
BROWSER_APPS = ["org.mozilla.firefox", "com.google.Chrome", "org.chromium.Chromium", "com.brave.Browser",
                "com.microsoft.Edge", "com.vivaldi.Vivaldi", "io.gitlab.librewolf-community", "org.gnome.Epiphany"]
SHADERS = ["mesa_shader_cache", "mesa_shader_cache_db", "nvidia/GLCache"]

# id, name, glyph, what it is (one line), folders (globs) whose contents go
KINDS = [
    ("trash", "Trash", "trash-2", "What you deleted in Files, here and on other disks",
     [DATA + "/Trash/files", DATA + "/Trash/info", DATA + "/Trash/expunged",
      f"/run/media/*/*/.Trash-{UID}", f"/media/*/*/.Trash-{UID}", f"/mnt/*/.Trash-{UID}"]),
    ("thumbnails", "Thumbnails", "image", "Previews of pictures and videos in Files, made again when shown",
     [CACHE + "/thumbnails"]),
    ("browsers", "Browser caches", "globe", "Copies of web pages kept to load them faster; logins and history stay",
     [f"{CACHE}/{b}" for b in BROWSERS] + [f"{HOME}/.var/app/{a}/cache" for a in BROWSER_APPS]),
    ("packages", "Downloaded packages", "download", "pip, uv, npm, Yarn, Cargo and Go fetch them again when needed",
     [CACHE + "/pip", CACHE + "/uv", HOME + "/.npm/_cacache", CACHE + "/yarn", CACHE + "/go-build",
      HOME + "/.cargo/registry/cache"]),
    ("shaders", "Shader caches", "monitor-cog", "Graphics drivers' work for games and apps; the next start is a bit slower",
     [f"{CACHE}/{s}" for s in SHADERS] + [f"{HOME}/.var/app/*/cache/{s}" for s in SHADERS]),
]


def too_wide(path):
    """A folder that holds home, or home itself: what a cache path comes to when XDG_CACHE_HOME is set wrong (to ~ or
    /). Emptying it would take everything, so it is never one of a kind's folders."""
    real, home = os.path.realpath(path), os.path.realpath(HOME)
    return real == home or home.startswith(real.rstrip("/") + "/")


def folders(globs):
    """The folders a kind's globs find, but not one that is a link (~/.cache/pip pointing at a folder of yours), nor
    one too wide"""
    found = []
    for g in globs:
        for p in sorted(glob.glob(g)):
            if os.path.isdir(p) and not os.path.islink(p) and not too_wide(p):
                found.append(p)
    return found


def contents_size(path):
    return walk.du(path) - walk.du_self(path)


def size(kind):
    return sum(contents_size(p) for p in folders(kind[4]))


def empty(path, failed):
    """Everything inside path, not path itself; a link inside goes as a link"""
    try:
        entries = list(os.scandir(path))
    except OSError as e:
        failed.append(f"{path}: {e.strerror}")
        return
    for e in entries:
        try:
            if e.is_dir(follow_symlinks=False):
                shutil.rmtree(e.path)
            else:
                os.unlink(e.path)
        except OSError as err:
            failed.append(f"{e.path}: {err.strerror}")


def run(ids):
    failed, freed = [], 0
    for kind in KINDS:
        if kind[0] not in ids:
            continue
        paths = folders(kind[4])
        before = sum(contents_size(p) for p in paths)
        # The Trash through gio when it is there: it knows every disk's trash, and tells Files the trash is empty
        if kind[0] == "trash" and shutil.which("gio"):
            subprocess.run(["gio", "trash", "--empty"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for p in paths:
            empty(p, failed)
        freed += max(0, before - sum(contents_size(p) for p in paths))
    return {"freed": freed, "failed": failed[:10]}


def human(n):
    for unit in ("B", "kB", "MB", "GB", "TB"):
        if n < 1000 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "B" or n >= 100 else f"{n:.1f} {unit}"
        n /= 1000


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    text = "--text" in argv
    args = [a for a in argv[2:] if a != "--text"]
    if cmd == "list":
        kinds = [{"id": k[0], "name": k[1], "glyph": k[2], "what": k[3], "size": size(k)} for k in KINDS]
        if text:
            for k in kinds:
                print(f"{k['id']:<12}{human(k['size']):>9}  {k['name']}: {k['what']}")
        else:
            print(json.dumps(kinds))
    elif cmd == "run" and args:
        known = [k[0] for k in KINDS]
        ids = known if args == ["all"] else args
        bad = [i for i in ids if i not in known]
        if bad:
            print(f"Unknown: {' '.join(bad)} (clean.py list names them)", file=sys.stderr)
            return 2
        r = run(set(ids))
        if text:
            print(f"Freed {human(r['freed'])}")
            for f in r["failed"]:
                print(f"Couldn't go: {f}", file=sys.stderr)
        else:
            print(json.dumps(r))
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
