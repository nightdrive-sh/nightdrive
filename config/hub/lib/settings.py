"""Where the Hub client keeps what it knows, and the small helpers to keep it safely.

- ~/.config/nightdrive/hub.json: the Hub this computer has joined (its URL and id). Settings, so it may later go
  with the settings sync (#3356); nothing secret is in it, as Tailscale does the signing in.
- ~/.local/state/nightdrive/hub/: this computer's own state, never synced: a manifest per collection (manifest.py),
  the last sync's status, the lock, and the files a sync put aside (a conflict's other side, a file deleted on
  another device), which are kept, never removed by the client.

The XDG variables move them all, which the tests use for a throwaway home.
"""
import fcntl
import json
import os
from pathlib import Path


def config_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "nightdrive"


def state_dir():
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "nightdrive/hub"


def config_file():
    return config_dir() / "hub.json"


def status_file():
    return state_dir() / "status.json"


def kept_dir(kind, collection):
    """Where a sync puts a file aside: kind is "conflicts" or "trash" (state_dir/<kind>/<collection>)."""
    return state_dir() / kind / collection


def write_atomic(path, data):
    """Write bytes or text through a hidden temporary file and a rename, so a reader (the Tasks window, a sync on
    another device reading this one's files) never sees half a file, and the sync's own scan skips the temporary."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(".%s.hub-tmp" % path.name)
    with open(tmp, "wb") as f:
        f.write(data.encode("utf-8") if isinstance(data, str) else data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default
    except ValueError:
        # A file cut short (a crash mid-write before write_atomic, a hand edit): start from nothing rather than fail
        # every sync. For a manifest that means the next sync is a "fresh" one, which deletes nothing (sync.py).
        return default


def write_json(path, data):
    write_atomic(path, json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True) + "\n")


def load_config():
    """{"url", "server"} of the joined Hub, or None."""
    c = read_json(config_file())
    return c if isinstance(c, dict) and c.get("url") else None


def save_config(url, server):
    write_json(config_file(), {"url": url, "server": server})


def forget_config():
    try:
        config_file().unlink()
    except FileNotFoundError:
        pass


class Busy(Exception):
    """Another sync holds the lock."""


class Lock:
    """One sync at a time on this computer: the timer's and a `nightdrive hub sync` typed meanwhile would otherwise
    both read the same manifest and both send the same change. flock is let go by the kernel if a sync dies."""

    def __enter__(self):
        state_dir().mkdir(parents=True, exist_ok=True)
        self.f = open(state_dir() / "lock", "w")
        try:
            fcntl.flock(self.f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.f.close()
            raise Busy("A sync is running already")
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()
