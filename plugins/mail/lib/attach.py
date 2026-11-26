"""The files a draft written from a terminal or by Claude's mail_draft takes as attachments (#3389).

A file attached to a draft leaves this computer: the draft syncs to the mail server's Drafts, and mail_send sends it
on (its card names the attachments). So a path keeps the rules Claude's other tools that send a file keep (Ferry's
sends, files_rules.checked with sending=True): in home, only in the folders Settings › Claude › Access › Apps and files
lets Claude use (mail_draft's options_from), wherever a link leads; nothing hidden; no hard link. Your own use from a
terminal keeps the home rules without the folders, as `nightdrive files` does. /tmp is allowed too, as Inbox's
attachments are (config/inbox/attach.py), for what a session made there (a screenshot, an export): there a file must be
the user's own, a regular file with one name, and nothing hidden.

Only files: a folder is refused, as `nightmail new` refuses one (compress it first). At most FILES_MAX of them and
TOTAL_MAX together; every path is checked before any is read, so a refused list writes no draft.
"""
import os
import stat
import sys
from pathlib import Path

# Claude's file rules are the core's (config/hypr/scripts/files_rules.py), as save.py uses them
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "config/hypr/scripts"))
from files_rules import checked, size_text  # noqa: E402

FILES_MAX = 10                    # attachments per draft, as Inbox's messages take
TOTAL_MAX = 18 * 1000 * 1000      # bytes together: base64 makes it ~24 MB, under the usual 25 MB a server takes
TMP = Path("/tmp")


def in_tmp(raw, path):
    """A path under /tmp (already resolved): the user's own regular file with one name, nothing hidden on the way."""
    rel = path.relative_to(TMP.resolve())
    if not rel.parts or any(part.startswith(".") for part in rel.parts):
        raise LookupError(f"{raw}: hidden files and files in hidden folders can't be attached")
    try:
        st = os.stat(path)
    except OSError:
        raise LookupError(f"{raw} doesn't exist") from None
    if not stat.S_ISREG(st.st_mode):
        raise LookupError(f"{raw}: only files can be attached" + (" (compress a folder first)" if stat.S_ISDIR(st.st_mode) else ""))
    # /tmp is shared: another user's file, or one with another name too (a hard link), isn't sent from here
    if st.st_uid != os.getuid():
        raise LookupError(f"{raw} isn't your own file")
    if st.st_nlink > 1:
        raise LookupError(f"{raw} is a hard link: the same file has another name too. Copy it (cp) and give the copy.")
    return path


def in_home(raw):
    """A path anywhere else: files_rules' rules (home, not hidden, Claude's folders when it is Claude), then a file."""
    path = checked(raw, sending=True)
    if path.is_dir():
        raise LookupError(f"{raw} is a folder: only files can be attached (compress it first)")
    if not path.is_file():
        raise LookupError(f"{raw}: only files can be attached")
    return path.resolve()


def files(paths):
    """The paths as resolved Paths ready to read, after the rules above; LookupError with the first that breaks one."""
    paths = [str(p) for p in paths or []]
    if len(paths) > FILES_MAX:
        raise LookupError(f"At most {FILES_MAX} attachments per message")
    out = []
    for raw in paths:
        given = Path(raw).expanduser()
        if not given.is_absolute():
            raise LookupError(f"{raw}: give an absolute path (or ~/…)")
        resolved = given.resolve()
        out.append(in_tmp(raw, resolved) if resolved.is_relative_to(TMP.resolve()) else in_home(raw))
    total = sum(p.stat().st_size for p in out)
    if total > TOTAL_MAX:
        raise LookupError(f"The attachments come to {size_text(total)}: at most {size_text(TOTAL_MAX)} go in one "
                          "message. Send big files another way (Ferry, a link).")
    return [str(p) for p in out]
