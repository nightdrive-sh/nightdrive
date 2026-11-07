#!/usr/bin/env python3
"""A message's attachments, or the message as a PDF, saved into a folder (#2291): Claude's mail_save_attachments and
mail_save_pdf (mcp.json) run these, and they work from the terminal too (`nightmail save-attachments`, `save-pdf`).

    save.py attachments [--into FOLDER] [--check] -- ID [NAME …]
                                   the attachments (only those NAMEs, as mail_thread lists them; default all)
    save.py pdf [--into FOLDER] [--check] -- ID
                                   the message as a PDF, as pdf.py draws it
    save.py unsave -- PATH SHA256 [PATH SHA256 …]
                                   the undo: each file to the trash, while it is still the file that was saved

Output: {saved: [paths], back: [path, sha256, …] (unsave's arguments), what, into}. --check saves nothing and prints
what the confirmation card shows. Failures go to stderr with exit status 1.

The rules, for Claude and the terminal alike, but where they say Claude:
- A copy only: the mail isn't changed, not even marked read. Nothing is overwritten: a name already in the folder
  gets " (2)", " (3)" … (created exclusively, so not even a file that appears meanwhile is). All or none: a save that
  fails halfway removes what it wrote.
- Into a folder in home, which must exist (default: Downloads): files_rules.destination, as Claude's files_move keeps
  it: not hidden, not ~/Mail, ~/Notes, ~/Projects, a mail folder or a git repository, and for Claude only in the
  folders Settings › Claude › Access › Apps and files lets it use (options_from), wherever a link leads.
- Clean names (clean_name): a stranger names an attachment, and the subject a PDF is named by. Only the last part of
  a path, no control or invisible characters (a right-to-left override makes "txt.exe" read as "exe.txt"), nothing
  hidden or option-like at the start, at most NAME_BYTES. Files are written 0644: nothing saved can be run.
- For Claude, the mail Access › Mail keeps from it (blocked.py) is as if it weren't there.
"""

import argparse
import email
import email.policy
import hashlib
import json
import os
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

import blocked
import ids
import parts

# Claude's file rules are the core's (config/hypr/scripts/files_rules.py): the same folders, the same no-go places
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "config/hypr/scripts"))
from files_rules import checked, destination, die, inside_home, shown, size_text  # noqa: E402

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
    raise OSError(f"{shown(folder / name)} and {TRIES - 1} numbered names after it are taken")


def message(ident):
    """A message's id, checked: exactly one message, and not one Access › Mail keeps from Claude."""
    ids.one(ident, threads=False)
    block = blocked.query(blocked.entries())
    if block and blocked.among([ident], block):
        raise LookupError(f"No message {ident} (it may have been deleted, or not synced yet)")
    return ident


def parsed(mid):
    return email.message_from_bytes(parts.raw(mid), policy=email.policy.default)


def attachments(mid):
    """The message's attachments as mail_thread lists them (browse.files): [(part, name, encoded size)]."""
    out = subprocess.run(["notmuch", "show", "--format=json", "--entire-thread=false", "--exclude=false",
                          "--query=sexp", ids.message(mid)], capture_output=True, text=True, check=True).stdout
    found = []

    def walk(node):
        if isinstance(node, list):
            for n in node:
                walk(n)
        elif isinstance(node, dict):
            if "body" in node:
                walk(node["body"])
                return
            content = node.get("content")
            if isinstance(content, list):
                walk(content)
            elif node.get("content-disposition") == "attachment" or node.get("filename"):
                found.append((str(node["id"]), node.get("filename", ""), node.get("content-length", 0)))
    walk(json.loads(out or "[]"))
    return found


def chosen(mid, names):
    found = attachments(mid)
    if not found:
        raise LookupError(f"Message {mid} has no attachments")
    if not names:
        return found
    have = {n for _, n, _ in found}
    missing = [n for n in names if n not in have]
    if missing:
        raise LookupError(f"Message {mid} has no attachment {missing[0]!r}; it has: " + ", ".join(sorted(have)))
    return [f for f in found if f[1] in set(names)]


