#!/usr/bin/env python3
"""A task edited on two devices before they synced, merged field by field (#3391 › Ristiriidat, #3397).

merge(base, mine, theirs) takes three versions of one task file: the one both devices last agreed on (base), this
device's (mine) and the Hub's (theirs, the one that got there first). A field changed on one side only takes that
side's value, so a retitle here and a due date moved there both stay. A field changed on both sides to different
values takes the side whose LAST-MODIFIED is newer (the Hub's on a tie, or when neither has one), and the value that
lost is written at the end of the task's notes, so nothing is lost without a trace. A field emptied on one side and
edited on the other keeps the edit: a deletion never wins over an edit, as with whole tasks in the sync.

A field is a property by name, all its lines together (CATEGORIES may come twice), except where properties only make
sense together: done is STATUS, COMPLETED and PERCENT-COMPLETE, so a task is never left "done" with no completion
time. Nested components (a VALARM) are one field. What the sync sets itself (DTSTAMP, LAST-MODIFIED, SEQUENCE) is
not merged but written new, and the calendar's own lines around the VTODO (a VTIMEZONE) are the Hub's file's.

A task's place in its list (X-APPLE-SORT-ORDER, order.py) is merged as a field, but a place that lost isn't written
in the notes: a number there would say nothing, and the task is still in the list where the newer move put it (#3507).

No base (a first sync, a new Hub) or two files that aren't the same task: None, and the caller keeps both.
"""

from datetime import datetime

from ics import Line, Task, as_text, escape, parse_time, unescape

# Properties that change together and so are merged as one field, by the first's name
GROUPS = {"COMPLETED": "STATUS", "PERCENT-COMPLETE": "STATUS"}
# Written by every change, so always different on two sides: set new on the result instead
META = {"DTSTAMP", "LAST-MODIFIED", "SEQUENCE"}
COMPONENTS = "BEGIN"       # the key nested components are merged under
LABELS = {"SUMMARY": "Title", "DESCRIPTION": "Notes", "STATUS": "Done", "DUE": "Due", "PRIORITY": "Priority",
          "DTSTART": "Starts", "CATEGORIES": "Tags", COMPONENTS: "Reminders"}
# Fields whose losing value isn't worth a line in the notes: the newer side's wins without a trace
QUIET = {"X-APPLE-SORT-ORDER"}
OTHER = "another computer"  # the Hub doesn't say which device wrote its version


class Merged:
    def __init__(self, text, lost):
        self.text = text        # the merged file
        self.lost = lost        # [{"field", "value", "from"}]: values that lost, now in the notes


def text_of(data):
    return data.decode("utf-8") if isinstance(data, (bytes, bytearray)) else data


def parse(data):
    try:
        return Task(text_of(data))
    except (UnicodeDecodeError, ValueError, AttributeError, TypeError):
        return None


def fields(task):
    """({key: tuple of the field's lines as written}, [keys in the file's order], [META lines], end): the VTODO's own
    properties by field, its nested components under COMPONENTS, and the index of its END line."""
    out, order, meta, depth, block = {}, [], [], 0, []
    i = task.start + 1
    while i < len(task.lines):
        line = task.lines[i]
        if depth == 0 and line.name == "END":
            break
        if line.name == "BEGIN":
            depth += 1
        if depth:
            block.append(line)
            if line.name == "END":
                depth -= 1
                if depth == 0:
                    out.setdefault(COMPONENTS, []).append(block)
                    block = []
                    if COMPONENTS not in order:
                        order.append(COMPONENTS)
        elif line.name in META:
            meta.append(line)
        else:
            key = GROUPS.get(line.name, line.name)
            out.setdefault(key, []).append(line)
            if key not in order:
                order.append(key)
        i += 1
    frozen = {}
    for k, v in out.items():
        frozen[k] = tuple(tuple(str(l) for l in b) for b in v) if k == COMPONENTS else tuple(str(l) for l in v)
    return frozen, order, meta, i


