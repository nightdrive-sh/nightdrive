"""An invitation's event put into a calendar, brought up to date there, or taken out when it is cancelled:
`calendar invite --add CALENDAR` and `--remove` (invite.py reads the file and calls run()).

What is kept of the invitation is the event's own fields (KEEP) and the time zones it uses: not its METHOD (a stored
event has none), its alarms (the sender's: the user's own reminder, or Calendar's default, applies), attachments,
or anything else a stranger's file might bring. An update keeps the alarms the user gave the event, and its file and
calendar: the event stays where it was put, whatever calendar the card picks.

A cancelled event is taken out (its file, or the one time of a recurring event: an EXDATE on it), as a stored copy of
a meeting that won't happen only misleads. Then the calendar is synced, as write.py's add does.
"""

import datetime as dt
import sys
import uuid
from pathlib import Path

import icalendar

import invite
import write

KEEP = ("uid", "dtstamp", "sequence", "summary", "dtstart", "dtend", "duration", "location", "description",
        "organizer", "attendee", "rrule", "rdate", "exdate", "recurrence-id", "status", "transp", "class",
        "categories", "created", "last-modified", "priority", "geo")


def own(event):
    """The VEVENT with only KEEP's fields, its text cut as invite.clean cuts it"""
    out = icalendar.Event()
    for key, value in event.items():
        if key.lower() in KEEP:
            out[key] = value
    for key in ("summary", "location"):
        if key in out:
            out[key] = invite.clean(out[key])
    if "description" in out:
        out["description"] = invite.clean(out["description"], invite.NOTES_MAX, True)
    if "dtstamp" not in out:
        out.add("dtstamp", dt.datetime.now(dt.timezone.utc))
    return out


def zones(ics, events):
    """The invitation's VTIMEZONEs its events use (Outlook's "FLE Standard Time" is one only the file defines)"""
    used = set()
    for e in events:
        for key in ("dtstart", "dtend", "recurrence-id"):
            if key in e and "TZID" in e[key].params:
                used.add(str(e[key].params["TZID"]))
    return [z for z in ics.walk("VTIMEZONE") if str(z.get("tzid")) in used]


def save(path, stored, cal, said):
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(stored.to_ical())
    tmp.replace(path)
    synced = write.sync(cal)
    return {"calendar": cal["id"], "calendar_name": cal["name"], "synced": synced, "said": said,
            **({} if synced else {"note": "Saved on this computer; the next sync takes it to the server."})}


def new_calendar(ics, events):
    out = icalendar.Calendar()
    out.add("prodid", write.PRODID)
    out.add("version", "2.0")
    for z in zones(ics, events):
        out.add_component(z)
    return out


def add(ics, calendar_id, info, uid, events):
    if info["state"] in ("reply", "gone", "cancelled"):
        sys.exit("A cancelled invitation, or an answer to one, has no event to add.")
    if info["state"] == "older":
        sys.exit(f"{info['existing']['calendar_name']} has a newer version of this event: nothing changed.")
    if info["state"] == "added":
        ex = info["existing"]
        return {"done": "none", "uid": uid, "calendar": ex["calendar"], "calendar_name": ex["calendar_name"],
                "synced": True, "said": f"Already in {ex['calendar_name']}: {info['title']}"}
    found = invite.find(uid)
    mine = [own(e) for e in events]
    if found is None:
        if all("recurrence-id" in e for e in events):
            sys.exit("This is one time of a recurring event that isn't in your calendar: add the event's own "
                     "invitation first.")
        cal = write.writable(calendar_id)
        stored = new_calendar(ics, events)
        for e in mine:
            stored.add_component(e)
        stored.add_missing_timezones()
        path = Path(cal["path"]) / f"{uuid.uuid4().hex.upper()}.ics"   # never a name the sender picked
        result = save(path, stored, cal, f"Added to {cal['name']}: {info['title']}")
        return {"done": "added", "uid": uid, **result}
    cal, path, old, old_events = found
    if cal["read_only"]:
        sys.exit(f"{cal['name']} is read-only here: the event can't be updated in it.")
    replaces_all = any("recurrence-id" not in e for e in events)
    alarms = [a for e in old_events if "recurrence-id" not in e for a in e.subcomponents if a.name == "VALARM"]
    gone = old_events if replaces_all else [invite.matching(old_events, e) for e in events]
    old.subcomponents = [c for c in old.subcomponents if not any(c is g for g in gone if g is not None)]
    have = {str(z.get("tzid")) for z in old.walk("VTIMEZONE")}
    for z in zones(ics, events):
        if str(z.get("tzid")) not in have:
            old.subcomponents.insert(0, z)
    for e in mine:
        if "recurrence-id" not in e:
            for a in alarms:   # the user's own reminder stays with the event
                e.add_component(a)
        old.add_component(e)
    old.add_missing_timezones()
    result = save(path, old, cal, f"Updated in {cal['name']}: {info['title']}")
    return {"done": "updated", "uid": uid, **result}


def remove(info, uid, events):
    if info["state"] != "cancelled":
        sys.exit("Only a cancelled invitation's event is removed this way, and only from the calendar it is in."
                 if info["state"] != "gone" else "The cancelled event isn't in any calendar.")
    cal, path, old, old_events = invite.find(uid)
    if cal["read_only"]:
        sys.exit(f"{cal['name']} is read-only here: the event can't be removed from it.")
    target = invite.main_part(events)
    rid = target.get("recurrence-id")
    if rid is None:
        old.subcomponents = [c for c in old.subcomponents if not (c.name == "VEVENT" and str(c.get("uid")) == uid)]
        if not any(True for _ in old.walk("VEVENT")):
            path.unlink()
            synced = write.sync(cal)
            return {"done": "removed", "uid": uid, "calendar": cal["id"], "calendar_name": cal["name"],
                    "synced": synced, "said": f"Removed from {cal['name']}: {info['title']}",
                    **({} if synced else {"note": "Removed on this computer; the next sync takes it from the server."})}
    else:
        stored = invite.matching(old_events, target)
        if stored is not None:
            old.subcomponents = [c for c in old.subcomponents if c is not stored]
        master = invite.main_part(old_events)
        if "recurrence-id" not in master:
            master.add("exdate", rid.dt)
    result = save(path, old, cal, f"Removed from {cal['name']}: {info['title']}"
                  + (f" ({info['occurrence']})" if rid is not None else ""))
    return {"done": "removed", "uid": uid, **result}


def run(ics, action, calendar_id):
    info = invite.describe(ics)
    uid, events = invite.parts(ics)
    if action == "remove":
        return remove(info, uid, events)
    return add(ics, (calendar_id or "").strip(), info, uid, events)
