#!/usr/bin/env python3
"""Writes a contact the editor (app/ContactEditor.qml) saved, makes a new one, or deletes one, in the account's folder of
vCards; `contacts sync` then takes the change to the server.

    edit.py save [JSON] the contact as JSON (or on stdin); prints {"id": …} (the card's path under the folder)
    edit.py delete ID…  deletes these cards; prints the accounts whose address book that left empty

save takes {id ("" for a new one), account, given, family, company, title, nickname, birthday, note, phones, emails,
urls, addresses}: phones, emails and urls are [{label, value, ref, orig}], addresses [{label, street, code, city, region,
country, ref, orig}], where ref is the line's place among the card's lines of its kind (cards.py) and orig the line as it
was loaded (-1 and null for a new line). A line that is as it was stays as the card had it, to the byte; one that
changed keeps its parameters (pref, Apple's own) where it can; the card's other fields are never touched.

Before a card changes for the first time since the last sync, its old text goes to BASE_DIR: merge.py needs it to tell
what changed here from what changed on the server, if both did (README.md › Editing).
"""

import configparser
import datetime
import json
import os
import re
import sys
import uuid
from pathlib import Path

import vcard
from vcard import components, escape, make, unescape, units

HOME = Path.home()
DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "contacts"
BASE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "contacts/base"
ACCOUNTS = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "contacts/accounts.conf"
PRODID = "-//Nightdrive//Contacts//EN"

# A label the editor offers, as vCard TYPE words; one it doesn't know (Apple's "Mökki") goes in an X-ABLABEL beside it
TYPES = {"mobile": ["CELL"], "iphone": ["IPHONE", "CELL"], "home": ["HOME"], "work": ["WORK"], "main": ["MAIN"],
         "other": ["OTHER"], "fax": ["FAX"], "pager": ["PAGER"]}
APPLE_ONLY = {"homepage": "_$!<HomePage>!$_"}
# TYPE words a line keeps when its label changes: they say something else than the label
KEEP_TYPES = {"pref", "internet", "voice"}
MULTI = {"phones": "TEL", "emails": "EMAIL", "urls": "URL", "addresses": "ADR"}


def fail(message):
    sys.exit(message)


def account_type(account):
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(ACCOUNTS)
    return parser.get("account " + account, "type", fallback="")


def card_path(cid):
    path = (DATA_DIR / cid).resolve()
    if DATA_DIR.resolve() not in path.parents or path.suffix != ".vcf":
        fail(f"Not a card of Contacts: {cid}")
    return path


def collection(account):
    """The address book a new card goes in: the account's folder with the most cards (iCloud's "card", Google's
    "default"), or its first"""
    root = DATA_DIR / account
    books = [d for d in root.iterdir() if d.is_dir()] if root.is_dir() else []
    if not books:
        fail(f"No address book for {account} yet: run contacts sync first.")
    return max(books, key=lambda d: (len(list(d.glob("*.vcf"))), -books.index(d)))


def birthday(text, icloud):
    """3.5.1980, 3.5., 1980-05-03, --05-03 → BDAY's params and value (iCloud's way for a day without a year), and the
    day as cards.py shows it (1980-05-03 or --05-03), to tell whether it changed"""
    t = text.strip().replace(" ", "")
    m = (re.match(r"^(?P<y>\d{4})-?(?P<m>\d{1,2})-?(?P<d>\d{1,2})$", t) or re.match(r"^--(?P<m>\d{1,2})-?(?P<d>\d{1,2})$", t)
         or re.match(r"^(?P<d>\d{1,2})\.(?P<m>\d{1,2})\.?(?P<y>\d{4})?$", t))
    if not m:
        fail(f"A birthday is a date: 1980-05-03, or 3.5.1980, or 3.5. without the year ({text})")
    y, mo, d = m.groupdict().get("y"), int(m.group("m")), int(m.group("d"))
    try:
        datetime.date(int(y) if y else 2000, mo, d)
    except ValueError:
        fail(f"No such day: {text}")
    if y:
        return ";VALUE=date", f"{y}-{mo:02}-{d:02}", f"{y}-{mo:02}-{d:02}"
    if icloud:
        return ";X-APPLE-OMIT-YEAR=1604;VALUE=date", f"1604-{mo:02}-{d:02}", f"--{mo:02}-{d:02}"
    return "", f"--{mo:02}-{d:02}", f"--{mo:02}-{d:02}"


