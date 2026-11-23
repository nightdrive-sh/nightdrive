"""When the computer arrives at a place or leaves one (Dashboard #3277, part 2 of #3275): the rules only, no D-Bus, no
files, so they can be tested (place_rules_test.py). `places check` (place_check.py) feeds them and acts on the result.

The inputs: the state kept between checks (place → here, last_seen, missing_since), the places (places.json), the
SSIDs connected now, the time, and whether this check is for going to sleep or for waking (a login counts as waking).

- Arriving: the computer is on one of the place's networks after being away from it more than ARRIVE_GAP, counted on
  the wall clock, sleep included. Lid shut at work on Friday and opened at work on Monday is an arrival; a nap at lunch
  at work isn't. Being away is "not here" or "here, but not seen since the network went": a short blip, or a sleep,
  ends in an arrival only when it lasted ARRIVE_GAP.
- Leaving: the place's networks have been gone for LEAVE_HOLD. A Wi-Fi blip or a hop between access points isn't a
  leaving; the caller checks again at `next_check` (a timer), so a leaving is told even when nothing else happens.
- Waking (and login) starts the leave clock afresh for the places it was at: the network gets LEAVE_HOLD to come up
  (well over net-watch's GRACE) before the place counts as left, and waking somewhere else is a leaving after it.
- A check that finds the state still asleep (the wake was missed: a leave timer firing as the computer woke, before
  net-watch's signal) counts as the wake first, so a timer from before the sleep can't tell a leaving at once.
- A place the state doesn't know yet (just added) is taken as it is, without an event: naming the network you're on
  isn't arriving there. One that went from places.json leaves the state without a word.
- Each place is its own question: one SSID may be in two places (places.py), and both arrive together.

At most one event per place per check, and only on a change: an arrival makes it "here", so it doesn't repeat.
"""

ARRIVE_GAP = 2 * 3600   # s away from a place before coming back counts as arriving (a lunch nap doesn't, a weekend does)
LEAVE_HOLD = 3 * 60     # s a place's networks must be gone before it is left (a blip, a reconnect, waking up)


def _known(state):
    places = state.get("places")
    return places if isinstance(places, dict) else {}


def _wake(places, now):
    """Waking or a login: the places it was at may still be there, once the network is up. Their leave clocks start
    now; last_seen stays the moment it went to sleep, which decides whether coming back is an arrival."""
    for s in places.values():
        if s.get("here"):
            s["missing_since"] = now


def _sleep(places, now):
    """Going to sleep: it was at the places it is at until now (unless their network had gone already: then it was
    there until that went)."""
    for s in places.values():
        if s.get("here") and s.get("missing_since") is None:
            s["last_seen"] = now


def step(state, rows, wifi, now, event=None):
    """One check. state: the dict kept between checks (changed in place; {} at first). rows: the places
    ([{name, wifi}], places.load()). wifi: the SSIDs now. event: None, "sleep" or "wake" (also a login).
    → (events, next_check): events as [("arrive" | "leave", name)], in the order of the places; next_check the Unix
    time to check again for a pending leaving, or None."""
    places = _known(state)
    state["places"] = places
    if event == "sleep":
        _sleep(places, now)
        state["asleep"] = True
        return [], None
    if event == "wake" or state.get("asleep"):
        _wake(places, now)
    state["asleep"] = False

    # The state follows places.json: names as written there now, gone places dropped
    names = {r["name"] for r in rows}
    for name in [n for n in places if n not in names]:
        del places[name]

    events, due = [], []
    now_wifi = set(wifi)
    for r in rows:
        name = r["name"]
        present = bool(set(r["wifi"]) & now_wifi)
        s = places.get(name)
        if s is None:
            # New to the state: taken as it is, no event
            places[name] = {"here": present, "last_seen": now if present else None, "missing_since": None}
            continue
        if present:
            away = not s.get("here") or s.get("missing_since") is not None
            last = s.get("last_seen")
            if away and (last is None or now - last > ARRIVE_GAP):
                events.append(("arrive", name))
            s.update(here=True, last_seen=now, missing_since=None)
        elif s.get("here"):
            if s.get("missing_since") is None:
                # Just gone: it was there until now, and the leave clock starts
                s["missing_since"] = now
                s["last_seen"] = now
            if now - s["missing_since"] >= LEAVE_HOLD:
                events.append(("leave", name))
                s.update(here=False, missing_since=None)
            else:
                due.append(s["missing_since"] + LEAVE_HOLD)
    return events, (min(due) if due else None)


def here(state):
    """The places the state counts as here now (a pending leaving included: it isn't told yet)."""
    return [n for n, s in _known(state).items() if s.get("here")]
