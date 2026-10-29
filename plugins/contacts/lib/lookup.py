#!/usr/bin/env python3
"""Finding people and reading a card without the window: `contacts find` and `contacts card` (and Claude's tools,
mcp.json).

    lookup.py find [--json] [--limit N] QUERY…   the people a search finds, as the window's search finds them
    lookup.py card [--json] WHO                  one person's card: WHO is a card's id, an email address or a number

Both read the people as All contacts shows them (cards.py's people(): one person's cards in several accounts as one),
without pictures, so nothing is written. Without --json they print text for a terminal.

Claude's calls (NIGHTDRIVE_MCP=1, from Nightdrive's MCP server) get only the parts of a card the user ticks in Settings ›
Claude › Access › Contacts (NIGHTDRIVE_MCP_OPTIONS, #1789; config/mcp/areas.py): one that is off isn't given, searched
or looked up by, so a number Claude has can't name its owner either. Its search needs a word of 2 characters and gives
at most LIMIT people, so the address book can't be read a letter at a time. The note, when given, is masked by the
server (mcp.json's mask).
"""

import json
import os
import re
import sys

import cards

LIMIT = 25      # find's default, and the most Claude gets: enough to pick from, short enough to read
SHORTEST = 2    # Claude's search needs a word at least this long
FIELDS = ("company", "title", "emails", "phones", "addresses", "birthday", "urls", "note")   # Access's choices
CHOICE = {"org": "company"}   # a key of the JSON named apart from its choice; keys that are no choice always go


def claude_fields():
    """The parts of a card beside the name that Claude's call may have; None when the call isn't Claude's (all of
    them). What can't be read is none: a choice only ever gives more."""
    if os.environ.get("NIGHTDRIVE_MCP") != "1":
        return None
    try:
        options = json.loads(os.environ.get("NIGHTDRIVE_MCP_OPTIONS", ""))
    except ValueError:
        return set()
    return {f for f in FIELDS if isinstance(options, dict) and options.get(f) is True}


SHOWN = claude_fields()


def shown(field):
    return SHOWN is None or field not in FIELDS or field in SHOWN


def everyone():
    return cards.people(cards.load(photos=False)[1])


def haystack(p):
    """What a search looks in, as the window's haystack() (app/shell.qml): numbers without their spaces. Only what is
    shown: a street that finds someone would tell where they live."""
    return "\n".join([p["name"], p["nickname"]]
                     + ([p["org"], p["company"]] if shown("company") else [])
                     + ([p["title"]] if shown("title") else [])
                     + ([e["value"] for e in p["emails"]] if shown("emails") else [])
                     + ([re.sub(r"[\s\-()]", "", n["value"]) for n in p["phones"]] if shown("phones") else [])
                     + ([" ".join(a["lines"]) for a in p["addresses"]] if shown("addresses") else [])).lower()


def needle(word):
    """A number is looked for without its dashes and leading 0, so 040 123 finds +358 40 123 too (the window's needle())"""
    return re.sub(r"^0+", "", word.replace("-", "")) if re.fullmatch(r"\+?[\d\-]+", word) else word


def lines(items):
    return [{"label": v["label"], "value": v["value"]} for v in items]


def kept(row):
    """A row without the parts Claude isn't given: left out, not empty, so they don't read as having none"""
    return {k: v for k, v in row.items() if shown(CHOICE.get(k, k))}


def brief(p):
    """A row of find: enough to tell people apart and to write or call them"""
    return kept({"id": p["id"], "name": p["name"], "org": p["org"], "title": p["title"],
                 "emails": lines(p["emails"]), "phones": lines(p["phones"])})


def whole(p):
    """The card: everything but the window's own fields (refs, photo, the editor's name parts)"""
    return kept(dict(brief(p), nickname=p["nickname"], ids=p["ids"], accounts=p["accounts"],
                     addresses=[{"label": a["label"], "value": "\n".join(a["lines"])} for a in p["addresses"]],
                     urls=lines(p["urls"]), birthday=p["birthday"], note=p["note"]))


