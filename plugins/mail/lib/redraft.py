"""A reply's draft written again, not written twice (#3624): drafts.py's draft with `draft` (Claude's mail_draft).

Claude wrote the same reply three times into one thread; the copies it couldn't take back stayed in Drafts, looked
like the user's own unfinished reply, and went out too. So a reply has one draft:

- answering(msgid): the drafts in Drafts that answer a message (their parent in notmuch's reply tree, which is their
  In-Reply-To). A second reply to it is refused with their ids, and Claude writes a new version of one instead.
- A new version keeps the draft's own signature and quote (tail) and takes only the text above them, so the hidden
  parts of Claude's copy (config/mcp/mask.py) never overwrite the quote.
- The version replaced goes to the account's Trash, not away: the user's edits in it are still there, Mail leaves it
  out of the thread (order.js), and undo (drafts.py undo of the new version) brings it back (restore).
- REPLACED remembers which draft replaced which, for undo and for the writing window: an autosave of a draft that
  Claude replaced says so (compose.draft).
"""

import json
import os
import re
import subprocess

import ids

REPLACED = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "nightmail", "replaced.json")
KEEP = 100          # pairs remembered: undo is for the last few
MOVE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "move.py")
# The line a reply's quote starts with (compose.reply: "On Thu 26 Nov 2026, 10:08, Maija wrote:"), else another app's
ATTRIBUTION = re.compile(r"^(On .+ wrote:|.+ kirjoitti:?|Am .+ schrieb .+:|Le .+ a écrit :)\s*$")


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def in_drafts(m):
    names = m.get("filename") or []
    names = [names] if isinstance(names, str) else names
    return any(re.search(r"/Drafts/(cur|new)/", f) for f in names)


def tree(nodes, parent, out):
    """notmuch show's [message, replies] pairs as (message, its parent's id)."""
    for n in nodes:
        if isinstance(n, list) and len(n) == 2 and isinstance(n[0], dict) and "headers" in n[0]:
            out.append((n[0], parent))
            tree(n[1], n[0]["id"], out)
        elif isinstance(n, list):
            tree(n, parent, out)
    return out


def answering(msgid):
    """The ids of the drafts in Drafts that answer msgid, oldest first."""
    out = notmuch("show", "--format=json", "--entire-thread=true", "--body=false", "--exclude=false", "--query=sexp",
                  ids.message(msgid))
    found = [m for m, parent in tree(json.loads(out or "[]"), None, []) if parent == msgid and in_drafts(m)]
    return [m["id"] for m in sorted(found, key=lambda m: m.get("timestamp", 0))]


def tail(body, sig):
    """What follows the text in a draft: the signature and the quote below it (or the quote alone), "" if neither."""
    lines = body.split("\n")
    if sig:
        first = sig.split("\n")[0].strip()
        for i, line in enumerate(lines):
            if line.strip() == first and "\n".join(l.rstrip() for l in lines[i:]).startswith(
                    "\n".join(l.rstrip() for l in sig.split("\n"))):
                return "\n".join(lines[i:])
    for i, line in enumerate(lines):
        if ATTRIBUTION.match(line) and i + 1 < len(lines) and lines[i + 1].startswith(">"):
            return "\n".join(lines[i:])
    return ""


def rewritten(text, old_body, sig):
    """The new version's body: Claude's text, then the old draft's signature and quote as they are."""
    rest = tail(old_body, sig)
    return text.rstrip() + ("\n\n" + rest.rstrip("\n") + "\n" if rest else "\n")


def load():
    try:
        with open(REPLACED) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def remember(new, old):
    pairs = load()
    pairs[new] = old
    save(dict(list(pairs.items())[-KEEP:]))


def save(pairs):
    os.makedirs(os.path.dirname(REPLACED), exist_ok=True)
    tmp = REPLACED + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(pairs, fh)
    os.replace(tmp, REPLACED)


def replaced_by(old):
    """The draft that replaced old, if Claude wrote a new version of it."""
    return next((n for n, o in load().items() if o == old), "")


def trash(msgid, drafts_folder):
    """The version replaced, from Drafts to the account's Trash (move.py: the sync moves it on the server too)."""
    run_move("Trash", msgid, drafts_folder)


def restore(new):
    """Undo of a new version: the one it replaced back from Trash to Drafts. Returns its id, or ""."""
    pairs = load()
    old = pairs.pop(new, "")
    if old:
        run_move("Drafts", old, "Trash")
        save(pairs)
    return old


def run_move(dest, msgid, source):
    out = subprocess.run(["python3", MOVE, "--sexp", dest, ids.message(msgid), source],
                         capture_output=True, text=True, check=True).stdout
    result = json.loads(out or "{}")
    if result.get("error"):
        raise RuntimeError(result["error"])