def shown_birthday(value):
    """BDAY's value as cards.py shows it (YYYY-MM-DD or --MM-DD), to tell whether the editor changed it"""
    m = re.match(r"^(\d{4}|--)-?(\d{2})-?(\d{2})$", value.split("T")[0])
    if not m:
        return value
    year = "--" if m.group(1) in ("--", "1604") else m.group(1)
    return (year + "-" if year != "--" else "--") + m.group(2) + "-" + m.group(3)


class Card:
    """The card's units, with the edits made on them in place"""

    def __init__(self, lines):
        self.units = units(lines)
        self.pending = []       # new units not in self.units yet, whose item groups are taken all the same

    def find(self, name):
        return [u for u in self.units if u[0].name == name]

    def free_group(self):
        used = {x.group.lower() for _, u in self.units + self.pending for x in u}
        n = 1
        while f"item{n}" in used:
            n += 1
        return f"item{n}"

    def single(self, name, value, params=None):
        """name's one line to value (already escaped), or gone when value is ""; kept as it was when it holds that.
        params None keeps the line's own."""
        have = self.find(name)
        if not value:
            self.units = [u for u in self.units if u not in have]
            return
        if have and have[0][0].value == value and params in (None, have[0][0].params):
            return
        line = make(name, value, params if params is not None else have[0][0].params if have else "")
        unit = (line, [line])
        if have:
            i = self.units.index(have[0])
            self.units[i] = unit
            self.units = [u for u in self.units if u not in have[1:]]
        else:
            self.units.append(unit)

    def text(self, name):
        have = self.find(name)
        return unescape(have[0][0].value) if have else ""

    def relabel(self, unit, label, kind):
        """The unit's line with label in place of the one it had: as TYPE words, or in an X-ABLABEL beside it"""
        main, lines = unit
        keep = [p for p in vcard.split_params(main.params) if p.partition("=")[0].upper() != "TYPE"]
        words = [w for w in main.type_words() if w in KEEP_TYPES]
        if kind == "EMAIL" and "internet" not in words:
            words.append("internet")
        key = label.strip().lower()
        custom = ""
        if key in TYPES:
            words = TYPES[key] + [w.upper() for w in words]
        else:
            words = [w.upper() for w in words]
            custom = APPLE_ONLY.get(key, label.strip())
        main.params = "".join(";" + p for p in keep) + "".join(";TYPE=" + w for w in words)
        others = [x for x in lines if x is not main and x.name != "X-ABLABEL"]
        if custom:
            group = main.group or self.free_group()
            main.group = group
            others.append(make("X-ABLABEL", custom, group=group))
        elif main.group and not others:
            main.group = ""      # nothing left in its item group
        main.raw = main.build()
        for x in others:
            x.group = main.group
            x.raw = x.build()
        return main, [main] + others

    def lines_of(self, kind, wanted, value_of):
        """kind's lines (TEL…) to wanted, in its order, where the card's first one of them was"""
        have = self.find(kind)
        out = []
        for w in wanted:
            value = value_of(w)
            if not value.strip(";"):
                continue
            ref, orig = w.get("ref", -1), w.get("orig")
            if orig is not None and 0 <= ref < len(have):
                main, lines = have[ref]
                if value_of(orig) == value and orig.get("label", "") == w.get("label", ""):
                    out.append(have[ref])
                    continue
                copy = [vcard.Line(x.raw) for x in lines]
                unit = (next(x for x in copy if x.name == kind), copy)
                unit[0].value = value
                unit[0].raw = unit[0].build()
                if orig.get("label", "") != w.get("label", ""):
                    unit = self.relabel(unit, w.get("label", ""), kind)
                out.append(unit)
            else:
                line = make(kind, value)
                unit = self.relabel((line, [line]), w.get("label", ""), kind)
                out.append(unit)
            self.pending.append(out[-1])
        self.pending = []
        # They go where the first of the old ones was (or at the end)
        at = self.units.index(have[0]) if have else len(self.units)
        rest = [u for u in self.units if u not in have]
        at = len([u for u in self.units[:at] if u not in have])
        self.units = rest[:at] + out + rest[at:]

    def lines(self):
        return [x for _, u in self.units for x in u]


