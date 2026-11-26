#!/usr/bin/env python3
"""Files on the clipboard, for a paste in the writing window (#3304): `clipfiles.py` prints {"files": [...],
"folders": [...]} as JSON, both empty when the clipboard holds no files.

Files' ⌘C / y (its lib/clipboard.py), Nautilus and other file browsers offer copied files as
x-special/gnome-copied-files and text/uri-list, beside the paths as text. A paste in a message being written attaches
the files (PasteFiles.qml, as `nightmail new FILE…` does), and pastes the text as before when there are none. Only
local files that can be read: a folder is listed apart (a mail can't carry one: compress it first, as `nightmail new`
says), and a link to a web page (a browser's uri-list) or a file that is gone is left out, so a browser's copied link
still pastes as text."""

import json
import os
import subprocess
import sys
from urllib.parse import unquote, urlsplit

TYPES = ["x-special/gnome-copied-files", "text/uri-list"]   # in the order read: Nautilus's own first, as Files reads
TIMEOUT = 2                                                 # seconds for wl-paste: an owner that never answers


def paths_of(text):
    """The local paths in a uri-list or a gnome-copied-files (its first line is copy or cut)."""
    out = []
    for line in text.replace("\r", "").split("\n"):
        line = line.strip()
        if not line or line.startswith("#") or line in ("copy", "cut"):
            continue
        u = urlsplit(line)
        if u.scheme != "file" or u.netloc not in ("", "localhost"):
            continue
        p = unquote(u.path)
        if p.startswith("/") and p not in out:
            out.append(p)
    return out


def sorted_out(paths):
    """{files, folders}: the readable files, and the folders apart; anything else is left out."""
    files = [p for p in paths if os.path.isfile(p) and os.access(p, os.R_OK)]
    folders = [p for p in paths if os.path.isdir(p)]
    return {"files": files, "folders": folders}


def wl_paste(*args):
    r = subprocess.run(["wl-paste", "--no-newline", *args], capture_output=True, text=True, timeout=TIMEOUT)
    return r.stdout if r.returncode == 0 else ""


def read(paste=wl_paste):
    try:
        offered = paste("--list-types").split("\n")
        kind = next((t for t in TYPES if t in offered), None)
        return sorted_out(paths_of(paste("--type", kind))) if kind else sorted_out([])
    except (OSError, subprocess.SubprocessError):
        return sorted_out([])


if __name__ == "__main__":
    json.dump(read(), sys.stdout)
    print()
