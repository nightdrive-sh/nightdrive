"""The displays' arrangement as geometry (#1800): where a screen dropped in the Displays window (config/displays) or
moved by `arrange` lands. Pure functions over rectangles in layout pixels (after the scale), so the window, the command
and Claude's tool place a screen the same way, and arrange_layout_test.py checks them without a desktop.

A screen is a dict with at least id, x, y, w, h. The rules are macOS's: a screen always touches another along an edge
(the pointer crosses there), never overlaps one, and lands at the nearest such place to where it was dropped; its edges
snap level with its neighbour's (top, centre, bottom) when dropped close to that. A screen left touching nothing by a
move is pulled back to the nearest place beside the others.

A screen with soft set (a virtual one: an iPad over VNC, connected or not) gives way to the desk's displays: they are
placed as if it weren't there, and then it keeps its place if that is still free and beside one, else moves to the
nearest place that is. So a phone not even connected never holds a display out of line (#1800).
"""

SIDES = ("left", "right", "above", "below")
MIN_TOUCH = 100      # layout px two screens share at least, so the pointer finds the crossing
SNAP = 80            # layout px within which an edge snaps level with the neighbour's (top, centre, bottom)


def _overlap(a0, a1, b0, b1):
    return min(a1, b1) - max(a0, b0)


def overlaps(a, b):
    """The two cover some of the same area (a shared edge alone isn't)."""
    return _overlap(a["x"], a["x"] + a["w"], b["x"], b["x"] + b["w"]) > 0 and \
        _overlap(a["y"], a["y"] + a["h"], b["y"], b["y"] + b["h"]) > 0


def touches(a, b):
    """They share a stretch of an edge that the pointer can cross (a corner alone isn't one)."""
    if a["x"] + a["w"] == b["x"] or b["x"] + b["w"] == a["x"]:
        return _overlap(a["y"], a["y"] + a["h"], b["y"], b["y"] + b["h"]) > 0
    if a["y"] + a["h"] == b["y"] or b["y"] + b["h"] == a["y"]:
        return _overlap(a["x"], a["x"] + a["w"], b["x"], b["x"] + b["w"]) > 0
    return False


