#!/usr/bin/env python3
"""Where an account's folder syncs in ~/.config/isyncrc, and a channel of its own for one of your own folders
(folders.py) on an account that syncs each folder by a channel (Gmail, iCloud), so it reaches the server too.

An account whose channel takes every folder (`Patterns *`, `Create Both`: Runbox, Fastmail) needs nothing: mbsync
makes the new folder on the server and moves its mail there. Elsewhere Mail appends a channel after a marked comment,
and takes away only what it added, when the folder is deleted. The rest of the file is yours and stays as it is.
"""

import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from push import sections, unquote  # noqa: E402  (push.py reads the same file for its inbox watch)

PATH = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "isyncrc")
MARK = "# nightmail: your own folder "


def mail_root():
    import subprocess
    out = subprocess.run(["notmuch", "config", "get", "database.path"], capture_output=True, text=True).stdout.strip()
    return os.path.expanduser(out or "~/Mail")


def store_of(maildir, parts, root):
    """The MaildirStore whose Path is ~/Mail/<maildir>."""
    want = os.path.normpath(os.path.join(root, maildir))
    for kind, name, s in parts:
        if kind == "maildirstore" and os.path.normpath(os.path.expanduser(unquote(s.get("path", "")))) == want:
            return name
    return None


def side(value):
    """A channel's Far or Near (":store:box") as (store, box)."""
    store, _, box = unquote(value or "").strip(":").partition(":")
    return store, box


def channel_for(maildir, box, path=PATH, root=None):
    """The mbsync channel that syncs the account's folder box: "name" (a channel of that folder), "name:box" (a
    channel with Patterns * and Create Both or Far), or None (none does)."""
    if not os.path.exists(path):
        return None
    parts = sections(path)
    store = store_of(maildir, parts, root or mail_root())
    for kind, name, s in parts:
        if kind != "channel":
            continue
        near_store, near_box = side(s.get("near"))
        if near_store != store:
            continue
        if near_box == box:
            return name
        if not near_box and "*" in s.get("patterns", "").split() and \
                s.get("create", "").lower() in ("both", "far", "slave"):
            return f"{name}:{box}"
    return None


def inbox_far(maildir, parts, root):
    """The IMAPStore of the account's INBOX channel, and the IMAPAccount behind it."""
    store = store_of(maildir, parts, root)
    for kind, name, s in parts:
        if kind == "channel" and side(s.get("near"))[0] == store:
            far = side(s.get("far"))[0]
            account = next((st.get("account") for k, n, st in parts if k == "imapstore" and n == far), None)
            return store, far, account
    return store, None, None


def slug(box):
    return re.sub(r"[^a-z0-9]+", "-", box.lower()).strip("-") or "folder"


def ensure(maildir, box, path=PATH, root=None):
    """Makes the folder sync: a channel added for it when none takes it. The channel's name, or None (no isyncrc,
    or nothing to add to)."""
    if not os.path.exists(path):
        return None
    if channel_for(maildir, box, path, root):
        return None
    parts = sections(path)
    near, far, account = inbox_far(maildir, parts, root or mail_root())
    if not near or not far:
        return None
    names = {n for k, n, _ in parts if k == "channel"}
    name, n = f"{account or far}-{slug(box)}", 2
    while name in names:
        name, n = f"{account or far}-{slug(box)}-{n}", n + 1
    block = (f"\n{MARK}{maildir}/{box} (Mail added it; deleting the folder in Mail removes it)\n"
             f"Channel {name}\nFar \":{far}:{box}\"\nNear \":{near}:{box}\"\n"
             "Create Both\nExpunge Both\nSyncState *\n")
    with open(path, "a", encoding="utf-8") as f:
        f.write(block)
    return name


def far_box(maildir, box, path=PATH, root=None):
    """The folder's name on the server, and the IMAPAccount's settings (for folders.py's delete there)."""
    if not os.path.exists(path):
        return None, None
    parts = sections(path)
    channel = channel_for(maildir, box, path, root)
    if not channel:
        return None, None
    name, _, patterned = channel.partition(":")
    s = next(s for k, n, s in parts if k == "channel" and n == name)
    far_store, far = side(s.get("far"))
    account = next((st.get("account") for k, n, st in parts if k == "imapstore" and n == far_store), None)
    settings = next((dict(st, name=n) for k, n, st in parts if k == "imapaccount" and n == account), None)
    return (patterned or far), settings


def remove(maildir, box, path=PATH):
    """Takes away the channel ensure() added for the folder, and nothing else. True if there was one."""
    if not os.path.exists(path):
        return False
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    head = f"{MARK}{maildir}/{box} "
    try:
        start = next(i for i, line in enumerate(lines) if line.startswith(head))
    except StopIteration:
        return False
    end = start + 1
    while end < len(lines) and lines[end].strip():
        end += 1
    if start > 0 and not lines[start - 1].strip():
        start -= 1          # the blank line ensure() put before it
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines[:start] + lines[end:]))
    return True
