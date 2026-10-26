"""A vCard as its own lines, for writing one back without losing what Contacts doesn't know (edit.py, merge.py).

vobject (cards.py) reads a card well, but writing it back through vobject re-encodes every line: an iPhone's or Google's
own fields would come out changed, if at all. Here a card is the list of its lines as they were (unfolded), and an
edit replaces only the lines it means to; the rest are written back as they came.

A *unit* is a line with the lines of its item group: Apple writes a number's label beside it (item1.TEL, item1.X-ABLABEL),
an address's country code too (item4.X-ABADR). A unit is moved, kept or dropped as one.
"""

import re

# A line: [group.]NAME[;params]:value. A quoted parameter value may hold ":" and ";".
LINE = re.compile(r'^(?:(?P<group>[A-Za-z0-9-]+)\.)?(?P<name>[A-Za-z0-9-]+)(?P<params>(?:;(?:[^:";]|"[^"]*")*)*):(?P<value>.*)$',
                  re.S)
FOLD = 75   # octets a line may take before it folds (RFC 6350 3.2)


class Line:
    def __init__(self, raw, folded=None):
        self.raw = raw
        self.folded = folded       # the line as the file had it, folded its own way, for as long as it stays the same
        m = LINE.match(raw)
        if m:
            self.group, self.name = m.group("group") or "", m.group("name").upper()
            self.params, self.value = m.group("params"), m.group("value")
        else:   # not a line we can read: kept as it is, under no name
            self.group, self.name, self.params, self.value = "", "", "", raw

    def build(self):
        return (self.group + "." if self.group else "") + self.name + self.params + ":" + self.value

    def type_words(self):
        """The TYPE words, lowercase: TYPE=HOME,PREF and type=pref alike"""
        out = []
        for p in split_params(self.params):
            key, _, val = p.partition("=")
            if key.upper() == "TYPE":
                out += [w.strip('"').lower() for w in val.split(",") if w]
        return out


def split_params(params):
    """;TYPE=HOME;type=pref → ["TYPE=HOME", "type=pref"]"""
    return [p for p in re.findall(r';((?:[^;"]|"[^"]*")*)', params) if p]


def parse(text):
    """[Line] between BEGIN:VCARD and END:VCARD, unfolded"""
    lines = []
    for raw in re.split(r"\r?\n", text):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1][0] += raw[1:]
            lines[-1][1].append(raw)
        elif raw:
            lines.append([raw, [raw]])
    body = [Line(x, f) for x, f in lines]
    return [x for x in body if x.name not in ("BEGIN", "END")]


def fold(x):
    if x.folded is not None and x.raw == "".join([x.folded[0]] + [f[1:] for f in x.folded[1:]]):
        return "\r\n".join(x.folded)
    out, data = [], x.raw.encode()
    first = True
    while data:
        size = FOLD if first else FOLD - 1
        cut = size if len(data) > size else len(data)
        while cut < len(data) and (data[cut] & 0xC0) == 0x80:     # not inside a UTF-8 character
            cut -= 1
        out.append(("" if first else " ") + data[:cut].decode())
        data, first = data[cut:], False
    return "\r\n".join(out)


def serialize(lines, newline="\r\n"):
    """newline: the card's own, where it had one (a server that wrote \n gets \n back)"""
    return newline.join(["BEGIN:VCARD"] + [fold(x).replace("\r\n", newline) for x in lines] + ["END:VCARD"]) + newline


def units(lines):
    """[(main, [lines])] in the card's order: each ungrouped line alone, each item group as one unit led by its main line
    (the first that isn't Apple's X-AB* note about it, else its first)."""
    out, by_group = [], {}
    for x in lines:
        if not x.group:
            out.append([x])
        elif x.group.lower() in by_group:
            by_group[x.group.lower()].append(x)
        else:
            by_group[x.group.lower()] = [x]
            out.append(by_group[x.group.lower()])
    result = []
    for u in out:
        main = next((x for x in u if not x.name.startswith("X-AB")), u[0])
        result.append((main, u))
    return result


def flatten(unit_list):
    """The lines of units, with their item groups numbered afresh (item1, item2…), so units from two cards don't meet"""
    lines, n = [], 0
    for _, u in unit_list:
        if u[0].group:
            n += 1
            for x in u:
                x.group = f"item{n}"
                x.raw = x.build()
        lines += u
    return lines


def escape(text):
    return text.replace("\\", "\\\\").replace("\n", "\\n").replace(",", "\\,").replace(";", "\\;")


def unescape(text):
    """Only vCard's own escapes, as vobject reads them (cards.py): a stray \\: stays as it is"""
    return re.sub(r"\\([nN,;\\])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), text)


def components(value):
    """N's and ADR's parts, split on ; that isn't escaped, still escaped"""
    return re.split(r"(?<!\\);", value)


def make(name, value, params="", group=""):
    x = Line("X:x")
    x.group, x.name, x.params, x.value = group, name, params, value
    x.raw = x.build()
    return x
