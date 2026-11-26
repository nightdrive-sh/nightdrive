"""The collections this client syncs, and each one's rule for what the sync can't settle by itself.

The Hub only carries files and refuses a write made without seeing the latest version (protocol.md); what to do then
is the app's to say, because only the app knows its files (#3391 › Ristiriidat). A rule answers these:

- root(): the folder the collection is in on this computer;
- accept(path): which files under it belong to the collection;
- merge(path, base, mine, theirs): both sides edited the file since they last agreed (base): one file with both
  sides' changes, or None when the app can't merge it; keeps_base(path) says which files it merges, so the sync
  keeps their agreed version (bases.py);
- keep_both(path, data): an edit made here lost the race to the Hub's and couldn't be merged: keep this side too,
  so nothing is lost;
- put_away(path): the file was deleted on another device: move it out of the app's sight, never unlink it.

Rule is the cautious default every app starts from: the other side of a conflict and a deleted file go to the state
folder (settings.kept_dir), where they wait for a person. An app with a better answer overrides it (tasks_rule.py).
"""
import os
import shutil
import socket
import time

import settings


def host():
    """This computer's short name, for a copy's name: which device's version it is."""
    return socket.gethostname().split(".")[0] or "this computer"


def free_path(path):
    """path itself, or path with .2, .3 … before its suffix when that name is taken: a put-aside file never replaces
    another."""
    if not os.path.lexists(path):
        return path
    stem, ext = os.path.splitext(path)
    n = 2
    while os.path.lexists("%s.%d%s" % (stem, n, ext)):
        n += 1
    return "%s.%d%s" % (stem, n, ext)


class Rule:
    name = None

    def root(self):
        raise NotImplementedError

    def accept(self, path):
        return True

    def keeps_base(self, path):
        return False

    def merge(self, path, base, mine, theirs):
        """bytes with both sides' changes, or None: then keep_both. The default merges nothing."""
        return None

    def full(self, path):
        return os.path.join(self.root(), *path.split("/"))

    def keep_both(self, path, data):
        """Keeps `data` (this computer's side) in the state folder. Returns None: no new file in the collection to
        send, the Hub's side is the one in its place."""
        stamp = time.strftime("%Y%m%d-%H%M%S")
        dest = settings.kept_dir("conflicts", self.name) / ("%s (%s %s)" % (path, host(), stamp))
        settings.write_atomic(free_path(str(dest)), data)
        return None

    def put_away(self, path):
        dest = free_path(str(settings.kept_dir("trash", self.name) / path))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.move(self.full(path), dest)
        self.tidy(path)

    def tidy(self, path):
        """Folders the file was in that are empty now go too (a list deleted elsewhere); the root stays."""
        root = os.path.realpath(self.root())
        d = os.path.dirname(os.path.realpath(self.full(path)))
        while d != root and d.startswith(root + os.sep):
            try:
                os.rmdir(d)
            except OSError:
                return      # not empty (or not ours to remove)
            d = os.path.dirname(d)


def rules():
    """{collection: rule} of the apps this computer has. Tasks only in this piece (#3395); Notes, Recorder and Inbox
    come in Hub 6 and 7."""
    import tasks_rule
    return {r.name: r for r in (tasks_rule.TasksRule(),)}
