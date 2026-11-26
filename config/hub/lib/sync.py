"""One sync of one collection: first what changed on the Hub, then what changed here (#3391 › Malli).

Every decision compares three things for a path: the file here now, the Hub's version, and the manifest (what both
last agreed on, manifest.py). The rules, in short:

- Nothing is deleted because it is missing. A file here that the Hub doesn't have is sent; a file on the Hub that
  isn't here is fetched, unless the manifest says this computer had it and deleted it. Only a tombstone deletes here,
  and only a file unchanged since the last agreement.
- A deletion never wins over an edit: an edited file comes back over a tombstone (written with the tombstone's version
  as base), and a deletion the Hub refuses because of an edit fetches the edit.
- Both sides edited: the app's rule merges them from the version both last agreed on, which the client keeps for it
  (bases.py); when it can't, it keeps both (apps.py).
- A fresh start (the first sync, another Hub, or this Hub restored from a backup: manifest.start) has no agreement with
  the Hub to go by, so it only adds and merges: identical files match by hash, nothing is deleted on either side, and
  what this computer agreed on before tells which side is newer (fresh.py); only when it can't, both are merged or kept.
- Many files gone here at once (emptied by mistake) aren't sent as deletions unless asked: `--allow-deletes`. A folder
  gone altogether (a disk not mounted) stops the collection's sync until it is back.

A crash at any point is safe to sync again: a write the Hub already has answers "changed: false", and a file fetched
but not yet in the manifest matches by hash next time.
"""
import os

import bases as hubbases
import client as hubclient
import fresh
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
        self.merged = []            # paths whose two sides were merged into one
        self.revived = []           # paths deleted elsewhere but edited here: brought back
        self.skipped = {}           # path: why the Hub refused it
        self.held_deletes = 0       # deletions held back by the guard
        self.fresh = False
        self.missing = False        # the collection's folder is gone: nothing synced (Sync.run)

    def as_json(self):
        return {"collection": self.collection, "fetched": self.fetched, "sent": self.sent,
                "deleted_here": self.deleted_here, "deleted_there": self.deleted_there,
                "kept_both": self.kept_both, "merged": self.merged, "revived": self.revived, "skipped": self.skipped,
                "held_deletes": self.held_deletes, "fresh": self.fresh, "missing": self.missing}

    def changed_here(self):
        return self.fetched + self.deleted_here + len(self.kept_both)


class Sync:
    def __init__(self, hub, rule, allow_deletes=False):
        self.hub, self.rule, self.allow_deletes = hub, rule, allow_deletes
        self.name = rule.name
        self.man = mf.Manifest(self.name)
        self.bases = hubbases.Bases(self.name, rule)
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
            data, _ = self.settle(path, self.read(path), data)
        settings.write_atomic(self.rule.full(path), data)
        self.report.fetched += 1

    def keep_both(self, path, mine):
        new = self.rule.keep_both(path, mine)
        self.report.kept_both.append(path)
        return new

    def settle(self, path, mine, theirs):
        """Both sides changed path since they last agreed: (content to put in place, copy or None). Merged when the
        rule can, from the agreed version (so call it before the manifest moves on; after a fresh start, the agreement
        from before it); else the rule keeps this side aside (a copy's path when it made one in the collection) and
        the Hub's goes in place."""
        m = self.man.get(path)
        base = self.bases.get(path, m["h"] if m else self.man.ancestor(path))
        merged = self.rule.merge(path, base, mine, theirs) if base is not None else None
        if merged is not None:
            if path not in self.report.merged:
                self.report.merged.append(path)
            return merged, None
        return theirs, self.keep_both(path, mine)

    def agreed(self, path, version, hash_, data=None):
        """The manifest's agreement on path, with its content kept as the base of a later merge (hash_ None: deleted)."""
        self.man.set(path, version, hash_)
        if hash_ is None:
            self.bases.drop(path)
        elif data is not None:
            self.bases.put(path, data)

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
                self.agreed(path, c["version"], None)
            elif m and m["h"] == here:
                self.rule.put_away(path)
                self.report.deleted_here += 1
                self.agreed(path, c["version"], None)
            else:
                # Edited here (or never agreed on): the edit wins. Recorded as the tombstone with no content, so the
                # push sees a difference and writes it back with the tombstone's version as base.
                self.report.revived.append(path)
                self.agreed(path, c["version"], None)
            return
        if here == c["hash"]:
            self.man.set(path, c["version"], here)      # its base is kept by bases.fill, in the push
            return
        way = None
        if here is not None and not m:
            # No agreement with this Hub (a fresh start): which side is newer, if the entry from before can tell
            way = fresh.choose(self.man.before.get(path), here, c["hash"])
            if way == fresh.OURS:
                # The Hub's copy is old: agreed at its version, so the push sends this computer's with it as base
                self.man.set(path, c["version"], c["hash"])
                return
        st = self.hub.get(self.name, path)
        if st.deleted or st.version == 0:
            return      # deleted since the list was made: its tombstone is in a later page
        data = st.body
        if here is not None and not (m and m["h"] == here) and way != fresh.HUBS:
            # Both sides changed (or a fresh start found two different files): merged, or the Hub's in place and ours
            # beside. A merge differs from the Hub's, so the push sends it in this same sync.
            data, _ = self.settle(path, self.read(path), st.body)
        self.write(path, data, here)
        self.agreed(path, st.version, st.hash, st.body)

    # To the Hub

    def push(self):
        local = mf.scan(self.rule.root(), self.rule.accept)
        self.bases.fill(self.man, local, self.read)
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
                merged, new = self.settle(path, data, st.body)
                self.write(path, merged, h)
                self.agreed(path, st.version, st.hash, st.body)
                if new:
                    yield new
                if new is not None or merged == st.body:
                    return
                # Merged: sent on the Hub's version, as the file is now (write may have merged an edit made meanwhile)
                data = self.read(path)
                h, base = mf.data_hash(data), st.version
                if h == st.hash:
                    return
                continue
            except hubclient.HubError as e:
                if e.status in (400, 413):
                    # A name the Hub refuses, a path that clashes, a file too large: kept here, said in the status
                    self.report.skipped[path] = e.code
                    return
                raise
            self.agreed(path, r["version"], h, data)
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
                self.agreed(path, st.version, None)
            elif st.version == 0:
                self.man.drop(path)
                self.bases.drop(path)
            else:
                # Edited on another device since: the edit wins, it comes back here
                self.write(path, st.body, None)
                self.agreed(path, st.version, st.hash, st.body)
                self.report.revived.append(path)
            return
        if r is None:
            self.man.drop(path)
            self.bases.drop(path)
            return
        self.agreed(path, r["version"], None)
        if r.get("changed", True):
            self.report.deleted_there += 1

    def run(self, server, newest=None):
        """One sync. `newest` is the Hub's newest version in the collection (protocol.md › Collections): one older
        than a version this computer has seen means the Hub went back (put back from a copy), and it starts fresh."""
        self.report.fresh = self.man.start(server, newest)
        live = self.man.live() or self.man.before
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
            self.man.finish()
        finally:
            self.man.save()
        return self.report
