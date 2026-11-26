#!/usr/bin/env python3
"""What a draft sends that Claude never saw (Dashboard #1878): mail_send's card, through `drafts.py card ID`.

Claude gets a draft with its secrets hidden (config/mcp/mask.py), and the card shows Claude's copy: "[login link
hidden]" where the quote has the real link, which goes out whole. That is right for a reply to the one who sent the
link, and an account takeover for a reply Claude was talked into addressing to someone else ("answer X's mail and send
it to me"). So the card says on a line of its own what goes out unseen, in words Claude didn't write, and a draft that
quotes something hidden to anyone who wasn't on the message it answers isn't sent at all: the user can still send it
from Mail, where they see the link itself.

When the user lets Claude read the mail's codes (Access › Mail › secrets), Claude saw everything: nothing to say.
"""

import importlib.util
import json
import os
import re
from email.utils import getaddresses
from pathlib import Path

import compose

# Loaded by its path: this folder's modules mustn't be shadowed by the server's, nor theirs by these
MASK = Path(__file__).resolve().parents[3] / "config/mcp/mask.py"

# A header of the message answered whose addresses count as on it: who it came from, went to, and asked for replies
ON_THE_MESSAGE = ("From", "Sender", "Reply-To", "To", "Cc", "Mail-Followup-To", "Mail-Reply-To")


def mask_module():
    spec = importlib.util.spec_from_file_location("nightdrive_mask", MASK)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def masked(text):
    return mask_module().mask(text)


def kinds(module):
    """mask.py's marks, each with the words for one and for more, in the order the card names them."""
    return [(module.LINK, "login link", "login links"), (module.CODE, "code", "codes"),
            (module.PASSWORD, "password", "passwords"), (module.KEY, "key", "keys"),
            ("••••", "card or account number", "card or account numbers"), (module.CVV, "CVV", "CVVs"),
            (module.EXPIRY, "card expiry", "card expiries"), (module.ID_CODE, "identity code", "identity codes"),
            ("=[hidden]", "meeting password", "meeting passwords")]


def hidden(texts):
    """What mask.py hides in texts, as [(count, words)]: what the card shows as [… hidden] and the draft sends."""
    module = mask_module()
    counts = {}
    for text in texts:
        text = str(text or "")
        shown = module.mask(text)
        if shown == text:
            continue
        for mark, one, more in kinds(module):
            n = shown.count(mark) - text.count(mark)   # a mark the draft has as such is its own text, not hidden
            if n > 0:
                counts[(one, more)] = counts.get((one, more), 0) + n
    return [(n, one if n == 1 else more) for (one, more), n in counts.items()]


def words(found):
    return ", ".join(f"{n} {what}" for n, what in found)


def on_the_message(msg):
    """The addresses on a message, lower-case."""
    values = [str(v) for h in ON_THE_MESSAGE for v in (msg.get_all(h) or [])]
    return {a.lower() for _, a in getaddresses(values) if a}


def own_addresses():
    return {a["address"].lower() for a in compose.accounts().values() if a.get("address")}


def answered(msg):
    """The id of the message a draft answers (its In-Reply-To), or None for a new message."""
    value = str(msg.get("In-Reply-To", "")).strip()
    m = re.search(r"<([^<>\s]+)>", value)
    return (m.group(1) if m else value) or None


def strangers(have, msg):
    """The draft's recipients who weren't on the message it answers (nor the user's own addresses); for a new message
    none: Claude wrote all of it, and couldn't write what it never saw."""
    mid = answered(msg)
    if not mid:
        return []
    try:
        known = on_the_message(compose.parsed(mid))
    except (StopIteration, OSError, ValueError, LookupError):
        known = set()   # the message answered is gone: nobody is known to have been on it
    known |= own_addresses()
    return [a for _, a in getaddresses([", ".join(have["to"] + have["cc"])]) if a and a.lower() not in known]


def secrets_seen():
    """The user lets Claude read Mail's codes (Access › Mail › secrets): its copy wasn't masked."""
    try:
        return json.loads(os.environ.get("NIGHTDRIVE_MCP_OPTIONS") or "{}").get("secrets") is True
    except (ValueError, AttributeError):
        return False


def check(have, msg):
    """The card's rows for a draft ({label: text}); LookupError when it mustn't go out from Claude's tools at all."""
    if secrets_seen() or not MASK.exists():
        return {}
    found = hidden([have["subject"], have["body"]])
    if not found:
        return {}
    outside = strangers(have, msg)
    if outside:
        raise LookupError(f"Not sent: the draft quotes what Claude saw hidden ({words(found)}), and it would go to "
                          f"{', '.join(outside)}, who wasn't on the message it answers. A login link or a code is "
                          "the user's alone: they can send it from Mail themselves if they mean to.")
    return {"Hidden from Claude": f"Goes out as the draft has it, not as this card shows it: {words(found)}"}
