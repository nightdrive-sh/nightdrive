"""remind's events (Dashboard #3279): what tells a reminder other than its own timer. Split from `remind` so the
command stays small, as schedule_events.py is from `schedule`; it runs these as its subcommands (restore, woke,
unlocked, event, expire).

- restore: at login, timers armed again, missed times told, login's reminders told, an arrival's or a leaving's week
  timer armed again (or, past it, told as not seen).
- woke / unlocked: wake's reminders come at the first unlock after sleep; what came under the lock comes at the unlock.
- event: `places check` saw this computer arrive at or leave a place: the reminders waiting for it come now, or under
  the lock at the unlock (a banner behind the lock would ring for nobody). A row's --from (events.py) keeps it from an
  event before then.
- expire: an arrival or a leaving not seen in a week (its timer, events.deadline): the reminder comes anyway, with the
  note "Didn't arrive at work" (Jari 19.11.: it mustn't go quietly). Told, it is gone, as any reminder that came.

Each reminder is told once whoever comes first: it is taken out of the state file under its lock before it is told, so
the login's restore and its `places check --wake` (started side by side, autostart.lua) can't tell one twice, and
neither needs the other first.

Each function takes `s`, the remind script as a namespace (its state, arm, armed, disarm, tell, screen_locked…), looked
up at each use, so a test's patch of remind.X reaches here too.
"""
import os, sys, time

import events
import timers

# Set by `woke` while the lock is up: the next unlock is the first after waking. In the runtime dir, so a logout or a
# restart drops it with the session it belongs to. Remind's own: schedule's `unlocked` removes its own flag.
WOKE = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "nightdrive-remind-woke")
TRIES = 3                          # an event's banner: Quickshell may still be starting at a login's `places check`


def take(s, pick):
    """The rows pick(row) chooses, out of the state file (under its lock), so no other caller tells them again."""
    with s.state() as rows:
        out = [r for r in rows if pick(r)]
        rows[:] = [r for r in rows if r not in out]
    for r in out:
        if events.deadline(r) is not None:
            s.disarm(r["id"])   # its week's timer: it came
    return out


def note(r, now):
    """The banner's second line: why it comes now. On arriving at work; a missed time's; a week not seen."""
    if "on" not in r:
        return "Missed while you were away: due at " + timers.clock(r["at"])
    if r.get("expired"):
        # short: the banner's second line has room for little more
        return ("Didn't arrive at " if r["on"] == "arrive" else "Didn't leave ") + r["place"] + " in a week"
    return events.describe(r, now)


def tell_all(s, rows, tries=1):
    now = time.time()
    for r in rows:   # after the rows are saved: a banner that hangs doesn't keep the lock
        s.tell(r["id"], r["message"], note(r, now), tries=tries)


def restore(s):
    """At login: missed times and login's reminders told, an arrival that came under the last session's lock too; the
    timers that went with the last session armed again. Wake's reminders wait for a wake."""
    now = time.time()
    try:
        os.remove(WOKE)   # a wake before the logout isn't this session's
    except OSError:
        pass

    def due(r):
        if "on" not in r:
            return r["at"] <= now
        end = events.deadline(r)
        if end is not None and end <= now and r.get("state") is None:
            r["expired"] = True   # told with its note: the week went by while away
            return True
        return r.get("state") == "unlock" or r["on"] == "login" and events.ready(r, now)

    told = take(s, due)
    with s.state() as rows:
        for r in rows:
            if s.timed(r) and r.get("state") is None and not s.armed(r["id"]):
                s.arm(r)
    tell_all(s, told, tries=10)


def woke(s):
    """After sleep: wake's reminders come at the first unlock. Under no lock (none came before the sleep) that is now."""
    if s.screen_locked():
        with open(WOKE, "w"):
            pass
        return
    now = time.time()
    tell_all(s, take(s, lambda r: r.get("on") == "wake" and events.ready(r, now)), TRIES)


def unlocked(s):
    """At an unlock: what came under the lock, and wake's reminders if this is the first unlock after waking."""
    woken = os.path.exists(WOKE)
    if woken:
        os.remove(WOKE)
    now = time.time()
    tell_all(s, take(s, lambda r: r.get("state") == "unlock" or
                     woken and r.get("on") == "wake" and r.get("state") is None and events.ready(r, now)), TRIES)


def event(s, kind, place):
    """arrive or leave PLACE happened: its reminders come now, or wait for the unlock under the lock.
    → {event, place, told, unlock}: ids."""
    now = time.time()

    def pick(r):
        return r.get("state") is None and events.matches(r, kind, place, now)

    if s.screen_locked():
        with s.state() as rows:
            waits = [r["id"] for r in rows if pick(r)]
            for r in rows:
                if r["id"] in waits:
                    r["state"] = "unlock"
        for rid in waits:
            s.disarm(rid)   # it came: its week no longer counts
        return {"event": kind, "place": place, "told": [], "unlock": waits}
    told = take(s, pick)
    tell_all(s, told, TRIES)
    return {"event": kind, "place": place, "told": [r["id"] for r in told], "unlock": []}


def expire(s, rid):
    """An arrival's or a leaving's week is over and it still waits: told now, with why (note). Under the lock it waits
    for the unlock, as an arrival would."""
    def pick(r):
        return r["id"] == rid and r.get("state") is None and (events.deadline(r) or float("inf")) <= time.time() + 60

    if s.screen_locked():
        with s.state() as rows:
            for r in rows:
                if pick(r):
                    r["state"] = "unlock"
                    r["expired"] = True
        return
    rows = take(s, pick)
    for r in rows:
        r["expired"] = True
    tell_all(s, rows)


if __name__ == "__main__":
    sys.exit("Run by the remind command: nightdrive remind --help")
