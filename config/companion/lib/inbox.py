"""Nightdrive Inbox in Companion (#3187): the messages the computer's Inbox keeps (config/inbox, docs/inbox.md), read
and changed through its own command's --json, so the window, Claude's tools and Companion agree on one store and its
rules. Nothing here writes the store itself.

The state carries only the unread count and a stamp that changes with any message (state()): the page fetches the
list and a message whole when its view is open (protocol.md › Inbox). The stamp costs a few stats a look, and the
command runs only when it changes, not every POLL.

Buttons (open, run, session, task) and push are later work (#3187's follow-ups): this shows, marks read and archives.
"""
import json
import mimetypes
import os
import re
import subprocess
import sys
import zlib
from urllib.parse import quote

CLI = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__)))), "inbox", "cli.py")
TIMEOUT = 15        # seconds a command may take: a list reads a few dozen small JSON files
LIMIT = 100         # messages a list gives: the newest; the window has the rest
ID = re.compile(r"^\d{8}-\d{6}-[0-9a-f]{4}$")    # store.py's: nothing else reaches the command
WEB = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "web")


class InboxError(ValueError):
    """The command said no (an id that isn't there): the page shows the reason."""


def message_id(mid):
    if not isinstance(mid, str) or not ID.match(mid):
        raise InboxError("No such message")
    return mid


def root():
    data = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local/share")
    return os.path.join(data, "nightdrive", "inbox")


def run(*args):
    """The inbox command with --json; its answer, or InboxError with what it printed."""
    p = subprocess.run([sys.executable, CLI, *args, "--json"], capture_output=True, text=True, timeout=TIMEOUT)
    if p.returncode:
        raise InboxError((p.stderr.strip() or "Inbox didn't answer").removeprefix("inbox: "))
    return json.loads(p.stdout or "null")


def public(msg):
    """A message for the page: its files as this server's addresses, not the computer's paths."""
    out = {k: v for k, v in msg.items() if k not in ("folder", "from")}
    files = msg.get("attachments")
    # a list row has the count of its files, a message shown whole the files themselves
    out["attachments"] = [{"name": f["name"], "type": f.get("type") or "", "size": f.get("size") or 0,
                           "url": f"/api/inbox/{msg['id']}/files/{quote(f['name'])}"}
                          for f in files if isinstance(f, dict) and f.get("name")] \
        if isinstance(files, list) else int(files or 0)
    if isinstance(msg.get("actions"), list):
        out["actions"] = len(msg["actions"])
    return out


class Inbox:
    def __init__(self):
        self.sig = None
        self.counts = {"unread": 0, "total": 0}

    def stamp(self):
        """Every message's message.json, its name, time and size: a read, an archive or a new one changes it."""
        parts = []
        try:
            with os.scandir(root()) as it:
                for e in it:
                    try:
                        st = os.stat(os.path.join(e.path, "message.json"))
                    except OSError:
                        continue
                    parts.append(f"{e.name}:{st.st_mtime_ns}:{st.st_size}")
        except OSError:
            pass
        return format(zlib.crc32("|".join(sorted(parts)).encode()), "08x")

    def state(self):
        sig = self.stamp()
        if sig != self.sig:
            try:
                got = run("count")
                self.counts = {"unread": int(got.get("unread") or 0), "total": int(got.get("total") or 0)}
                self.sig = sig
            except (InboxError, OSError, subprocess.SubprocessError, ValueError, AttributeError):
                pass    # the last count stays; the next look tries again
        return {**self.counts, "stamp": self.sig or ""}

    def list(self):
        got = run("list", "--limit", str(LIMIT))
        return {"messages": [public(m) for m in got.get("messages") or []], "total": got.get("total", 0),
                "unread": got.get("unread", 0)}

    def show(self, mid, mark_read=False):
        args = ["show", message_id(mid)] + (["--mark-read"] if mark_read else [])
        return public(run(*args))

    def file(self, mid, name):
        """A file of the message: (path, type), only one it lists, read from its own folder."""
        msg = run("show", message_id(mid))
        for f in msg.get("attachments") or []:
            if f.get("name") == name and f.get("path"):
                path = os.path.realpath(f["path"])
                folder = os.path.realpath(msg.get("folder") or "")
                if folder and path.startswith(folder + os.sep) and os.path.isfile(path):
                    return path, f.get("type") or mimetypes.guess_type(name)[0] or "application/octet-stream"
        raise InboxError("No such file")

    def read(self, mid, unread=False):
        run("read", message_id(mid), *(["--unread"] if unread else []))

    def archive(self, mid, undo=False):
        run("archive", message_id(mid), *(["--undo"] if undo else []))


