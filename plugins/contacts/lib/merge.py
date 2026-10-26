#!/usr/bin/env python3
"""vdirsyncer's conflict_resolution (config.py): a card changed both on the server (the phone) and here since the last
sync. Called with the two versions' files, named after their storages (NAME_remote, NAME_local); it writes the merged
card into both, as vdirsyncer wants.

    merge.py REMOTE LOCAL

What changed here is found against the card as it was before Contacts first changed it (edit.py keeps that in BASE_DIR,
by its UID), and the server's version takes those changes, a field at a time:
- a field only one side changed is that side's;
- a number, address, link… (MULTI) added on either side stays, and one either side removed goes: a line is known by
  its value (ident), not by how the side wrote it;
- a field both changed to different things (the name, the note) is this computer's, the later edit as a rule.
Without the base (a file edited by hand) nothing is known to be removed: both sides' lines are kept.
"""

import datetime
import os
import re
import sys
from pathlib import Path

import vcard

HOME = Path.home()
BASE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "contacts/base"
# Fields with any number of lines, merged line by line; every other field is one thing, taken whole from one side
MULTI = {"TEL", "EMAIL", "ADR", "URL", "IMPP", "X-SOCIALPROFILE", "X-ABRELATEDNAMES", "X-ABDATE",
         "X-ADDRESSBOOKSERVER-MEMBER", "CATEGORIES"}
# The card's own bookkeeping: the server's, and REV new
SKIP = {"VERSION", "PRODID", "UID", "REV"}


def key(unit):
    """A unit as text to compare, without its item group's name (item3 in one card is item7 in the other)"""
    return "\n".join(sorted(x.name + x.params.lower() + ":" + x.value for x in unit[1]))


def ident(unit):
    """What a line of a MULTI field is, however a side wrote it: the iPhone rewrites a number saved here as
    TEL;type=CELL;type=VOICE;type=pref, which is still the same number. Its label isn't part of it."""
    main = unit[0]
    value = vcard.unescape(main.value).strip()
    if main.name == "TEL":
        value = re.sub(r"[^\d+]", "", value)
    elif main.name in ("EMAIL", "URL", "IMPP"):
        value = value.lower()
    elif main.name == "ADR":
        value = " ".join(re.findall(r"\w+", value.casefold()))
    return main.name + ":" + value


def multi(ru, lu, bu):
    """A MULTI field's lines, line by line: the server's, without the ones removed here and with the ones added here; a
    line both have takes this side's version where this side changed it (its label), else the server's"""
    b = {ident(u): u for u in bu or []}
    l = {ident(u): u for u in lu}
    r = {ident(u): u for u in ru}
    out = []
    for i, u in r.items():
        if bu is not None and i in b and i not in l:
            continue
        mine = l.get(i)
        out.append(mine if mine is not None and (bu is None or i not in b or key(mine) != key(b[i])) else u)
    out += [u for i, u in l.items() if i not in r and (bu is None or i not in b)]
    return out


def by_name(lines):
    out = {}
    for u in vcard.units(lines):
        out.setdefault(u[0].name, []).append(u)
    return out


def merge(remote, local, base):
    r, l = by_name(remote), by_name(local)
    b = by_name(base) if base is not None else None
    names = list(r) + [n for n in l if n not in r]
    out = []
    for name in names:
        if name in SKIP:
            if name != "REV":
                out += (r.get(name) or l.get(name))[:1]
            continue
        ru, lu = r.get(name, []), l.get(name, [])
        rk, lk = [key(u) for u in ru], [key(u) for u in lu]
        if name in MULTI:
            out += multi(ru, lu, b.get(name, []) if b is not None else None)
            continue
        if b is None:
            out += lu if lu else ru
            continue
        bk = [key(u) for u in b.get(name, [])]
        if lk == bk:
            out += ru
        elif rk == bk:
            out += lu
        else:
            out += lu
    rev = vcard.make("REV", datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    out.append((rev, [rev]))
    return vcard.flatten(out)


def uid(lines):
    return next((x.value for x in lines if x.name == "UID"), "")


def main(remote_path, local_path):
    remote_text = Path(remote_path).read_text(errors="replace")
    remote = vcard.parse(remote_text)
    local = vcard.parse(Path(local_path).read_text(errors="replace"))
    account = re.sub(r"_(remote|local)$", "", Path(remote_path).name)
    base_file = BASE_DIR / account / (re.sub(r"[^\w.-]", "_", uid(local) or uid(remote)) + ".vcf")
    base = vcard.parse(base_file.read_text(errors="replace")) if base_file.exists() else None
    text = vcard.serialize(merge(remote, local, base), "\r\n" if "\r\n" in remote_text else "\n")
    for p in (remote_path, local_path):
        Path(p).write_text(text)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