def modified(task):
    """When this side was last changed, for the newer-wins rule; None when it doesn't say"""
    for name in ("LAST-MODIFIED", "DTSTAMP"):
        line = task.line(name)
        when = parse_time(line) if line else None
        if isinstance(when, datetime):
            return when
    return None


def shown(key, value):
    """A field's value as a person reads it in the note"""
    if not value:
        return "none"
    if key == COMPONENTS:
        return "%d reminder%s" % (len(value), "s" * (len(value) != 1))
    lines = [Line.parse(v) for v in value]
    if key == "STATUS":
        status = next((l.value.upper() for l in lines if l.name == "STATUS"), "")
        return "yes" if status == "COMPLETED" else "no"
    if key in ("DUE", "DTSTART"):
        return as_text(parse_time(lines[0])) or lines[0].value
    return ", ".join(unescape(l.value) for l in lines)


def pick(key, b, m, t, mine_newer):
    """(value, lost value or None, lost side "mine"/"theirs" or None) for one field"""
    if m == t or m == b:
        return t, None, None
    if t == b:
        return m, None, None
    # Changed on both sides, differently
    if m is None:
        return t, None, None        # removed here, edited there: the edit stays
    if t is None:
        return m, None, None
    return (m, t, "theirs") if mine_newer else (t, m, "mine")


def note(lost, here, when):
    """The lines that go at the end of the notes: one group per side that lost something"""
    out = []
    for side, who in (("mine", here), ("theirs", OTHER)):
        mine = [x for x in lost if x["side"] == side]
        if not mine:
            continue
        stamp = when[side].strftime(", %Y-%m-%d %H:%M") if when[side] else ""
        out.append("Edited on two computers. Not kept from the older edit (%s%s):" % (who, stamp))
        out += ["%s: %s" % (x["field"], x["value"]) for x in mine]
    return "\n".join(out)


def merge(base, mine, theirs, here="this computer"):
    """Merged(text, lost), or None when the three can't be merged (see the module's docstring). `here` names this
    computer in the note."""
    if base is None:
        return None
    b, m, t = parse(base), parse(mine), parse(theirs)
    if not (b and m and t) or len({x.get("UID") for x in (b, m, t)}) != 1:
        return None
    (bf, _, _, _), (mf, morder, _, _), (tf, torder, meta, tend) = fields(b), fields(m), fields(t)
    when = {"mine": modified(m), "theirs": modified(t)}
    # Newer wins; the Hub's on a tie or when this side doesn't say (it was there first)
    mine_newer = when["mine"] is not None and (when["theirs"] is None or when["mine"] > when["theirs"])

    chosen, lost = {}, []
    order = torder + [k for k in morder if k not in torder]
    for key in order:
        value, gone, side = pick(key, bf.get(key), mf.get(key), tf.get(key), mine_newer)
        if value is not None:
            chosen[key] = value
        if side and key not in QUIET:
            lost.append({"field": LABELS.get(key, key.title()), "value": shown(key, gone),
                         "from": here if side == "mine" else OTHER, "side": side})
    if chosen == tf and not lost:
        return Merged(text_of(theirs), [])      # nothing of this side's to add: the Hub's file as it is

    # The Hub's file is the frame: its calendar lines and its VTODO's META, with the chosen fields in place
    own = [Line.parse(v) for k in order if k in chosen and k != COMPONENTS for v in chosen[k]]
    nested = [Line.parse(v) for block in chosen.get(COMPONENTS, ()) for v in block]
    t.lines = t.lines[:t.start + 1] + own + meta + nested + t.lines[tend:]
    if lost:
        text = note(lost, here, when)
        notes = t.get("DESCRIPTION")
        t.put(Line("DESCRIPTION", {}, escape(notes + "\n\n" + text if notes else text)))
    # touch() adds one to SEQUENCE: from the higher of the two, so the result reads as newer than either side
    seqs = [int(s) for s in (m.get("SEQUENCE"), t.get("SEQUENCE")) if s.isdigit()]
    t.put(Line("SEQUENCE", {}, str(max(seqs, default=0))))
    t.touch()
    for x in lost:
        del x["side"]
    return Merged(str(t), lost)
