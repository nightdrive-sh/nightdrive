"""The version of each file this computer and the Hub last agreed on, kept here for a three-way merge (#3397).

The Hub keeps every version but serves only the newest (protocol.md), and a merge field by field needs the one both
sides started from: so the client keeps it itself, for the collections whose rule merges (Rule.keeps_base). A copy
goes in state_dir/base/<collection>/<path> whenever the manifest records an agreement with content, and goes when the
file is deleted. It is only ever used while its hash is the manifest's for that path (after a fresh start, the
agreement from before it: manifest.ancestor), so a copy left behind by a crash is never taken for the base of another
version: then there is no base, and the rule keeps both sides as before.

Tasks' files are small (the whole vdir is ~200 kB), so a second copy of them costs little.
"""
import os
import shutil

import manifest as mf
import settings


class Bases:
    def __init__(self, collection, rule):
        self.rule = rule
        self.dir = settings.state_dir() / "base" / collection

    def wanted(self, path):
        return self.rule.keeps_base(path)

    def file(self, path):
        return self.dir.joinpath(*path.split("/"))

    def get(self, path, h):
        """The agreed content of path if it is kept and its hash is h (the manifest's), else None."""
        if not h or not self.wanted(path):
            return None
        try:
            data = self.file(path).read_bytes()
        except (FileNotFoundError, IsADirectoryError, NotADirectoryError):
            return None
        return data if mf.data_hash(data) == h else None

    def put(self, path, data):
        if self.wanted(path):
            settings.write_atomic(self.file(path), data)

    def drop(self, path):
        try:
            os.unlink(self.file(path))
        except (FileNotFoundError, IsADirectoryError, NotADirectoryError):
            pass

    def fill(self, man, local, read):
        """Keeps a copy of every file that is as last agreed and has none (or a stale one): those the pull found the
        same as the Hub's, and what a computer synced before this piece has, so its first conflict can already be
        merged. read(path) gives a file's content here."""
        for path, h in local.items():
            entry = man.get(path)
            if entry and entry["h"] == h and self.wanted(path) and self.get(path, h) is None:
                try:
                    data = read(path)
                except OSError:
                    continue
                if mf.data_hash(data) == h:
                    self.put(path, data)