DEMO = [
    {"id": "20261120-101500-a3f1", "title": "Companion: the Inbox view, have a look", "at": "2026-11-20T10:15:00+02:00",
     "task": 3187, "body": "The Inbox is in Companion now:\n\n- the messages, **newest first**\n- read and archive\n\n"
     "| Size | Layout |\n| --- | --- |\n| iPhone | the list, a message over it |\n| iPad | both side by side |",
     "sender": {"short": "#3187 Companion inbox", "label": "#3187 Companion inbox · dotfiles"},
     "files": [("icon.png", "image/png")]},
    {"id": "20261120-091000-0c2d", "title": "Deck: the night's backup finished", "at": "2026-11-20T09:10:00+02:00",
     "body": "4 812 songs, 0 errors.", "sender": {"short": "Deck", "label": "Deck"}, "files": []},
    {"id": "20261119-213000-7e88", "title": "Cold Start: new menus to try", "at": "2026-11-19T21:30:00+02:00",
     "read": "2026-11-19T22:00:00+02:00", "task": 2741, "body": "Start the game and open the pause menu.",
     "sender": {"short": "#2741 menus", "label": "#2741 menus · cold-start"}, "files": [("logo.svg", "image/svg+xml")]},
]


class Demo(Inbox):
    """Made-up messages kept in memory (companion demo): read and archive work on them, nothing on the disk changes."""

    def __init__(self):
        super().__init__()
        self.msgs = [{"read": None, "task": None, "archived": False, "actions": 0, **m,
                      "attachments": [{"name": n, "type": t, "size": 0} for n, t in m["files"]]} for m in DEMO]

    def _find(self, mid):
        m = next((m for m in self.msgs if m["id"] == message_id(mid)), None)
        if not m:
            raise InboxError("No such message")
        return m

    def state(self):
        live = [m for m in self.msgs if not m["archived"]]
        stamp = "|".join(f"{m['id']}{m['read']}{m['archived']}" for m in self.msgs)
        return {"unread": sum(1 for m in live if not m["read"]), "total": len(live),
                "stamp": format(zlib.crc32(stamp.encode()), "08x")}

    def list(self):
        live = [{k: v for k, v in m.items() if k not in ("body", "files")} for m in self.msgs if not m["archived"]]
        return {"messages": [public({**m, "attachments": len(m["attachments"])}) for m in live],
                "total": len(live), "unread": sum(1 for m in live if not m["read"])}

    def show(self, mid, mark_read=False):
        m = self._find(mid)
        if mark_read and not m["read"]:
            m["read"] = "2026-11-20T12:00:00+02:00"
        return public({k: v for k, v in m.items() if k != "files"})

    def file(self, mid, name):
        if not any(f["name"] == name for f in self._find(mid)["attachments"]):
            raise InboxError("No such file")
        return os.path.join(WEB, name), mimetypes.guess_type(name)[0] or "application/octet-stream"

    def read(self, mid, unread=False):
        self._find(mid)["read"] = None if unread else "2026-11-20T12:00:00+02:00"

    def archive(self, mid, undo=False):
        self._find(mid)["archived"] = not undo
