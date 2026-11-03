"""When net-watch tells the user the internet went or came back (#2057): the rules only, no D-Bus, so they can be
tested (net_watch_rules_test.py: `python3 config/hypr/scripts/net_watch_rules_test.py`).

The inputs are NetworkManager's own: its connectivity check (full / limited / portal / none / unknown) and whether a
connection is up at all (networking on and its State at least CONNECTED_LOCAL), plus logind's PrepareForSleep. A drop
says so only when it holds for DEBOUNCE seconds, and never in the GRACE after login or waking up, when every network
starts out with no internet for a while. A connection that goes down (Wi-Fi turned off, the network out of reach) is
not "the internet dropped": the bar shows that, and a notification already shown is taken away without a word.
"""

DEBOUNCE = 10    # s a drop must hold before it is told: a blip goes unseen
PORTAL_HOLD = 2  # s for a captive portal: NM saw the redirect, it's no blip, and the sign-in should come soon
GRACE = 30       # s after login or waking with no "lost": the network is still coming up

# NetworkManager's NMConnectivityState and NMState (D-Bus numbers)
UNKNOWN, NONE, PORTAL, LIMITED, FULL = 0, 1, 2, 3, 4
CONNECTED_LOCAL = 50


class Watch:
    """step() takes what changed and returns (actions, wake_at): actions from "lost", "portal" (shown: replaces the
    other), "back" (the one shown goes, a transient says so) and "clear" (it goes silently); wake_at is the time to call
    step() again with nothing new, when a pending drop would be due, or None."""

    def __init__(self, now):
        self.conn = UNKNOWN
        self.up = False
        self.asleep = False
        self.grace_until = now + GRACE
        self.shown = None          # "lost" | "portal" | None: the notification on screen now
        self.bad = None            # the kind of trouble now, and since when
        self.bad_since = 0.0

    def step(self, now, conn=None, up=None, asleep=None):
        out = []
        if asleep is not None and asleep != self.asleep:
            self.asleep = asleep
            if asleep:
                # Off to sleep: what was shown is old news by the time it wakes, and the network goes down anyway
                if self.shown:
                    out.append("clear")
                self.shown = self.bad = None
            else:
                self.grace_until = now + GRACE
        if conn is not None:
            self.conn = conn
        if up is not None:
            self.up = up
        acts, wake = self._eval(now)
        return out + acts, wake

    def _eval(self, now):
        if self.asleep:
            return [], None
        if not self.up:
            self.bad = None
            if self.shown:
                self.shown = None
                return ["clear"], None
            return [], None
        kind = "portal" if self.conn == PORTAL else "lost" if self.conn in (NONE, LIMITED) else None
        if kind is None:   # full, or unknown (NM has no check configured): nothing to say
            self.bad = None
            if self.shown:
                self.shown = None
                return ["back"], None
            return [], None
        if kind != self.bad:
            self.bad, self.bad_since = kind, now
        if self.shown == kind:
            return [], None
        # A portal doesn't wait for the grace: after waking in a hotel the sign-in is what's needed first
        due = self.bad_since + PORTAL_HOLD if kind == "portal" else max(self.bad_since + DEBOUNCE, self.grace_until)
        if now >= due:
            self.shown = kind
            return [kind], None
        return [], due
