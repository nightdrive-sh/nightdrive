"""One sync of one collection: first what changed on the Hub, then what changed here (#3391 › Malli).

Every decision compares three things for a path: the file here now, the Hub's version, and the manifest (what both
last agreed on, manifest.py). The rules, in short:

- Nothing is deleted because it is missing. A file here that the Hub doesn't have is sent; a file on the Hub that
  isn't here is fetched, unless the manifest says this computer had it and deleted it. Only a tombstone deletes here,
  and only a file unchanged since the last agreement.
- A deletion never wins over an edit: an edited file comes back over a tombstone (written with the tombstone's version
  as base), and a deletion the Hub refuses because of an edit fetches the edit.
- Both sides edited: the app's rule keeps both (apps.py).
- A fresh start (the first sync, or another Hub, manifest.start) has no agreement to go by, so it only adds and
  merges: identical files match by hash, differing ones keep both, nothing is deleted on either side.
- Many files gone here at once (emptied by mistake) aren't sent as deletions unless asked: `--allow-deletes`. A folder
  gone altogether (a disk not mounted) stops the collection's sync until it is back.

A crash at any point is safe to sync again: a write the Hub already has answers "changed: false", and a file fetched
but not yet in the manifest matches by hash next time.
"""
import os

import client as hubclient
import manifest as mf
import settings

# Deletions made here past this many, and past half the files, are held back (a guard, not a rule for daily use)
DELETE_GUARD = 20


class Report:
    """What one sync did, for the status and the command's output."""

    def __init__(self, collection):
        self.collection = collection
        self.fetched = self.sent = self.deleted_here = self.deleted_there = 0
        self.kept_both = []         # paths whose two sides were both kept
        self.revived = []           # paths deleted elsewhere but edited here: brought back
        self.skipped = {}           # path: why the Hub refused it
        self.held_deletes = 0       # deletions held back by the guard
        self.fresh = False
        self.missing = False        # the collection's folder is gone: nothing synced (Sync.run)

    def as_json(self):
        return {"collection": self.collection, "fetched": self.fetched, "sent": self.sent,
                "deleted_here": self.deleted_here, "deleted_there": self.deleted_there,
                "kept_both": self.kept_both, "revived": self.revived, "skipped": self.skipped,
                "held_deletes": self.held_deletes, "fresh": self.fresh, "missing": self.missing}

    def changed_here(self):
        return self.fetched + self.deleted_here + len(self.kept_both)


