#!/usr/bin/env python3
"""`nightdrive backup`'s settings and state (docs/backup.md). Each machine backs up its own disk, so both stay on it
(docs/sync.md › What stays with each machine).

~/.config/nightdrive/backup.conf, `key = value` lines as the apps' .conf files have them:

    repository = sftp:storage-backup:/feature-dev      restic's repository (sftp:, s3:, b2:, rclone:, rest: or a path)
    password-cmd = secret-tool lookup service nightdrive-backup repository sftp:storage-backup:/feature-dev
    path = ~                                           what to back up; a line each, ~ for the home folder
    keep-daily = 7                                     the snapshots kept (keep-weekly, keep-monthly, keep-yearly)

The password comes from a command and never sits in a file: the keyring's by default, or a password manager's
(`op read op://…`). ~/.config/nightdrive/backup-excludes.txt is restic's --exclude-file, written from
config/backup/excludes.txt the first time.
"""
import json
import os
import shlex
import tempfile
import time
from pathlib import Path

HOME = Path.home()
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "nightdrive"
CONF = CONFIG_DIR / "backup.conf"
EXCLUDES = CONFIG_DIR / "backup-excludes.txt"
EXCLUDES_DEFAULT = Path(__file__).resolve().parent.parent / "excludes.txt"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "nightdrive" / "backup"
STATUS = STATE_DIR / "status.json"

# The keyring entry's attributes: one password per repository
KEYRING_SERVICE = "nightdrive-backup"
# What is kept after each prune, unless backup.conf says otherwise: a week of days, two months of weeks, two years of
# months, and a snapshot a year for ten years
KEEP = {"keep-daily": 7, "keep-weekly": 8, "keep-monthly": 24, "keep-yearly": 10}
LIST_KEYS = ("path",)
KEYS = ("repository", "password-cmd") + LIST_KEYS + tuple(KEEP)


def keyring_cmd(repository):
    return "secret-tool lookup service %s repository %s" % (KEYRING_SERVICE, shlex.quote(repository))


def parse(text):
    """{key: value} from backup.conf's text, `path` as a list. An unknown key is an error: a typo would otherwise
    leave a folder out of every backup without a word."""
    out = {"path": []}
    for n, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        key, sep, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if not sep or key not in KEYS:
            raise ValueError("backup.conf line %d: %r is not a setting (%s)" % (n, line, ", ".join(KEYS)))
        if key in LIST_KEYS:
            out[key].append(value)
        elif key in KEEP:
            if not value.isdigit():
                raise ValueError("backup.conf line %d: %s takes a number" % (n, key))
            out[key] = int(value)
        else:
            out[key] = value
    return out


def load(path=None):
    """The settings, defaults filled in, or None without a backup.conf (backup not set up)."""
    path = Path(path or CONF)
    try:
        cfg = parse(path.read_text())
    except FileNotFoundError:
        return None
    if not cfg.get("repository"):
        raise ValueError("backup.conf has no repository (nightdrive backup setup REPOSITORY)")
    for key, n in KEEP.items():
        cfg.setdefault(key, n)
    cfg.setdefault("password-cmd", keyring_cmd(cfg["repository"]))
    cfg["path"] = [str(Path(p).expanduser()) for p in cfg["path"] or ["~"]]
    return cfg


def render(repository, paths, password_cmd=None):
    """backup.conf's text for a new setup."""
    lines = ["# nightdrive backup (docs/backup.md). This machine's own: it isn't synced.",
             "repository = " + repository,
             "password-cmd = " + (password_cmd or keyring_cmd(repository))]
    lines += ["path = " + p for p in paths or ["~"]]
    lines += ["%s = %d" % kv for kv in KEEP.items()]
    return "\n".join(lines) + "\n"


def save(text, path=None):
    write_atomic(Path(path or CONF), text)


def ensure_excludes(path=None):
    """The excludes file, from the default the first time; the person's own edits are never overwritten."""
    path = Path(path or EXCLUDES)
    if not path.exists():
        write_atomic(path, EXCLUDES_DEFAULT.read_text())
    return path


def read_status():
    try:
        return json.loads(STATUS.read_text())
    except (FileNotFoundError, ValueError):
        return {}


def write_status(status):
    write_atomic(STATUS, json.dumps(status, indent=1) + "\n")


def write_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix="." + path.name)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def age_hours(stamp, at=None):
    """Hours since a status timestamp, None for never."""
    if not stamp:
        return None
    then = time.mktime(time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S"))
    return ((at or time.time()) - then) / 3600
