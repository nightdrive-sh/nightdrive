#!/usr/bin/env python3
"""Mail's sorting rules: a sender's mail, or a whole domain's, goes to one of the account's own folders (folders.py)
as it arrives (classify.py) instead of the inbox. A rule is made by dragging a sender's mail into the folder
(sorting.py), never written by hand; kept in ~/.config/nightmail/rules.json.

    rules.py list [--account ID]                     {"rules": [{account, folder, sender | domain, added}]}
    rules.py add ACCOUNT FOLDER sender|domain VALUE  one rule; the sender's (or domain's) old one in that account goes
    rules.py remove ACCOUNT sender|domain VALUE      that rule
    rules.py remove-folder ACCOUNT FOLDER            every rule into that folder (it is being deleted)
    rules.py public                                  {"domains": [...]}: public mail services, refused as a domain

add and remove print {"added": [rules], "removed": [rules]}, which is also their undo: the removed ones added again.
ACCOUNT is the account's id (`nightmail accounts`): rules belong to one account, as its folders do.
"""

import datetime
import json
import os
import sys
import tempfile
from email.utils import getaddresses

PATH = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "nightmail", "rules.json")
KINDS = ("sender", "domain")
# A rule for one of these would sort everyone who has an address there: a domain rule is refused for them
PUBLIC_DOMAINS = {
    "gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "msn.com", "icloud.com", "me.com",
    "mac.com", "yahoo.com", "ymail.com", "aol.com", "proton.me", "protonmail.com", "pm.me", "gmx.com", "gmx.net",
    "gmx.de", "web.de", "mail.com", "yandex.com", "yandex.ru", "zoho.com", "fastmail.com", "fastmail.fm", "hey.com",
    "runbox.com", "tutanota.com", "tuta.io", "hotmail.fi", "live.fi", "outlook.fi", "suomi24.fi", "luukku.com",
    "kolumbus.fi", "elisanet.fi", "pp.inet.fi", "saunalahti.fi", "welho.com", "dnainternet.net",
}


def load():
    try:
        with open(PATH, encoding="utf-8") as f:
            rules = json.load(f).get("rules", [])
    except (OSError, ValueError, AttributeError):
        return []
    return [r for r in rules if isinstance(r, dict) and r.get("account") and r.get("folder") and kind_of(r)]


def save(rules):
    """Written whole and then moved in place: the sync's hook may read it at any moment."""
    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(PATH), prefix=".rules-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump({"rules": rules}, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, PATH)


def kind_of(rule):
    return next((k for k in KINDS if rule.get(k)), None)


def address(header):
    """The address in a From header, lowercased ("" if there is none)."""
    found = [a for _, a in getaddresses([header or ""]) if "@" in a]
    return found[0].strip().lower() if found else ""


def domain(addr):
    return addr.rpartition("@")[2]


def clean(kind, value):
    """A rule's value as kept: an address or a domain, lowercased; ValueError for what can't be one."""
    value = value.strip().lower().lstrip("@")
    if kind == "sender" and (value.count("@") != 1 or not all(value.split("@"))):
        raise ValueError(f"Not an address: {value!r}")
    if kind == "domain":
        if "@" in value or "." not in value or " " in value:
            raise ValueError(f"Not a domain: {value!r}")
        if value in PUBLIC_DOMAINS:
            raise ValueError(f"{value} is a public mail service: sort its senders one at a time")
    return value


def match(rules, account, addr):
    """The folder a sender's mail goes to in an account: a rule for the address itself before one for its domain
    (mail.shop.fi falls under shop.fi), or None."""
    addr = addr.lower()
    mine = [r for r in rules if r["account"] == account]
    for r in mine:
        if r.get("sender") == addr:
            return r["folder"]
    d = domain(addr)
    for r in mine:
        if r.get("domain") and (d == r["domain"] or d.endswith("." + r["domain"])):
            return r["folder"]
    return None


def covering(rules, account, addr):
    """The rules that sort this address in the account: its own and its domain's."""
    addr, d = addr.lower(), domain(addr.lower())
    return [r for r in rules if r["account"] == account and
            (r.get("sender") == addr or r.get("domain") and (d == r["domain"] or d.endswith("." + r["domain"])))]


def add(account, folder, kind, value):
    """Adds a rule, the same sender's (or domain's) old one in the account replaced: {added, removed}."""
    value = clean(kind, value)
    rules = load()
    old = [r for r in rules if r["account"] == account and r.get(kind) == value]
    rule = {"account": account, "folder": folder, kind: value, "added": datetime.date.today().isoformat()}
    if any(o["folder"] == folder for o in old):
        return {"added": [], "removed": []}          # already so
    save([r for r in rules if r not in old] + [rule])
    return {"added": [rule], "removed": old}


def remove(account, kind, value):
    value = value.strip().lower().lstrip("@")
    rules = load()
    gone = [r for r in rules if r["account"] == account and r.get(kind) == value]
    if gone:
        save([r for r in rules if r not in gone])
    return {"added": [], "removed": gone}


def remove_where(test):
    rules = load()
    gone = [r for r in rules if test(r)]
    if gone:
        save([r for r in rules if r not in gone])
    return gone


def restore(added, removed):
    """Takes back a change: the rules it added go, the ones it removed come back."""
    keys = [(r["account"], kind_of(r), r[kind_of(r)]) for r in added + removed]
    rules = [r for r in load() if (r["account"], kind_of(r), r[kind_of(r)]) not in keys]
    save(rules + removed)


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else ""
    if cmd == "list":
        acc = args[2] if args[1:2] == ["--account"] and len(args) > 2 else None
        print(json.dumps({"rules": [r for r in load() if not acc or r["account"] == acc]}, ensure_ascii=False))
    elif cmd == "add" and len(args) == 5 and args[3] in KINDS:
        print(json.dumps(add(args[1], args[2], args[3], args[4]), ensure_ascii=False))
    elif cmd == "remove" and len(args) == 4 and args[2] in KINDS:
        out = remove(args[1], args[2], args[3])
        if not out["removed"]:
            raise ValueError(f"No rule for {args[3]} in {args[1]}")
        # sorting.py undo takes it back (Claude's mail_rule_remove)
        out["step"] = json.dumps({"account": args[1], "folder": "", "added": [], "removed": out["removed"], "moved": []})
        print(json.dumps(out, ensure_ascii=False))
    elif cmd == "public":
        print(json.dumps({"domains": sorted(PUBLIC_DOMAINS)}))
    elif cmd == "remove-folder" and len(args) == 3:
        gone = remove_where(lambda r: r["account"] == args[1] and r["folder"] == args[2])
        print(json.dumps({"added": [], "removed": gone}, ensure_ascii=False))
    else:
        sys.exit(__doc__.split("\n\n")[1])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
