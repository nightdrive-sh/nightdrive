"""What this computer last agreed with the Hub on, per collection, and what has changed here since.

The manifest (state_dir/<collection>.json) holds, for each path, the version the Hub gave it and the hash of the
content this computer had then (null for a deletion), with the Hub's id and the changes cursor. Comparing it with the
files on disk tells a sync what to send: a hash that differs is an edit made here, a path that is gone is a deletion
made here. It never decides anything about files it has no entry for: those are new here, or new to this computer.

Each entry also keeps a few of the contents agreed on before ("p", newest first): what the file was on its way here.

A manifest made with another Hub (another server id), or with this Hub before it went back in time (put back from a
copy by hand: its newest version is older than one this computer has seen), is no guide to it, so it starts empty: a
"fresh" sync, which only adds and merges and deletes nothing (sync.py, fresh.py; protocol.md › Info). The entries it
had are kept as `before` until that sync is done, to tell which side of a difference is the newer one.
"""
import hashlib
import os
from pathlib import Path

import settings

CHUNK = 1 << 20
PAST = 8        # earlier contents remembered per file: enough to know an old copy, small for thousands of files


def file_hash(path):
    """SHA-256 of a file as lowercase hex (protocol.md › Terms), or None when there is no such file."""
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            while True:
                chunk = f.read(CHUNK)
                if not chunk:
                    break
                h.update(chunk)
    except (FileNotFoundError, IsADirectoryError, NotADirectoryError):
        return None
    return h.hexdigest()


def data_hash(data):
    return hashlib.sha256(data).hexdigest()


def scan(root, accept):
    """{path: hash} of the files under root that the collection's rule accepts. Hidden files and folders are left out:
    an app's half-written temporary (`.x.tmp`), an editor's swap file, `.DS_Store`; the protocol refuses such names
    anyway. Links are left out too: a link to a file outside the folder would send that file."""
    root = Path(root)
    out = {}
    for d, dirs, files in os.walk(root):
        dirs[:] = sorted(x for x in dirs if not x.startswith(".") and not os.path.islink(os.path.join(d, x)))
        for name in sorted(files):
            full = os.path.join(d, name)
            if name.startswith(".") or os.path.islink(full):
                continue
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            if accept(rel):
                h = file_hash(full)
                if h is not None:       # gone between the listing and the read: the next sync sees it
                    out[rel] = h
    return out


class Manifest:
    """One collection's manifest. entries: {path: {"v": version, "h": hash or None, "p": [earlier hashes]}}."""

    def __init__(self, collection):
        self.collection = collection
        self.path = settings.state_dir() / ("%s.json" % collection)
        data = settings.read_json(self.path, {}) or {}
        self.server = data.get("server")
        self.cursor = int(data.get("cursor") or 0)
        self.entries = data.get("files") or {}
        self.before = data.get("before") or {}      # the entries of the Hub before a fresh start (fresh.py)

    def start(self, server, newest=None):
        """Make this manifest the one for `server`, whose newest version in the collection is `newest` (None: not
        known). Returns True when it was made with another Hub (or none), or this Hub has gone back to before the
        cursor: then it starts over, empty and from cursor 0, so nothing is taken for a deletion. The entries it had
        stay as `before` until finish()."""
        # Every version this computer has from the Hub (the cursor, its own writes' answers) is at most the Hub's
        # newest, unless the Hub went back
        seen = max([self.cursor] + [e["v"] for e in self.entries.values()])
        went_back = newest is not None and seen > newest
        if self.server == server and not went_back:
            return False
        # A fresh start broken off and started again keeps the entries of the one before it too
        self.before.update(self.entries)
        self.server, self.cursor, self.entries = server, 0, {}
        return True

    def ancestor(self, path):
        """The content this computer last agreed on for `path` before a fresh start (a hash), or None."""
        return (self.before.get(path) or {}).get("h")

    def finish(self):
        """A sync went through: the fresh start, if there was one, is done and `before` is no longer needed."""
        self.before = {}

    def get(self, path):
        return self.entries.get(path)

    def set(self, path, version, hash_):
        old = self.entries.get(path) or self.before.get(path) or {}
        past = old.get("p") or []
        if old.get("h") and old["h"] != hash_:
            past = [old["h"]] + [h for h in past if h != old["h"]]
        e = {"v": int(version), "h": hash_}
        if past:
            e["p"] = past[:PAST]
        self.entries[path] = e

    def drop(self, path):
        self.entries.pop(path, None)

    def live(self):
        """{path: hash} of the files this computer and the Hub last agreed exist."""
        return {p: e["h"] for p, e in self.entries.items() if e.get("h")}

    def save(self):
        data = {"server": self.server, "cursor": self.cursor, "files": self.entries}
        if self.before:
            data["before"] = self.before
        settings.write_json(self.path, data)

    def pending(self, local):
        """(edited or new here, deleted here) against `local` ({path: hash} from scan): what the next sync sends."""
        live = self.live()
        changed = sorted(p for p, h in local.items() if (self.entries.get(p) or {}).get("h") != h)
        gone = sorted(p for p in live if p not in local)
        return changed, gone