class Sync:
    def __init__(self, hub, rule, allow_deletes=False):
        self.hub, self.rule, self.allow_deletes = hub, rule, allow_deletes
        self.name = rule.name
        self.man = mf.Manifest(self.name)
        self.report = Report(self.name)

    # Files here

    def local_hash(self, path):
        return mf.file_hash(self.rule.full(path))

    def read(self, path):
        with open(self.rule.full(path), "rb") as f:
            return f.read()

    def write(self, path, data, expect):
        """Writes the Hub's content over the file here, only while the file is still as `expect` (its hash, None for
        none): an edit made since the decision (the person typing in Tasks) is kept as the other side instead."""
        now = self.local_hash(path)
        if now is not None and now != expect and now != mf.data_hash(data):
            self.keep_both(path, self.read(path))
        settings.write_atomic(self.rule.full(path), data)
        self.report.fetched += 1

    def keep_both(self, path, mine):
        new = self.rule.keep_both(path, mine)
        self.report.kept_both.append(path)
        return new

    # From the Hub

    def pull(self):
        for changes, cursor in self.hub.changes(self.name, self.man.cursor):
            for c in changes:
                self.pull_one(c)
            self.man.cursor = cursor
            self.man.save()     # page by page: a long first sync that breaks off goes on from here

    def pull_one(self, c):
        path, m = c["path"], self.man.get(c["path"])
        if not self.rule.accept(path):
            return
        if m and m["v"] >= c["version"]:
            return      # this computer's own write coming back: nothing new from elsewhere
        here = self.local_hash(path)
        if c["deleted"]:
            if here is None:
                self.man.set(path, c["version"], None)
            elif m and m["h"] == here:
                self.rule.put_away(path)
                self.report.deleted_here += 1
                self.man.set(path, c["version"], None)
            else:
                # Edited here (or never agreed on): the edit wins. Recorded as the tombstone with no content, so the
                # push sees a difference and writes it back with the tombstone's version as base.
                self.report.revived.append(path)
                self.man.set(path, c["version"], None)
            return
        if here == c["hash"]:
            self.man.set(path, c["version"], here)
            return
        st = self.hub.get(self.name, path)
        if st.deleted or st.version == 0:
            return      # deleted since the list was made: its tombstone is in a later page
        if here is not None and not (m and m["h"] == here):
            # Both sides changed (or a fresh start found two different files): the Hub's goes in place, ours beside
            self.keep_both(path, self.read(path))
        self.write(path, st.body, here)
        self.man.set(path, st.version, st.hash)

    # To the Hub

    def push(self):
        local = mf.scan(self.rule.root(), self.rule.accept)
        changed, gone = self.man.pending(local)
        for path in changed:
            for new in self.push_one(path, local[path]):
                # The other side of a conflict, kept as a file of its own (a task with a new UID): send it too
                h = self.local_hash(new)
                if h:
                    list(self.push_one(new, h))
        many = len(gone) > DELETE_GUARD and len(gone) * 2 > len(self.man.live())
        if many and not self.allow_deletes:
            self.report.held_deletes = len(gone)
            return
        for path in gone:
            self.delete_one(path)

    def push_one(self, path, h):
        """Sends one file; yields the paths of any copies a conflict made."""
        m = self.man.get(path)
        base = m["v"] if m else 0
        data = self.read(path)
        if mf.data_hash(data) != h:
            return      # changed since the scan: the next sync sends it as it is then
        for _ in range(3):
            try:
                r = self.hub.put(self.name, path, data, base, h)
            except hubclient.Conflict as e:
                st = e.state
                if st.deleted or st.version == 0:
                    # Deleted on the Hub (or a new Hub): the edit wins over the deletion
                    if m and m["h"] is not None and st.deleted:
                        self.report.revived.append(path)
                    base = st.version
                    continue
                new = self.keep_both(path, data)
                self.write(path, st.body, h)
                self.man.set(path, st.version, st.hash)
                if new:
                    yield new
                return
            except hubclient.HubError as e:
                if e.status in (400, 413):
                    # A name the Hub refuses, a path that clashes, a file too large: kept here, said in the status
                    self.report.skipped[path] = e.code
                    return
                raise
            self.man.set(path, r["version"], h)
            if r.get("changed", True):
                self.report.sent += 1
            return

    def delete_one(self, path):
        m = self.man.get(path)
        try:
            r = self.hub.delete(self.name, path, m["v"])
        except hubclient.Conflict as e:
            st = e.state
            if st.deleted:
                self.man.set(path, st.version, None)
            elif st.version == 0:
                self.man.drop(path)
            else:
                # Edited on another device since: the edit wins, it comes back here
                self.write(path, st.body, None)
                self.man.set(path, st.version, st.hash)
                self.report.revived.append(path)
            return
        if r is None:
            self.man.drop(path)
            return
        self.man.set(path, r["version"], None)
        if r.get("changed", True):
            self.report.deleted_there += 1

    def run(self, server):
        self.report.fresh = self.man.start(server)
        live = self.man.live()
        if live and not os.path.isdir(self.rule.root()):
            # The folder is gone while this computer has synced files in it: a disk not mounted, a folder moved or
            # deleted by mistake. Its deletions aren't sent, and nothing is fetched either, which would make the folder
            # again with a few files and turn the rest into deletions next time. The status says so; a person decides.
            self.report.missing = True
            self.report.held_deletes = len(live)
            return self.report
        try:
            self.pull()
            self.push()
        finally:
            self.man.save()
        return self.report
