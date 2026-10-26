#!/usr/bin/env python3
"""The contacts in ~/.local/share/contacts as JSON, for Contacts' window (app/shell.qml).

    cards.py list      {accounts: [{id, name, count}], groups: [{id, account, name, members}], contacts: [...], people: [...]}
    cards.py people    [{id, name, org, emails, phones, addresses}]: the people alone, lines as text, for Mail and the
                       launcher (`contacts people`; no pictures, so it is quick and writes nothing)

A contact is {id, account, name, sort, org, title, nickname, initials, photo, emails, phones, addresses, urls, birthday,
note}: emails, phones and urls are [{label, value, ref}], addresses [{label, lines, ref, street, code, city, region,
country}]; ref is what edit.py finds the line by. id is the file's path under the folder.
photo is a picture to show: a file in the cache for one inside the card or one of iCloud's (photos.py), the address of
one on the web, or "".
people are the contacts of every account with one person's cards as one (people() says when), each with ids and accounts.
Apple's groups are cards of their own (X-ADDRESSBOOKSERVER-KIND:group); the others come from CATEGORIES.
"""

import configparser
import json
import os
import re
import sys
from pathlib import Path

import vobject

import photos as photos_lib

HOME = Path.home()
DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "contacts"
ACCOUNTS = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "contacts/accounts.conf"
PHOTO_DIR = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "contacts/photos"
ACCOUNT_NAMES = {"icloud": "iCloud", "google": "Google", "carddav": "CardDAV"}
# vCard's TYPE words, as a contact app shows them; the rest keep their own word
LABELS = {"cell": "mobile", "iphone": "iPhone", "main": "main", "home": "home", "work": "work", "fax": "fax",
          "pager": "pager", "other": "other", "internet": "", "voice": "", "pref": "", "x400": ""}
# Apple's own labels come in an item's X-ABLABEL: _$!<Mobile>!$_
APPLE_LABEL = re.compile(r"^_\$!<(.*)>!\$_$")


def accounts():
    """[(id, name)] in accounts.conf's order: the type's name, or the address with more than one of a type."""
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(ACCOUNTS)
    found = [(s.partition(" ")[2], parser[s]) for s in parser.sections() if s.startswith("account ")]
    kinds = [v.get("type", "") for _, v in found]
    return [(name, ACCOUNT_NAMES.get(v.get("type", ""), name) if kinds.count(v.get("type", "")) == 1
             else v.get("address", name)) for name, v in found]


def text(card, key):
    item = card.contents.get(key)
    if not item:
        return ""
    value = item[0].value
    return value if isinstance(value, str) else ""


def labels(card):
    """X-ABLABEL by item group (item1.TEL with item1.X-ABLABEL), Apple's way to name a number or an address."""
    out = {}
    for item in card.contents.get("x-ablabel", []):
        if item.group:
            m = APPLE_LABEL.match(item.value)
            out[item.group] = (m.group(1) if m else item.value).lower()
    return out


def label(item, grouped):
    if item.group and item.group in grouped:
        return grouped[item.group]
    words = [t.lower() for t in item.params.get("TYPE", [])]
    shown = [LABELS.get(w, w) for w in words if LABELS.get(w, w)]
    return shown[0] if shown else ""


def values(card, key, grouped):
    """ref: the line's place among the card's lines of its kind, which edit.py finds it by"""
    return [{"label": label(i, grouped), "value": i.value.strip(), "ref": n} for n, i in enumerate(card.contents.get(key, []))
            if isinstance(i.value, str) and i.value.strip()]


def addresses(card, grouped):
    """lines to show, and the parts the editor shows (street holds the box and the extended line too)"""
    out = []
    for n, item in enumerate(card.contents.get("adr", [])):
        a = item.value
        street = " ".join(x for x in (a.box, a.extended, a.street) if x).strip()
        town = " ".join(x for x in (a.code, a.city) if x).strip()
        lines = [x.strip() for x in (street, town, a.region, a.country) if x and x.strip()]
        if lines:
            out.append({"label": label(item, grouped), "lines": lines, "ref": n, "street": street, "code": a.code or "",
                        "city": a.city or "", "region": a.region or "", "country": a.country or ""})
    return out


def birthday(card):
    """2001-05-03, --05-03 (no year) or 20010503, as YYYY-MM-DD or --MM-DD"""
    raw = text(card, "bday").split("T")[0]
    m = re.match(r"^(\d{4}|--)-?(\d{2})-?(\d{2})$", raw)
    if not m:
        return ""
    year = "--" if m.group(1) in ("--", "1604") else m.group(1)     # 1604: Apple's year for "no year"
    return (year + "-" if year != "--" else "--") + m.group(2) + "-" + m.group(3)


def photo(card, path, photos=True):
    """The card's picture: inside it (written once to the cache, named by its content) or on the web."""
    item = card.contents.get("photo")
    if not item or not photos:
        return ""
    p = item[0]
    if isinstance(p.value, str) and p.value.startswith(("http://", "https://")):
        if not photos_lib.signed_in(p.value):
            return p.value
        # iCloud's need its sign-in: photos.py fetches them after a sync; till then the initials show
        cached = photos_lib.cached(p)
        return str(cached) if cached.exists() else ""
    data = photos_lib.inside(p, path)
    if data is None:
        return ""
    path = photos_lib.own(data)
    if not path.exists():
        PHOTO_DIR.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return str(path)


def name_parts(card):
    n = card.contents.get("n")
    if n and not isinstance(n[0].value, str):
        return n[0].value.given or "", n[0].value.family or ""
    return "", ""


