#!/usr/bin/env python3
"""A reminder's notification, waiting for its buttons in a process of its own (remind.py starts it by systemd-run).

    notice.py one ALARM      one event: its title, when it starts and where; Open shows it in Calendar, Snooze
                             brings it back in SNOOZE minutes, and Join, for one with a meeting link, opens the call
                             (#3444). The join notification a minute before (kind "join") has Join and Open only
    notice.py many ALARMS    several at once (a computer that was off): one notification, Open shows today's agenda

ALARM is remind.py's plan entry as JSON. When the event starts is written as it is at the moment the notification
shows ("In 15 min", "Now", "Started 10 min ago"), the times and days the region's way (the kit's region.py, Settings ›
Region). A normal notification (#1982): Do Not Disturb holds it, as it does other apps'.
"""

import datetime as dt
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import remind

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "app" / "kit"))
import region  # noqa: E402

COMMAND = Path(__file__).resolve().parents[1] / "bin/calendar"
ICON = "lucide:calendar"
SNOOZE = 5      # minutes


def day_name(d, today, r):
    if d == today:
        return "Today"
    if d == today + dt.timedelta(days=1):
        return "Tomorrow"
    if 0 < (d - today).days < 7:
        return region.fmt(d, "ddd " + r["day"])
    return region.fmt(d, r["short"])


def when(a, now):
    """The first line: how far off the start is, and the times. "In 15 min · 14:00–15:00", "Tomorrow, all day" """
    r = region.current()
    start, end = dt.datetime.fromisoformat(a["start"]), dt.datetime.fromisoformat(a["end"])
    if a["all_day"]:
        last = (end - dt.timedelta(days=1)).date()
        text = day_name(start.date(), now.date(), r) + ", all day"
        return text if last == start.date() else f"{text} until {day_name(last, now.date(), r)}"
    times = f"{region.fmt(start, r['time'])}–{region.fmt(end, r['time'])}"
    if start.date() != now.date():
        times = f"{day_name(start.date(), now.date(), r)} {times}"
    minutes = round((start - now).total_seconds() / 60)
    if minutes > 0 and start.date() != now.date():
        return times   # another day's (a reminder a day before): its day says it better than "In 25 h"
    if minutes > 0:
        hours, rest = divmod(minutes, 60)
        off = f"In {minutes} min" if minutes < 60 else f"In {hours} h" + (f" {rest} min" if rest else "")
    elif minutes == 0:
        off = "Now"
    else:
        off = f"Started {-minutes} min ago" if -minutes < 60 else "Started"
    return f"{off} · {times}"


def notify(tag, summary, body, actions):
    """The action pressed, or None once the row has gone (dismissed, replaced, expired)"""
    cmd = ["notify-send", "-a", "Calendar", "-i", ICON, "-h", f"string:x-dunst-stack-tag:calendar-{tag}", "-w"]
    for key, name in actions:
        cmd += ["-A", f"{key}={name}"]
    try:
        # -- first: a title that starts with - is the text, not an option (#1863)
        out = subprocess.run(cmd + ["--", summary, body], stdin=subprocess.DEVNULL, capture_output=True,
                             text=True).stdout
    except OSError:
        return None
    return out.strip() or None


def actions(a):
    """The buttons: Join first when there is a call to join, as it is what the notification is for a minute before"""
    out = [("default", "Open")]
    if (a.get("meeting") or {}).get("url"):
        out.append(("join", "Join"))
    out.append(("open", "Open"))
    if a.get("kind") != "join":   # a minute before the start, five more would be too late
        out.append(("snooze", "Snooze"))
    return out


def join(a):
    """The call in the browser: only a web address, as it comes from whoever sent the invitation"""
    url = ((a.get("meeting") or {}).get("url") or "").strip()
    if url.lower().startswith(("https://", "http://")):
        subprocess.run(["xdg-open", url], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)


def snooze(a):
    until = dt.datetime.now().astimezone() + dt.timedelta(minutes=SNOOZE)
    snoozed = remind.read(remind.SNOOZED, {})
    snoozed[a["key"]] = {"until": until.isoformat(), "alarm": a}
    remind.store(remind.SNOOZED, snoozed)


def one(a):
    now = dt.datetime.now().astimezone()
    place = (a.get("location") or "").split("\n")[0]
    body = "\n".join(x for x in [when(a, now), place] if x)
    # The same tag for the same reminder: a snoozed one coming back takes the place of its row
    pressed = notify(hashlib.sha1(a["key"].encode()).hexdigest()[:12], a["title"] or "An event", body, actions(a))
    if pressed == "join":
        join(a)
    elif pressed == "snooze":
        snooze(a)
    elif pressed in ("default", "open"):   # a click on it, or its button
        subprocess.run([str(COMMAND), "open-event", a["calendar"], a["uid"], a["day"]])


def many(alarms):
    now = dt.datetime.now().astimezone()
    r = region.current()
    rows = [(region.fmt(dt.datetime.fromisoformat(a["start"]), r["time"]) + "  " if not a["all_day"] else "")
            + (a["title"] or "An event") for a in alarms]
    body = "\n".join(rows[:5]) + (f"\n…and {len(rows) - 5} more" if len(rows) > 5 else "")
    if notify("many", f"{len(alarms)} reminders", body, [("default", "Open"), ("open", "Open")]) in ("default", "open"):
        subprocess.run([str(COMMAND), "show", now.date().isoformat()])
        subprocess.run([str(COMMAND), "agenda"])


if __name__ == "__main__":
    cmd, rest = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "one" and len(rest) == 1:
        one(json.loads(rest[0]))
    elif cmd == "many" and len(rest) == 1:
        many(json.loads(rest[0]))
    else:
        sys.exit("usage: notice.py one ALARM | many ALARMS")
