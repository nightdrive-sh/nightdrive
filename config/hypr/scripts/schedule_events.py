"""schedule's events (Dashboard #3149, #3278): what runs a row other than its own timer. Split from `schedule` so the
command stays small; it runs these as its subcommands (restore, woke, unlocked, event, expire, ask).

- restore: at login, timers armed again, login's rows run, missed times run or asked (Run / Skip).
- woke / unlocked: wake's rows wait for the first unlock after sleep; what came due under the lock runs at the unlock.
- event: `places check` saw this computer arrive at or leave a place: the rows waiting for it run, or under the lock
  wait for the unlock (as a time does). A row's --from (events.py) keeps it from an event before then.
- expire: an arrival or a leaving not seen in a week (its timer, events.deadline): the row turns missed and asks, Run
  or Skip (Jari 19.11.: it mustn't go quietly). Until answered, the arrival may still come and run it.
- ask: a missed row's question.

Each row runs once whoever starts it: due() marks it under the state's lock, and `fire` takes it out under that lock
before running it, so the login's restore and its `places check --wake` (started side by side, autostart.lua) can't
run one twice, nor lose one: neither needs the other first, as the rows are in the state file.

Each function takes `s`, the schedule script as a namespace (its state, notify, start_now, screen_locked, what…), looked
up at each use, so a test's patch of schedule.X reaches here too.
"""
import os, subprocess, sys, time

import events
import timers

LATE_HOURS = 12                     # missed over a logout: run at login under this late, else asked (Jari 19.11.)
# Set by `woke` while the lock is up: the next unlock is the first after waking. In the runtime dir, so a logout or a
# restart drops it with the session it belongs to.
WOKE = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "nightdrive-schedule-woke")


def due(s, pick):
    """The rows pick(row) chooses become due and start now, each in its own service. They are marked first, under the
    lock, so a second caller (two unlocks close together) starts none twice; one whose start failed stays due, and the
    next unlock or login starts it."""
    with s.state() as rows:
        ids = [r["id"] for r in rows if pick(r)]
        for r in rows:
            if r["id"] in ids:
                r["state"] = "due"
    for rid in ids:
        s.start_now(rid)
    return ids


def restore(s):
    """At login: a timer that went with the last session is armed again; login's rows run; a time missed meanwhile runs
    if it is under LATE_HOURS late, an older one asks. Wake's rows wait for a wake."""
    now = time.time()
    try:
        os.remove(WOKE)   # a wake before the logout isn't this session's
    except OSError:
        pass

    def runs(r):
        if "on" in r:   # login's; and an arrival or a leaving that came under the last session's lock
            return r["on"] == "login" and events.ready(r, now) or r.get("state") == "unlock"
        return r["at"] <= now and r.get("state") != "missed" and now - r["at"] < LATE_HOURS * 3600

    due(s, runs)
    ask = []
    with s.state() as rows:
        for r in rows:
            end = events.deadline(r)
            if end is not None and r.get("state") in (None, "missed"):   # an arrival's or a leaving's week
                if end <= now:
                    r["state"] = "missed"
                    ask.append(r["id"])
                elif r.get("state") is None and not timers.armed(s.UNIT + r["id"]):
                    s.arm(r)
            if "on" in r or r.get("state") == "due":
                continue
            if r["at"] <= now:
                r["state"] = "missed"
                ask.append(r["id"])
            elif not timers.armed(s.UNIT + r["id"]):
                r.pop("state", None)
                s.arm(r)
    for rid in ask:
        ask_later(s, rid)


def ask_later(s, rid):
    # Each its own question, in the background: an unanswered one mustn't hold the others, nor the login
    subprocess.Popen([s.SELF, "ask", rid], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def ask(s, rid):
    """A missed one's question: Run or Skip. Dismissed, it stays in the list as missed (schedule run / cancel)."""
    with s.state() as rows:
        r = next((r for r in rows if r["id"] == rid and r.get("state") == "missed"), None)
    if not r:
        return
    if "on" in r:   # an arrival or a leaving that hasn't come in a week
        summary = ("You didn't arrive at " if r["on"] == "arrive" else "You didn't leave ") + r["place"] + ": "
        body = "Waiting since " + events.day_clock(r.get("from") or r["added"], time.time())
    else:
        summary = "Missed: "
        body = f"Was due {timers.iso(r['at'])[:16].replace('T', ' at ')}, while the computer was off"
    answer = s.notify(r["id"], summary + s.what(r), body + s.by_claude(r),
                      pinned=True, actions=[("run", "Run"), ("skip", "Skip")])
    if answer == "run":
        due(s, lambda x: x["id"] == r["id"] and x.get("state") == "missed")
    elif answer == "skip":
        with s.state() as rows:
            rows[:] = [x for x in rows if x["id"] != r["id"]]


def woke(s):
    """After sleep: wake's rows run at the first unlock. Under no lock (none came before the sleep) that is now."""
    if s.screen_locked():
        with open(WOKE, "w"):
            pass
    else:
        now = time.time()
        due(s, lambda r: r.get("on") == "wake" and events.ready(r, now))


def unlocked(s):
    """At an unlock: what came due under the lock runs, and wake's rows if this is the first unlock after waking."""
    woken = os.path.exists(WOKE)
    if woken:
        os.remove(WOKE)
    now = time.time()
    due(s, lambda r: r.get("state") in ("unlock", "due") or woken and r.get("on") == "wake" and events.ready(r, now))


def event(s, kind, place):
    """arrive or leave PLACE happened: its rows run now, or wait for the unlock under the lock. A missed one (its week
    passed, its question unanswered) runs too: the arrival came after all. → {event, place, due, unlock}: ids."""
    now = time.time()

    def pick(r):
        return r.get("state") in (None, "missed") and events.matches(r, kind, place, now)

    if s.screen_locked():
        with s.state() as rows:
            waits = [r["id"] for r in rows if pick(r)]
            for r in rows:
                if r["id"] in waits:
                    r["state"] = "unlock"
        ran = []
    else:
        waits, ran = [], due(s, pick)
    for rid in waits + ran:
        s.disarm(rid)   # its week's timer: it came
    return {"event": kind, "place": place, "due": ran, "unlock": waits}


def expire(s, rid):
    """An arrival's or a leaving's week is over and it still waits: missed, and asked now (in this timer's service:
    a question started apart from it would go when the service ends)."""
    with s.state() as rows:
        r = next((r for r in rows if r["id"] == rid and "state" not in r), None)
        if not r or (events.deadline(r) or float("inf")) > time.time() + 60:   # came, cancelled, or not its week yet
            return
        r["state"] = "missed"
    ask(s, rid)


if __name__ == "__main__":
    sys.exit("Run by the schedule command: nightdrive schedule --help")