def initials(name):
    words = [w for w in re.split(r"[\s\-]+", name) if w and w[0].isalnum()]
    return "".join(w[0] for w in words[:2]).upper()


def read(path):
    try:
        return vobject.readOne(path.read_text(errors="replace"))
    except Exception:       # a card vobject can't read is left out, not the whole list
        return None


def load(photos=True):
    """(accounts, contacts, groups, counts) from the folders; photos=False leaves the pictures out"""
    found = accounts()
    contacts, groups, counts = [], [], {}
    for account, _ in found:
        counts[account] = 0
        for path in sorted((DATA_DIR / account).rglob("*.vcf")):
            card = read(path)
            if card is None:
                continue
            uid = text(card, "uid")
            cid = str(path.relative_to(DATA_DIR))
            kind = text(card, "x-addressbookserver-kind").lower() or text(card, "kind").lower()
            if kind == "group":
                members = [m.value.removeprefix("urn:uuid:") for m in card.contents.get("x-addressbookserver-member", [])]
                groups.append({"id": cid, "account": account, "name": text(card, "fn"), "members": members})
                continue
            given, family = name_parts(card)
            org = card.contents.get("org")
            org = " ".join(x for x in org[0].value if x) if org and isinstance(org[0].value, list) else ""
            name = text(card, "fn").strip() or " ".join(x for x in (given, family) if x) or org
            grouped = labels(card)
            emails = values(card, "email", grouped)
            phones = values(card, "tel", grouped)
            if not name:
                name = emails[0]["value"] if emails else phones[0]["value"] if phones else ""
            if not name:
                continue
            categories = card.contents.get("categories")
            contacts.append({
                "id": cid, "uid": uid, "account": account, "name": name,
                "given": given, "family": family,
                # org is left out of a company's own card, where it is the name; company is it as written, for the editor
                "org": org if org != name else "", "company": org, "title": text(card, "title"), "nickname": text(card, "nickname"),
                "initials": initials(name), "photo": photo(card, path, photos),
                "emails": emails, "phones": phones, "addresses": addresses(card, grouped),
                "urls": values(card, "url", grouped), "birthday": birthday(card), "note": text(card, "note").strip(),
                "categories": [c for c in (categories[0].value if categories else []) if c],
            })
            counts[account] += 1
    # CATEGORIES as groups, where the account has no group cards of its own
    for account, _ in found:
        if any(g["account"] == account for g in groups):
            continue
        names = sorted({c for x in contacts if x["account"] == account for c in x["categories"]}, key=str.casefold)
        for n in names:
            members = [x["uid"] for x in contacts if x["account"] == account and n in x["categories"]]
            groups.append({"id": account + "/" + n, "account": account, "name": n, "members": members})
    groups.sort(key=lambda g: (g["account"], g["name"].casefold()))
    contacts.sort(key=lambda x: x["name"].casefold())
    return found, contacts, groups, counts


def main():
    found, contacts, groups, counts = load()
    json.dump({"accounts": [{"id": a, "name": n, "count": counts.get(a, 0)} for a, n in found],
               "groups": groups, "contacts": contacts, "people": people(contacts)}, sys.stdout, ensure_ascii=False)


def reach(x):
    """A contact's numbers (their last 9 digits, so +358 40… and 040… meet) and addresses, to tell one person from two"""
    return ({re.sub(r"\D", "", p["value"])[-9:] for p in x["phones"]} - {""}) | {e["value"].lower() for e in x["emails"]}


def people(contacts):
    """All contacts as people: the cards of one person in several accounts (the same name, and a number or address
    in common, or nothing to tell them apart by) as one, with every line of them once. ids lists the cards."""
    out, by_name = [], {}
    for x in contacts:
        key = x["name"].casefold()
        same = next((p for p in by_name.get(key, []) if not reach(p) or not reach(x) or reach(p) & reach(x)), None)
        if same is None:
            p = dict(x, ids=[x["id"]], accounts=[x["account"]])
            by_name.setdefault(key, []).append(p)
            out.append(p)
            continue
        same["ids"].append(x["id"])
        if x["account"] not in same["accounts"]:
            same["accounts"].append(x["account"])
        for field in ("org", "company", "title", "nickname", "photo", "birthday", "given", "family"):
            same[field] = same[field] or x[field]
        if x["note"] and x["note"] not in same["note"]:
            same["note"] = (same["note"] + "\n\n" + x["note"]).strip()
        for field, key_of in (("emails", lambda v: v["value"].lower()), ("urls", lambda v: v["value"]),
                              ("phones", lambda v: re.sub(r"\D", "", v["value"])[-9:]),
                              # The same address written another way ("9 Rinnetie" for "Rinnetie 9"): its words
                              ("addresses", lambda v: " ".join(sorted(re.findall(r"\w+", " ".join(v["lines"]).casefold()))))):
            have = {key_of(v) for v in same[field]}
            same[field] = same[field] + [v for v in x[field] if key_of(v) not in have]
    return out


def brief():
    """The people, each line as its text: what Mail completes addresses from and the launcher finds people by"""
    out = []
    for p in people(load(photos=False)[1]):
        out.append({"id": p["id"], "name": p["name"], "org": p["org"],
                    "emails": [{"label": v["label"], "value": v["value"]} for v in p["emails"]],
                    "phones": [{"label": v["label"], "value": v["value"]} for v in p["phones"]],
                    "addresses": [{"label": v["label"], "value": "\n".join(v["lines"])} for v in p["addresses"]]})
    json.dump(out, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    if sys.argv[1:] == ["list"]:
        main()
    elif sys.argv[1:] == ["people"]:
        brief()
    else:
        sys.exit(__doc__)