def _along(want, other0, other_len, size):
    """The coordinate along the shared edge: as dropped, kept within reach of the neighbour (MIN_TOUCH shared) and
    snapped level with its start, centre or end when close."""
    touch = min(MIN_TOUCH, size, other_len)
    lo, hi = other0 - size + touch, other0 + other_len - touch
    v = max(lo, min(hi, want))
    for level in (other0, other0 + (other_len - size) // 2, other0 + other_len - size):
        if abs(v - level) <= SNAP:
            return level
    return v


def beside(s, o, side, want_x=None, want_y=None):
    """Where s goes on that side of o: (x, y), along the edge at want (default: centred on o)."""
    if want_x is None:
        want_x = o["x"] + (o["w"] - s["w"]) // 2
    if want_y is None:
        want_y = o["y"] + (o["h"] - s["h"]) // 2
    if side == "left":
        return o["x"] - s["w"], _along(want_y, o["y"], o["h"], s["h"])
    if side == "right":
        return o["x"] + o["w"], _along(want_y, o["y"], o["h"], s["h"])
    if side == "above":
        return _along(want_x, o["x"], o["w"], s["w"]), o["y"] - s["h"]
    return _along(want_x, o["x"], o["w"], s["w"]), o["y"] + o["h"]


def _free(s, x, y, others):
    t = dict(s, x=x, y=y)
    return not any(overlaps(t, o) for o in others)


def snap(s, x, y, others):
    """The nearest place to (x, y) where s touches one of others and overlaps none. With nothing else on the desk, (x, y)
    itself; None if there is no such place (cannot happen with rectangles, but the caller keeps the screen where it was)."""
    if not others:
        return x, y
    best = None
    for o in others:
        for side in SIDES:
            cx, cy = beside(s, o, side, x, y)
            if not _free(s, cx, cy, others):
                continue
            d = (cx - x) ** 2 + (cy - y) ** 2
            if best is None or d < best[0]:
                best = (d, cx, cy)
    return (best[1], best[2]) if best else None


def connected(screens):
    """The screens' groups that reach each other edge to edge, as lists of ids, the largest first."""
    left = {s["id"]: s for s in screens}
    groups = []
    while left:
        first = next(iter(left))
        group, todo = [], [left.pop(first)]
        while todo:
            s = todo.pop()
            group.append(s["id"])
            for oid in [i for i, o in left.items() if touches(s, o)]:
                todo.append(left.pop(oid))
        groups.append(group)
    groups.sort(key=len, reverse=True)
    return groups


def move(screens, sid, x, y, origin=True):
    """The arrangement after screen sid is dropped at (x, y): it is snapped beside the others, and any screen the move
    left touching nothing is pulled back beside them, nearest first. Returns a new list; the input is left alone. With
    origin, shifted so the desk starts at 0,0 (normalize); without, in the input's coordinates."""
    out = [dict(s) for s in screens]
    by = {s["id"]: s for s in out}
    s = by[sid]
    displays = [o for o in out if not o.get("soft")]
    if not s.get("soft"):
        # A display moves among the displays alone, those it cut off come back, then the virtual screens give way
        at = snap(s, x, y, [o for o in displays if o is not s])
        if at is None:
            return out
        s["x"], s["y"] = at
        _rejoin(displays, keep=sid)
        _settle_soft(out, displays)
    else:
        # A virtual screen lands beside any other and never moves a display; the other virtual screens give way to it
        at = snap(s, x, y, [o for o in out if o is not s])
        if at is None:
            return out
        s["x"], s["y"] = at
        _settle_soft(out, displays + [s])
    return normalize(out) if origin else out


def _settle_soft(screens, placed):
    """The soft screens not yet placed, nearest the placed ones first: each stays where it is if that is free and beside
    one, else goes to the nearest place that is."""
    placed = list(placed)
    rest = [s for s in screens if not any(s is p for p in placed)]

    def dist(s):
        return min((abs(s["x"] - p["x"]) + abs(s["y"] - p["y"]) for p in placed), default=0)
    for s in sorted(rest, key=dist):
        if not (any(touches(s, p) for p in placed) and _free(s, s["x"], s["y"], placed)):
            at = snap(s, s["x"], s["y"], placed)
            if at:
                s["x"], s["y"] = at
        placed.append(s)


def _rejoin(screens, keep):
    """Pulls the groups cut off from keep's back beside it, each screen to its nearest place, the nearest first."""
    for _ in range(len(screens)):
        groups = connected(screens)
        if len(groups) <= 1:
            return
        main = next(g for g in groups if keep in g)
        placed = [s for s in screens if s["id"] in main]
        stray = [s for s in screens if s["id"] not in main]

        def dist(s):
            return min(abs(s["x"] - p["x"]) + abs(s["y"] - p["y"]) for p in placed)
        s = min(stray, key=dist)
        at = snap(s, s["x"], s["y"], placed)
        if at:
            s["x"], s["y"] = at


def place_side(screens, sid, side, of=None, origin=True):
    """Screen sid on a side of screen of, centred on it; without of, outside the whole desk on that side, centred on
    it (the old `display side` and `vnc-display place`). Then snapped and the others rejoined, as a drop is."""
    s = next(t for t in screens if t["id"] == sid)
    others = [o for o in screens if o["id"] != sid]
    if not others:
        return [dict(t) for t in screens]
    if of is not None:
        o = next(t for t in others if t["id"] == of)
    else:
        # A display beside the displays alone; a virtual screen beside all
        around = [t for t in others if s.get("soft") or not t.get("soft")] or others
        x0, y0 = min(t["x"] for t in around), min(t["y"] for t in around)
        x1, y1 = max(t["x"] + t["w"] for t in around), max(t["y"] + t["h"] for t in around)
        o = {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0}
    x, y = beside(s, o, side)
    return move(screens, sid, x, y, origin)


def step(screens, sid, side):
    """The arrow keys: screen sid a screen's width (or height) that way, to the nearest place there that lies mostly in
    that direction (sideways at most half as far as ahead), so → past a screen of the same size swaps the two rather than
    lifting it on top."""
    s = next(t for t in screens if t["id"] == sid)
    others = [o for o in screens if o["id"] != sid and (s.get("soft") or not o.get("soft"))]   # as move() sees them
    dx, dy = {"left": (-s["w"], 0), "right": (s["w"], 0), "above": (0, -s["h"]), "below": (0, s["h"])}[side]
    want_x, want_y = s["x"] + dx, s["y"] + dy
    best = None
    for o in others:
        for sd in SIDES:
            cx, cy = beside(s, o, sd, want_x, want_y)
            if not _free(s, cx, cy, others):
                continue
            ahead = {"left": s["x"] - cx, "right": cx - s["x"], "above": s["y"] - cy, "below": cy - s["y"]}[side]
            aside = abs(cy - s["y"]) if side in ("left", "right") else abs(cx - s["x"])
            if ahead <= 0 or 2 * aside > ahead:
                continue
            d = (cx - want_x) ** 2 + (cy - want_y) ** 2
            if best is None or d < best[0]:
                best = (d, cx, cy)
    if best is None:
        return [dict(t) for t in screens]
    return move(screens, sid, best[1], best[2])


def normalize(screens):
    """Shifted so the desk's displays start at 0,0, as Hyprland lays screens out from there (a virtual screen left of or
    above them goes negative, so whether one is there doesn't move the displays)."""
    if not screens:
        return screens
    base = [s for s in screens if not s.get("soft")] or screens
    dx, dy = min(s["x"] for s in base), min(s["y"] for s in base)
    for s in screens:
        s["x"] -= dx
        s["y"] -= dy
    return screens