def into(folder):
    """The folder to save in, by destination()'s rules (it must exist)."""
    path, _ = destination(folder or parts.downloads(), new=False)
    return path


def card(subject, lines, folder):
    print(json.dumps({"From the message": subject or "(no subject)", "Save": "\n".join(lines), "Into": shown(folder)},
                     ensure_ascii=False))


def saved(paths, what, folder):
    back = [x for p in paths for x in (str(p), hashlib.sha256(p.read_bytes()).hexdigest())]
    print(json.dumps({"saved": [str(p) for p in paths], "back": back, "what": what, "into": shown(folder)},
                     ensure_ascii=False))


def write_all(folder, files):
    """Each (name, data) as a new file: all or none."""
    done = []
    try:
        for name, data in files:
            done.append(create(folder, name, data))
    except OSError as e:
        for p in done:
            p.unlink(missing_ok=True)
        die(f"Nothing was saved: {getattr(e, 'strerror', None) or e}.")
    return done


def cmd_attachments(a):
    mid = message(a.id)
    picked = chosen(mid, a.names)
    folder = into(a.into)
    # As decoded, which is what is written: notmuch's content-length is the encoded size, and none for a text part
    files = [(clean_name(n), parts.raw(mid, part)) for part, n, _ in picked]
    if a.check:
        card(parsed(mid).get("Subject", ""), [f"{n}  ({size_text(len(d))})" for n, d in files], folder)
        return
    paths = write_all(folder, files)
    saved(paths, paths[0].name if len(paths) == 1 else f"{len(paths)} attachments", folder)


def cmd_pdf(a):
    import pdf   # here: only a PDF needs Chromium's page
    mid = message(a.id)
    msg = parsed(mid)
    folder = into(a.into)
    name = clean_name(msg.get("Subject", ""), "message", title=True) + ".pdf"
    if a.check:
        card(msg.get("Subject", ""), [name + "  (remote images and links aren't loaded)"], folder)
        return
    paths = write_all(folder, [(name, pdf.render(pdf.document(msg)))])
    saved(paths, paths[0].name, folder)


def cmd_unsave(a):
    """Undo: each saved file to the desktop's trash, by the rules a trash keeps (files_rules.checked), and only while
    it is the file that was saved: one the user has changed since stays, and is named."""
    pairs = a.back
    if not pairs or len(pairs) % 2:
        die("unsave takes PATH SHA256 pairs.")
    trashed, kept = [], []
    for arg, sha in zip(pairs[::2], pairs[1::2]):
        path = Path(arg)
        if not path.is_absolute() or not inside_home(path) or not os.path.lexists(path):
            kept.append(arg)   # gone already, or not a path a save makes: nothing to take back
            continue
        path = checked(arg, moving=True)
        if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            kept.append(arg)
            continue
        subprocess.run(["gio", "trash", "--", str(path)], check=True, capture_output=True)
        trashed.append(str(path))
    print(json.dumps({"trashed": trashed, "kept": kept,
                      **({"note": "Kept: changed since it was saved, or not there."} if kept else {})},
                     ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser(prog="nightmail save-attachments|save-pdf|unsave")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("attachments", "pdf"):
        p = sub.add_parser(name)
        p.add_argument("--into", default="")
        p.add_argument("--check", action="store_true")
        p.add_argument("id")
        if name == "attachments":
            p.add_argument("names", nargs="*")
    sub.add_parser("unsave").add_argument("back", nargs="*")
    a = ap.parse_args()
    {"attachments": cmd_attachments, "pdf": cmd_pdf, "unsave": cmd_unsave}[a.cmd](a)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        err = e.stderr.decode(errors="replace") if isinstance(e.stderr, bytes) else (e.stderr or "")
        sys.exit(f"{e.cmd[0]} failed: {err.strip() or e.returncode}")
    except (LookupError, ValueError, OSError) as e:
        sys.exit(str(e))
