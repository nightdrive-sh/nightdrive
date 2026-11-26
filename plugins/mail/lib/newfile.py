#!/usr/bin/env python3
"""New files from a message, under the names a stranger gave them (#2291, #3627): Mail's own Save and Save all
(parts.py) and Claude's mail_save_attachments and mail_save_pdf (save.py) name and write them the same way.

- Clean names (clean_name): only the last part of a path, no control or invisible characters (a right-to-left
  override makes "txt.exe" read as "exe.txt"), nothing hidden or option-like at the start, at most NAME_BYTES.
- Nothing is overwritten: a name already in the folder gets " (2)", " (3)" … (created exclusively, so not even a
  file that appears meanwhile is). Files are written 0644: nothing saved can be run.
- All or none (write_all): a save that fails halfway removes what it wrote.
"""

import os
import re
import unicodedata
from pathlib import Path

NAME_BYTES = 200        # of a name we make: under the file system's 255, with room for " (99)"
EXT_BYTES = 16          # an extension longer than this isn't one worth keeping whole when a name is cut
TRIES = 100             # names tried for a free one: "name (2)" … "name (100)"
FALLBACK = "attachment"


def clean_name(name, fallback=FALLBACK, title=False):
    """A file name a stranger gave, made safe to save under. title: a subject, whose slashes are words' ("Invoice /
    November"), not a path's: they become dashes."""
    name = unicodedata.normalize("NFC", str(name or ""))
    if title:
        name = re.sub(r"\s*[/\\]+\s*", " - ", name)
    name = re.split(r"[/\\]", name)[-1]        # a path's last part: no ../ out of the folder
    # Whitespace as one space; other control, format (bidi overrides, zero-width), private and unassigned characters out
    name = "".join(" " if c.isspace() else c for c in name if c.isspace() or unicodedata.category(c)[0] != "C")
    name = re.sub(r" {2,}", " ", name)
    # Not hidden (a leading dot), not read as an option (-) or home (~); no trailing dots, spaces or dashes
    name = re.sub(r"^[\s.\-~]+|[\s.\-]+$", "", name)
    if not name:
        return fallback
    stem, ext = os.path.splitext(name)
    if len(ext.encode()) > EXT_BYTES:
        stem, ext = name, ""
    while len((stem + ext).encode()) > NAME_BYTES:
        stem = stem[:-1]
    return (stem.rstrip(" .") or fallback) + ext


def create(folder, name, data):
    """Writes data as a new file in folder under name, or the first free "name (N)"; returns its path."""
    stem, ext = os.path.splitext(name)
    for n in range(1, TRIES + 1):
        path = folder / (name if n == 1 else f"{stem} ({n}){ext}")
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o644)
        except FileExistsError:
            continue
        try:
            with os.fdopen(fd, "wb") as fh:
                fh.write(data)
        except OSError:
            path.unlink(missing_ok=True)
            raise
        return path
    raise OSError(f"{name} and {TRIES - 1} numbered names after it are taken")


def write_all(folder, files):
    """Each (name, data) as a new file in folder: all or none. Returns their paths; an OSError leaves nothing."""
    folder, done = Path(folder), []
    try:
        for name, data in files:
            done.append(create(folder, name, data))
    except OSError:
        for p in done:
            p.unlink(missing_ok=True)
        raise
    return done
