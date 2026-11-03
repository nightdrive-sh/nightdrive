"""A note's new title (`notes rename`, the window's Rename and Claude's notes_rename), and its undo (`notes unrename`);
and refile, the file following a title changed in the window.

The title is the note's first heading, so that is what changes: the heading's text, its level kept, or, in a note that
doesn't start with one, a "# Title" put above it. The file follows the title as a new note's does (store.new_path), in
the same folder, so Files, Apostrophe and a sync see the name the note has.

The new text goes to the new name first, then the old name goes: a crash in between leaves the note twice, never not at
all. The output has what unrename needs to put it back exactly as it was: the old id, the old heading line ("" when
there was none) and the MD5 of the text it wrote, so an edit made since is never undone with it.
"""

import os
import re
import tempfile
from contextlib import contextmanager

import store
from store import NoteError

HEADING = re.compile(r"(#{1,6})[ \t]+.*")


def split_head(text):
    """(what is before the heading, the heading line without its \\r, whether it had one, the rest after its line): the
    heading is the first line that isn't blank, if it is one; else the heading is "" and the rest is the whole text."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.strip():
            bare = line.rstrip("\r")
            if HEADING.fullmatch(bare):
                return "\n".join(lines[:i]) + ("\n" if i else ""), bare, bare != line, "\n".join(lines[i + 1:])
            break
    return "", "", False, text


def with_head(text, head):
    """The text with head as its heading line ("" takes off the heading titled() added, and the blank line under it)."""
    lead, old, cr, rest = split_head(text)
    if not old:
        return f"{head}\n\n{text}" if text.strip() else f"{head}\n"
    if not head:
        return rest[1:] if rest.startswith("\n") else rest
    return f"{lead}{head}{chr(13) if cr else ''}\n{rest}"


def titled(text, title):
    """The text with title as its heading, its level kept; and the old heading line, "" when there was none."""
    old = split_head(text)[1]
    level = HEADING.fullmatch(old).group(1) if old else "#"
    return with_head(text, f"{level} {title}"), old


@contextmanager
def staged(folder, text, mode):
    """The text in a hidden file in folder, gone again afterwards: linked to a name (os.link, which never replaces a
    file that is there) or moved over one (os.replace), it is a whole note there in one step."""
    fd, tmp = tempfile.mkstemp(prefix=".", suffix=".tmp", dir=folder)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.chmod(tmp, mode)
        yield tmp
    finally:
        if os.path.lexists(tmp):
            os.unlink(tmp)


def movable(nid):
    p = store.path_of(nid)
    if p.is_symlink():
        raise NoteError(f"{nid} is a link to a note elsewhere: rename it in Files.")
    return p


def rename(who, title):
    title = " ".join(title.split())
    if not title:
        raise NoteError("A note needs a title: give the new one.")
    p = movable(store.note_id(store.find(who)))
    old_id = store.note_id(p)
    text = p.read_bytes().decode("utf-8", "replace")
    new, head = titled(text, title)
    same_name = store.new_path(title, p.parent, keep=p) == p
    mode = p.stat().st_mode & 0o7777
    if same_name:
        if new != text:
            with staged(p.parent, new, mode) as tmp:
                os.replace(tmp, p)
        target = p
    else:
        with staged(p.parent, new, mode) as tmp:
            while True:
                target = store.new_path(title, p.parent)
                try:
                    os.link(tmp, target)
                    break
                except FileExistsError:     # made meanwhile: the next name
                    continue
        p.unlink()
    return dict(store.brief(target), old_id=old_id, old_head=head, md5=store.digest(new),
                renamed=new != text or not same_name)


def unrename(nid, old_id, old_head, expect):
    """rename's undo: the old heading line (or none) and the old name back, only while the note is still the text
    rename wrote and the old name is free."""
    p = movable(nid)
    text = p.read_bytes().decode("utf-8", "replace")
    if store.digest(text) != expect:
        raise NoteError(f"{nid} has changed since it was renamed, so it's left as it is (rename it again instead).")
    back, mode = with_head(text, old_head.rstrip("\r")), p.stat().st_mode & 0o7777
    old = store.ROOT / old_id
    if old == p:
        with staged(p.parent, back, mode) as tmp:
            os.replace(tmp, p)
        return dict(store.brief(p), restored=True)
    rel = old.relative_to(store.ROOT) if old.is_relative_to(store.ROOT) else None
    if not rel or ".." in rel.parts or not store.visible(rel) or rel.suffix != store.SUFFIX or old.parent != p.parent:
        raise NoteError(f"{old_id!r} isn't where {nid} was renamed from.")
    with staged(p.parent, back, mode) as tmp:
        try:
            os.link(tmp, old)
        except FileExistsError:
            raise NoteError(f"There's a note named {old_id} again, so {nid} keeps its name.")
    p.unlink()
    return dict(store.brief(old), restored=True)


def refile(nid, was):
    """The file named after the note's title again, its text untouched (`notes refile`: the window, on leaving a note it
    wrote in). Only when the file was named after was, the title the note had when the window began writing: a new note
    ("Untitled.md") or one whose name followed its title. A file named otherwise keeps its name, and so does a note
    without a heading (its title is then its file name already). The same way as rename: the new name is linked first,
    then the old one goes, never over another file."""
    p = movable(nid)
    title = store.title_of(p)
    if not store.named_after(p, was) or store.new_path(title, p.parent, keep=p) == p:
        return dict(store.brief(p), old_id=nid, renamed=False)
    while True:
        target = store.new_path(title, p.parent)
        try:
            os.link(p, target)
            break
        except FileExistsError:     # made meanwhile: the next name
            continue
    p.unlink()
    return dict(store.brief(target), old_id=nid, renamed=True)
