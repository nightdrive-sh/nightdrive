"""How much Claude changes unasked, and what the user just refused (#1882): registry.py's call() asks this before the
card.

A change tool that Access allows runs at once, with Undo. That is fine for one wallpaper, but a loop (a mail that tells
Claude to add a hundred tasks, a note a line at a time, the volume up and down) would fill the user's lists and
notifications faster than they can undo it. So an area takes PACE such changes in a minute; past that each one asks on
the card, which says how many there were and why it asks, until the minute has passed. Such a card also offers Allow
the rest (#3224): the user who asked for fifty tasks lets the area take up to BURST changes without the card for
WINDOW seconds, instead of answering each. It only waves through what Access already allows: a right set to Ask, or an
act tool, asks all the same.

And a call the user refused on the card isn't shown to them again the moment Claude repeats it: the same tool with the
same arguments is refused without a card for REFUSED_FOR seconds, so a card can't be pressed on the user until they
give in. (A longer leave to act is another matter: Dashboard #1838.)

Both are the server's own memory: a new Claude Code session starts with none, as it has made no changes yet.
"""

import json
import time
from collections import defaultdict, deque
from contextlib import contextmanager

from run import ToolError

PACE = 20            # changes an area takes in WINDOW seconds without a card
WINDOW = 60
REFUSED_FOR = 120    # seconds a refused call isn't asked again
BURST = 100          # changes Allow all lets an area make without a card, within WINDOW seconds of it


class Pace:
    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.changes = defaultdict(deque)   # area → when its changes ran, the last WINDOW seconds'
        self.refusals = {}                  # (tool, arguments as JSON) → when the user refused it
        self.grants = {}                    # area → [until, changes left]: the user's Allow all on a paced card

    def recent(self, area):
        times, now = self.changes[area], self.clock()
        while times and now - times[0] >= WINDOW:
            times.popleft()
        return len(times)

    def granted(self, area):
        """Whether the user's Allow all still holds for the area: its minute hasn't passed nor its BURST run out."""
        grant = self.grants.get(area)
        if grant and (self.clock() >= grant[0] or grant[1] <= 0):
            del self.grants[area]
            grant = None
        return grant is not None

    def due(self, tool, decision):
        """Whether this call, which Access lets run unasked, asks on the card all the same: its area has had PACE
        changes in the last minute, and the user hasn't let the rest of them through."""
        return (decision == "allow" and tool.cls == "change" and self.recent(tool.area) >= PACE
                and not self.granted(tool.area))

    def ran(self, tool):
        """A change about to run, however it was allowed: the next ones count it, and so does a grant."""
        if tool.cls == "change":
            self.changes[tool.area].append(self.clock())
            if self.granted(tool.area):
                self.grants[tool.area][1] -= 1

    def grant(self, tool):
        """The user chose Allow all on a paced card: the area's next BURST changes (this one among them) that
        Access allows run without the card for WINDOW seconds. Called only for a paced call (registry.py)."""
        self.grants[tool.area] = [self.clock() + WINDOW, BURST]

    @contextmanager
    def noted(self, tool, paced):
        """The card says why a change asks that otherwise wouldn't, and offers Allow all (confirm.card reads
        tool.paced); a call that isn't paced has none."""
        tool.paced = {"count": self.recent(tool.area), "pace": PACE, "burst": BURST} if paced else None
        try:
            yield
        finally:
            tool.paced = None

    def key(self, tool, arguments):
        return tool.name, json.dumps(arguments, sort_keys=True, ensure_ascii=False)

    def check(self, tool, arguments):
        """ToolError when the user refused this very call on the card in the last REFUSED_FOR seconds."""
        now = self.clock()
        for k in [k for k, at in self.refusals.items() if now - at >= REFUSED_FOR]:
            del self.refusals[k]
        at = self.refusals.get(self.key(tool, arguments))
        if at is not None:
            raise ToolError(f"{tool.name} wasn't run: the user refused this same call on the card {int(now - at)} s "
                            "ago, so it isn't shown to them again yet. Don't try it another way; ask them in the chat "
                            "whether they still want it.")

    def refused(self, tool, arguments):
        self.refusals[self.key(tool, arguments)] = self.clock()
