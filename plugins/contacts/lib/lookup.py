#!/usr/bin/env python3
"""Finding people and reading a card without the window: `contacts find` and `contacts card` (and Claude's tools,
mcp.json).

    lookup.py find [--json] [--limit N] QUERY…   the people a search finds, as the window's search finds them
    lookup.py card [--json] WHO                  one person's card: WHO is a card's id, an email address or a number

Both read the people as All contacts shows them (cards.py's people(): one person's cards in several accounts as one),
without pictures, so nothing is written. Without --json they print text for a terminal.
"""

import json
import re
import sys

import cards

LIMIT = 25      # find's default: enough to pick from, short enough for Claude to read


def everyone():
    return cards.people(cards.load(photos=False)[1])


def haystack(p):
    """What a search looks in, as the window's haystack() (app/shell.qml): numbers without their spaces"""
    return "\n".join([p["name"], p["nickname"], p["org"], p["company"], p["title"]]
                     + [e["value"] for e in p["emails"]]
                     + [re.sub(r"[\s\-()]", "", n["value"]) for n in p["phones"]]
                     + [" ".join(a["lines"]) for a in p["addresses"]]).lower()


def needle(word):
    """A number is looked for without its dashes and leading 0, so 040 123 finds +358 40 123 too (the window's needle())"""
    return re.sub(r"^0+", "", word.replace("-", "")) if re.fullmatch(r"\+?[\d\-]+", word) else word


def lines(items):
    return [{"label": v["label"], "value": v["value"]} for v in items]


def brief(p):
    """A row of find: enough to tell people apart and to write or call them"""
    return {"id": p["id"], "name": p["name"], "org": p["org"], "title": p["title"],
            "emails": lines(p["emails"]), "phones": lines(p["phones"])}


def whole(p):
    """The card: everything but the window's own fields (refs, photo, the editor's name parts)"""
    return dict(brief(p), nickname=p["nickname"], ids=p["ids"], accounts=p["accounts"],
                addresses=[{"label": a["label"], "value": "\n".join(a["lines"])} for a in p["addresses"]],
                urls=lines(p["urls"]), birthday=p["birthday"], note=p["note"])


def find(query, limit):
    words = [needle(w) for w in query.lower().split()]
    found = [p for p in everyone() if all(w in haystack(p) for w in words)]
    return {"query": query, "count": len(found), "people": [brief(p) for p in found[:limit]]}


def card(who):
    """The person by a card's id, an email address or a number (its last 9 digits), as the window's showWho()"""
    w = who.strip().lower()
    digits = re.sub(r"\D", "", w)[-9:]
    is_number = re.fullmatch(r"\+?[\d\s\-()]+", w) and len(digits) >= 5
    people = everyone()
    p = (next((x for x in people if who.strip() in x["ids"]), None)
         or next((x for x in people if any(e["value"].lower() == w for e in x["emails"])), None)
         or (next((x for x in people if any(re.sub(r"\D", "", n["value"])[-9:] == digits for n in x["phones"])), None)
             if is_number else None))
    return whole(p) if p else None


def show_lines(items):
    return [f"  {v['label'] or 'other'}: {v['value']}" for v in items]


def text_find(result):
    if not result["people"]:
        return f"No one in your contacts matches {result['query']!r}."
    rows = []
    for p in result["people"]:
        reach = [e["value"] for e in p["emails"][:1]] + [n["value"] for n in p["phones"][:1]]
        rows.append("  ".join([p["name"]] + reach) + f"    ({p['id']})")
    more = result["count"] - len(result["people"])
    return "\n".join(rows + ([f"… and {more} more: narrow the search, or --limit"] if more > 0 else []))


def text_card(p):
    out = [p["name"]]
    out += [x for x in (" · ".join(y for y in (p["title"], p["org"]) if y), p["nickname"] and f"“{p['nickname']}”") if x]
    out += show_lines(p["emails"]) + show_lines(p["phones"]) + show_lines(p["urls"])
    out += [f"  {a['label'] or 'address'}: " + a["value"].replace("\n", ", ") for a in p["addresses"]]
    if p["birthday"]:
        out.append(f"  birthday: {p['birthday']}")
    if p["note"]:
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
        result = find(query, limit)
        print(json.dumps(result, ensure_ascii=False) if as_json else text_find(result))
        return
    p = card(query)
    if p is None:
        # An error a reader (or Claude) can act on: find gives the ids
        sys.exit(f"Not in your contacts: {query}. Find them by name first (contacts find) for their id.")
    print(json.dumps(p, ensure_ascii=False) if as_json else text_card(p))


if __name__ == "__main__":
    main(sys.argv[1:])
