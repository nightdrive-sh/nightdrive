"""A message's attachments: files a sender hands over (a screenshot, a diff, a build), copied into the message's folder
so they stay as they were sent, after /tmp is emptied or the project has moved on (#3132).

What may be attached is kept narrow on purpose. A session that has read something hostile (a web page, a mail) could
be talked into "attaching" a key or a password file, and the inbox is what Companion will show on another device. So:
only regular files under home or /tmp, nothing in a hidden folder or hidden itself (~/.ssh, ~/.config, .env), at most
FILES_MAX of them and SIZE_MAX each. Every one is checked before any is copied, so a refused list leaves nothing behind.
"""
import mimetypes
import os
import shutil
from pathlib import Path

from store import InboxError

FILES_MAX = 10                  # attachments per message
SIZE_MAX = 25 * 1024 * 1024     # bytes per attachment: screenshots and short clips, not disk images
ROOTS = (Path.home(), Path("/tmp"))
NAME_MAX = 120                  # characters of a file name kept


def checked(paths, base, already=0):
    """The paths as resolved Paths, after the rules above (a relative one from base, the sender's folder);
    InboxError with the first that breaks one."""
    if already + len(paths) > FILES_MAX:
        raise InboxError(f"at most {FILES_MAX} attachments per message")
    out = []
    for raw in paths:
        given = Path(os.path.expanduser(str(raw)))
        if not given.is_absolute():
            given = Path(base) / given
        path = given.resolve()   # a link counts where it points
        if not any(path.is_relative_to(r.resolve()) for r in ROOTS):
            raise InboxError(f"{raw}: only files in your home folder or /tmp can be attached")
        rel = path.relative_to(next(r.resolve() for r in ROOTS if path.is_relative_to(r.resolve())))
        if any(part.startswith(".") for part in rel.parts):
            raise InboxError(f"{raw}: hidden files and files in hidden folders can't be attached")
        if not path.is_file():
            raise InboxError(f"{raw}: not a file" + ("" if path.exists() else " (it doesn't exist)"))
        if path.stat().st_size > SIZE_MAX:
            raise InboxError(f"{raw}: larger than {SIZE_MAX // (1024 * 1024)} MB")
        out.append(path)
    return out


def free_name(dest, name, taken):
    """name, or name-2.ext, name-3.ext… when the message already has a file of that name."""
    name = name[-NAME_MAX:].lstrip(".") or "file"
    stem, ext = os.path.splitext(name)
    candidate, n = name, 2
    while candidate in taken or candidate in ("message.json", "history") or (dest / candidate).exists():
        candidate, n = f"{stem}-{n}{ext}", n + 1
    return candidate


def copier(paths):
    """attach(dest, existing) for store.create/update: copies the checked files in, returns every attachment entry."""
    def attach(dest, existing):
        entries = list(existing)
        taken = {a["name"] for a in entries}
        for path in paths:
            name = free_name(dest, path.name, taken)
            shutil.copyfile(path, dest / name)
            taken.add(name)
            entries.append({"name": name, "type": mimetypes.guess_type(name)[0] or "application/octet-stream",
                            "size": path.stat().st_size})
        return entries
    return attach