def find(query, limit):
    words = [needle(w) for w in query.lower().split()]
    if SHOWN is not None and max(map(len, words), default=0) < SHORTEST:
        # A letter (or 0, which a number's needle drops) finds most of the book: Claude searches for someone
        raise LookupError(f"Search with a name or a word of at least {SHORTEST} characters, not single letters.")
    found = [p for p in everyone() if all(w in haystack(p) for w in words)]
    return {"query": query, "count": len(found), "people": [brief(p) for p in found[:limit]]}


def card(who):
    """The person by a card's id, an email address or a number (its last 9 digits), as the window's showWho()"""
    w = who.strip().lower()
    digits = re.sub(r"\D", "", w)[-9:]
    is_number = re.fullmatch(r"\+?[\d\s\-()]+", w) and len(digits) >= 5
    people = everyone()
    p = (next((x for x in people if who.strip() in x["ids"]), None)
         or (next((x for x in people if any(e["value"].lower() == w for e in x["emails"])), None)
             if shown("emails") else None)
         or (next((x for x in people if any(re.sub(r"\D", "", n["value"])[-9:] == digits for n in x["phones"])), None)
             if is_number and shown("phones") else None))
    return whole(p) if p else None


def show_lines(items):
    return [f"  {v['label'] or 'other'}: {v['value']}" for v in items]


def text_find(result):
    if not result["people"]:
        return f"No one in your contacts matches {result['query']!r}."
    rows = []
    for p in result["people"]:
        reach = [e["value"] for e in p.get("emails", [])[:1]] + [n["value"] for n in p.get("phones", [])[:1]]
        rows.append("  ".join([p["name"]] + reach) + f"    ({p['id']})")
    more = result["count"] - len(result["people"])
    return "\n".join(rows + ([f"… and {more} more: narrow the search, or --limit"] if more > 0 else []))


def text_card(p):
    out = [p["name"]]
    out += [x for x in (" · ".join(y for y in (p.get("title"), p.get("org")) if y),
                        p["nickname"] and f"“{p['nickname']}”") if x]
    out += show_lines(p.get("emails", [])) + show_lines(p.get("phones", [])) + show_lines(p.get("urls", []))
    out += [f"  {a['label'] or 'address'}: " + a["value"].replace("\n", ", ") for a in p.get("addresses", [])]
    if p.get("birthday"):
        out.append(f"  birthday: {p['birthday']}")
    if p.get("note"):
        out.append("  note: " + p["note"].replace("\n", "\n        "))
    out.append(f"  ({', '.join(p['ids'])})")
    return "\n".join(out)


def main(argv):
    if not argv or argv[0] not in ("find", "card"):
        sys.exit(__doc__)
    command, rest = argv[0], argv[1:]
    as_json = "--json" in rest
    rest = [a for a in rest if a != "--json"]
    limit = LIMIT
    if "--limit" in rest:
        i = rest.index("--limit")
        try:
            limit = max(1, int(rest[i + 1]))
        except (IndexError, ValueError):
            sys.exit("--limit takes a number")
        del rest[i:i + 2]
    query = " ".join(rest).strip()
    if not query:
        sys.exit(f"Usage: contacts {command} {'QUERY' if command == 'find' else 'WHO'} [--json]")
    if command == "find":
        if SHOWN is not None:
            limit = min(limit, LIMIT)
        try:
            result = find(query, limit)
        except LookupError as e:
            sys.exit(str(e))
        print(json.dumps(result, ensure_ascii=False) if as_json else text_find(result))
        return
    p = card(query)
    # Looked up by a part Access leaves out: say so, as "not in your contacts" would be untrue
    hidden = next((words for f, words, looks in (("emails", "email addresses", "@" in query),
                                                 ("phones", "phone numbers", len(re.sub(r"\D", "", query)) >= 5))
                   if looks and not shown(f)), None)
    if p is None and hidden:
        sys.exit(f"The user's Access (Settings › Claude › Access › Contacts) doesn't give Claude {hidden}, so no one is "
                 "found by one. Find them by name (contacts_find) for their id.")
    if p is None:
        # An error a reader (or Claude) can act on: find gives the ids
        sys.exit(f"Not in your contacts: {query}. Find them by name first (contacts find) for their id.")
    print(json.dumps(p, ensure_ascii=False) if as_json else text_card(p))


if __name__ == "__main__":
    main(sys.argv[1:])
