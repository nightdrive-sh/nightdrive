#!/usr/bin/env python3
"""The events' alarms (VALARM): read for the reminders (remind.py) and the window's editor (events.py), written by the
editor's Reminder (write.py, change.py).

A reminder is kept as minutes before the event's start: 15 is a quarter before, 0 at the start; an all-day event's
start is its midnight, so -540 is 9:00 on the day and 900 9:00 the day before (the phone's "On day of event" and "1 day
before"). None is no reminder.

    Files()                        the .ics files of the calendars, each read once: .event(cal, uid, start)
    times(vevent, start, end)      when its alarms go off for the time starting at start: [aware datetime]
    reminder(vevent) -> int|None   its first alarm, in minutes before the start (the editor's field)
    set_reminder(vevent, minutes)  its alarms replaced by that one, or by none

What counts as an alarm: DISPLAY and AUDIO (the phone's sound alert), relative to the start or the end, or at a time.
Not Apple's placeholders: ACTION:NONE, or a time in 1976; nor a snooze another device added (RELATED-TO), which that
device rings. One dismissed on another device (ACKNOWLEDGED at or after its time) has been seen there.
"""

import datetime as dt
import uuid
from pathlib import Path

import icalendar

import write

RINGS = ("DISPLAY", "AUDIO")


def local(value):
    """A start or end as an aware local datetime: a day is its midnight, a floating time local time"""
    zone = write.local_zone()
    if isinstance(value, dt.datetime):
        return value.astimezone(zone) if value.tzinfo else value.replace(tzinfo=zone)
    return dt.datetime.combine(value, dt.time(), tzinfo=zone)


def ringing(alarm):
    if str(alarm.get("action", "")).upper() not in RINGS or "related-to" in alarm or "trigger" not in alarm:
        return False
    when = alarm.decoded("trigger")
    return not (isinstance(when, dt.datetime) and when.year < 2000)


def times(vevent, start, end):
    out = []
    for alarm in vevent.walk("VALARM"):
        if not ringing(alarm):
            continue
        trigger = alarm.decoded("trigger")
        if isinstance(trigger, dt.timedelta):
            related = str(alarm["trigger"].params.get("RELATED", "START")).upper()
            at = (end if related == "END" else start) + trigger
        else:
            at = local(trigger)
        if "acknowledged" in alarm:
            try:
                if local(alarm.decoded("acknowledged")) >= at:
                    continue
            except (TypeError, ValueError):
                pass
        out.append(at)
    return sorted(set(out))


def reminder(vevent):
    for alarm in vevent.walk("VALARM"):
        if ringing(alarm):
            trigger = alarm.decoded("trigger")
            related = str(alarm["trigger"].params.get("RELATED", "START")).upper()
            if isinstance(trigger, dt.timedelta) and related == "START":
                return int(-trigger.total_seconds() // 60)
            return None   # at a time, or before the end: the editor's choices don't say it
    return None


def set_reminder(vevent, minutes):
    """Every alarm out (but Apple's placeholder, which the phone keeps for itself) and the one in"""
    vevent.subcomponents = [c for c in vevent.subcomponents
                            if c.name != "VALARM" or str(c.get("action", "")).upper() == "NONE"]
    if minutes is None:
        return
    alarm = icalendar.Alarm()
    alarm.add("uid", str(uuid.uuid4()).upper())
    alarm.add("action", "DISPLAY")
    alarm.add("description", "Reminder")
    alarm.add("trigger", dt.timedelta(minutes=-int(minutes)))
    vevent.add_component(alarm)


def minutes(value):
    """A reminder as JSON gives it: an integer, or None ("none", null, ""); exits with what it takes otherwise"""
    if value is None or value == "" or str(value).lower() == "none":
        return None
    try:
        m = int(value)
    except (TypeError, ValueError):
        raise SystemExit(f"reminder is minutes before the start (0 at the start), or null for none: not {value!r}.")
    if not -1440 < m <= 40320:   # from the day's end to four weeks before
        raise SystemExit("reminder is at most four weeks (40320 minutes) before the start.")
    return m


class Files:
    """The calendars' events by uid, each folder indexed and each file parsed once a run: the reminders look at a
    week of events, many in the same files (a recurring one, an ICS address's single calendar)"""

    def __init__(self, cals):
        self.cals = {c["id"]: c for c in cals}
        self.index = {}    # calendar id: {uid: path}
        self.parsed = {}   # path: [VEVENT]

    def vevents(self, cal_id, uid):
        cal = self.cals.get(cal_id)
        if cal is None:
            return []
        direct = Path(cal["path"]) / f"{uid}.ics"
        path = direct if direct.is_file() else self.lookup(cal, uid)
        if path is None:
            return []
        if path not in self.parsed:
            try:
                self.parsed[path] = list(icalendar.Calendar.from_ical(path.read_bytes()).walk("VEVENT"))
            except (OSError, ValueError):
                self.parsed[path] = []
        return [e for e in self.parsed[path] if str(e.get("uid")) == uid]

    def lookup(self, cal, uid):
        """A file not named by its uid (vdirsyncer keeps the server's names): the folder read once for all of them"""
        if cal["id"] not in self.index:
            found = {}
            for path in Path(cal["path"]).glob("*.ics"):
                try:
                    for line in path.read_text(errors="replace").splitlines():
                        if line.startswith("UID:"):
                            found.setdefault(line[4:].strip(), path)
                except OSError:
                    continue
            self.index[cal["id"]] = found
        return self.index[cal["id"]].get(uid)

    def event(self, cal_id, uid, start):
        """The VEVENT of the time starting at start (an aware datetime): a changed occurrence's own, else the event's"""
        found = self.vevents(cal_id, uid)
        for e in found:
            if "recurrence-id" in e and "dtstart" in e and local(e.decoded("dtstart")) == start:
                return e
        return next((e for e in found if "recurrence-id" not in e), found[0] if found else None)