def address_value(a):
    return ";".join(["", ""] + [escape(a.get(k, "").strip()) for k in ("street", "city", "region", "code", "country")])


def save(data):
    account = data.get("account", "")
    if not re.match(r"^[a-z0-9][a-z0-9_-]*$", account):
        fail(f"No such account: {account}")
    if data.get("id"):
        path = card_path(data["id"])
        old = path.read_text(errors="replace")
        card = Card(vcard.parse(old))
        unchanged = vcard.serialize(card.lines())
    else:
        uid = str(uuid.uuid4()).upper()
        path = collection(account) / (uid + ".vcf")
        old = None
        card = Card([make("VERSION", "3.0"), make("PRODID", PRODID), make("UID", uid)])

    given, family, company = (data.get(k, "").strip() for k in ("given", "family", "company"))
    n = card.find("N")
    parts = components(n[0][0].value) + [""] * 5 if n else [""] * 5
    org = card.find("ORG")
    # The company as cards.py shows it: ORG's parts (the company, its departments) in one
    org_was = " ".join(unescape(x) for x in components(org[0][0].value) if x) if org else ""
    was = (unescape(parts[1]), unescape(parts[0]), org_was)
    if (given, family) != was[:2]:
        card.single("N", ";".join([escape(family), escape(given)] + parts[2:5]))
    if company != org_was:
        card.single("ORG", escape(company))
    # FN, the name shown: kept as the card had it (Dr. Maija) until the name or the company changes
    name = " ".join(x for x in (given, family) if x) or company
    if not name:
        first = [x.get("value", "").strip() for k in ("emails", "phones") for x in data.get(k, []) if x.get("value", "").strip()]
        name = first[0] if first else ""
    if not name:
        fail("A contact needs a name, a company, an email address or a number.")
    if old is None or (given, family, company) != was or not card.find("FN"):
        card.single("FN", escape(name))
    if old is None and company and not (given or family):
        card.single("X-ABSHOWAS", "COMPANY")      # the iPhone lists it under the company

    for key in ("title", "nickname", "note"):
        if data.get(key, "").strip() != card.text(key.upper()):
            card.single(key.upper(), escape(data.get(key, "").strip()))
    bday = data.get("birthday", "").strip()
    have = card.find("BDAY")
    params, value, shown = birthday(bday, account_type(account) == "icloud") if bday else ("", "", "")
    if shown != (shown_birthday(have[0][0].value) if have else ""):
        card.single("BDAY", value, params)

    for key, kind in MULTI.items():
        if key == "addresses":
            card.lines_of(kind, data.get(key, []), address_value)
        else:
            card.lines_of(kind, data.get(key, []), lambda x: x.get("value", "").strip().replace("\n", " "))

    # Saved as it was: the file stays as it is, so the sync has nothing to send
    if old is not None and vcard.serialize(card.lines()) == unchanged:
        return path
    card.single("REV", datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    text = vcard.serialize(card.lines(), "\r\n" if old is None or "\r\n" in old else "\n")
    if old is not None:
        keep_base(account, card.text("UID"), old)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(text)
    tmp.replace(path)
    return path


def keep_base(account, uid, text):
    """The card as the server last had it, for merge.py; the first one stays until the next sync clears them"""
    if not uid:
        return
    base = BASE_DIR / account / (re.sub(r"[^\w.-]", "_", uid) + ".vcf")
    if not base.exists():
        base.parent.mkdir(parents=True, exist_ok=True)
        base.write_text(text)


def delete(ids):
    """The accounts left with an empty address book: vdirsyncer takes that for a folder lost by mistake and won't
    empty the server's too, unless the sync is told it was meant (`contacts sync --force-delete`)"""
    emptied = []
    for cid in ids:
        path = card_path(cid)
        path.unlink(missing_ok=True)
        if not any(path.parent.glob("*.vcf")):
            emptied.append(cid.split("/")[0])
    return emptied


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "save":
        path = save(json.loads(sys.argv[2]) if len(sys.argv) > 2 else json.load(sys.stdin))
        print(json.dumps({"id": str(path.relative_to(DATA_DIR))}))
    elif command == "delete" and len(sys.argv) > 2:
        for account in dict.fromkeys(delete(sys.argv[2:])):
            print(account)
    else:
        sys.exit(__doc__)
