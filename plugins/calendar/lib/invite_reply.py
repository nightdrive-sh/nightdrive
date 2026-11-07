"""Answering an invitation (#2130): the iTIP REPLY that tells its organiser Accepted, Maybe or Declined, and the answer
kept in the event's copy in a calendar. `calendar invite` calls it (invite.py reads the file):

    invite.py [FILE|-] --as ADDRESS [--json]          the invitation, with reply: whether and how it can be answered
    invite.py [FILE|-] --reply ANSWER --as ADDRESS [--name NAME]
                                                      the REPLY to send, as JSON: {to, to_name, subject, body, ics, …};
                                                      nothing is written or sent
    invite.py [FILE|-] --answered ANSWER --as ADDRESS [--add CALENDAR]
                                                      once the REPLY has gone: the answer in the event's copy, which an
                                                      Accept or Maybe puts in CALENDAR first when it isn't in one yet

ANSWER is accept, maybe or decline (PARTSTAT ACCEPTED, TENTATIVE, DECLINED). ADDRESS is the mail account the
invitation came to: the reply answers for that one invitee. Sending is Mail's (its lib/invitation_reply.py), only when
the user presses a button or allows Claude's call on Nightdrive's card: this file never sends anything.

The REPLY carries what RFC 5546 asks of one (UID, SEQUENCE, DTSTAMP, ORGANIZER, the one ATTENDEE with its PARTSTAT,
RECURRENCE-ID for one time of a recurring event) and the event's time and title, which Outlook shows with it; never the
sender's notes, alarms or links back.
"""

import datetime as dt
import json
import re
import sys

import icalendar

import invite
import write

ANSWERS = {"accept": "ACCEPTED", "maybe": "TENTATIVE", "decline": "DECLINED"}
WORDS = {"ACCEPTED": "Accepted", "TENTATIVE": "Tentative", "DECLINED": "Declined"}   # the subject's, as Outlook's
VERBS = {"ACCEPTED": "accepted", "TENTATIVE": "tentatively accepted", "DECLINED": "declined"}
ADDRESS = re.compile(r"^[^@\s<>\"]+@[^@\s<>\"]+\.[^@\s<>\"]+$")


def address_of(value):
    return re.sub(r"^mailto:", "", str(value or ""), flags=re.I).strip().lower()


def attendees(event):
    found = event.get("attendee") or []
    return found if isinstance(found, list) else [found]


def me(event, address):
    """The event's ATTENDEE that is ADDRESS, or None"""
    return next((a for a in attendees(event) if address_of(a) == address.lower()), None)


def status(ics, info, address):
    """For the card: {can, why, answer, to, as}: whether ADDRESS can answer it, and the answer given already (the
    event's copy in a calendar has the last one sent from here, else the invitation's own)"""
    out = {"can": False, "why": "", "answer": None, "to": "", "as": address}
    organizer = info["organizer"]
    if info["method"] != "REQUEST":
        out["why"] = "Only an invitation (REQUEST) is answered."
        return out
    if not organizer or not ADDRESS.match(organizer["address"]):
        out["why"] = "The invitation has no organiser to answer."
        return out
    out["to"] = organizer["address"]
    if organizer["address"].lower() == address.lower():
        out["why"] = "You organise it."
        return out
    uid, events = invite.parts(ics)
    target = invite.main_part(events)
    found = invite.find(uid)
    stored = invite.matching(found[3], target) if found else None
    for event in (stored, target):
        mine = me(event, address) if event is not None else None
        if mine is not None and str(mine.params.get("PARTSTAT", "")).upper() in WORDS:
            out["answer"] = str(mine.params["PARTSTAT"]).upper()
            break
    out["can"] = True
    return out


def partstat(answer):
    key = (answer or "").strip().lower()
    if key in ANSWERS:
        return ANSWERS[key]
    if key.upper() in WORDS:
        return key.upper()
    sys.exit(f"The answer is accept, maybe or decline, not {answer!r}.")


def attendee(event, address, name, state):
    """This invitee's ATTENDEE with the answer: the invitation's own line for them when it has one (its address as
    written, its name), else one for ADDRESS (an invitation sent to a list or an alias)"""
    found = me(event, address)
    value = icalendar.vCalAddress(str(found) if found is not None else f"mailto:{address}")
    cn = found.params.get("CN") if found is not None else None
    if cn or name:
        value.params["CN"] = invite.clean(cn or name)
    value.params["PARTSTAT"] = state
    return value, found is not None


def build(ics, answer, address, name=""):
    """The REPLY to send: {to, to_name, subject, body, ics, answer, uid, listed}; exits when it can't be answered"""
    if not ADDRESS.match(address or ""):
        sys.exit("Answering needs the address the invitation came to (--as ADDRESS).")
    info = invite.describe(ics)
    can = status(ics, info, address)
    if not can["can"]:
        sys.exit(can["why"])
    state = partstat(answer)
    uid, events = invite.parts(ics)
    target = invite.main_part(events)
    event = icalendar.Event()
    event.add("uid", uid)
    event.add("dtstamp", dt.datetime.now(dt.timezone.utc))
    event.add("sequence", invite.seq(target))
    for key in ("recurrence-id", "dtstart", "dtend", "duration"):
        if key in target:
            event[key] = target[key]
    event.add("summary", info["title"])
    organizer = icalendar.vCalAddress(f"mailto:{info['organizer']['address']}")   # cleaned: no stranger's control marks
    if info["organizer"]["name"]:
        organizer.params["CN"] = info["organizer"]["name"]
    event["organizer"] = organizer
    who, listed = attendee(target, address, name, state)
    event.add("attendee", who)
    reply = icalendar.Calendar()
    reply.add("prodid", write.PRODID)
    reply.add("version", "2.0")
    reply.add("method", "REPLY")
    import invite_write   # its zones(): the VTIMEZONEs the times name, which only the invitation may define
    for zone in invite_write.zones(ics, [target]):
        reply.add_component(zone)
    reply.add_component(event)
    o = info["organizer"]
    when = write.span(*_bounds(info))
    me_name = invite.clean(name) or address
    return {"to": o["address"], "to_name": o["name"], "answer": state, "uid": uid, "listed": listed,
            "subject": f"{WORDS[state]}: {info['title']}",
            "body": f"{me_name} has {VERBS[state]} this invitation.\n\n{info['title']}\n{when}"
                    + (f"\n{info['location']}" if info["location"] else "") + "\n",
            "ics": reply.to_ical().decode()}


def _bounds(info):
    """start and last as dates or datetimes again, for write.span's words"""
    parse = dt.date.fromisoformat if info["all_day"] else dt.datetime.fromisoformat
    return parse(info["start"]), parse(info["end"])


def answered(ics, answer, address, calendar_id=None):
    """The answer kept in the event's copy, once the REPLY has gone; an Accept or Maybe of one in no calendar puts it in
    calendar_id first. {done, said, …}: the mail is out already, so a calendar that can't take it is a note, not a
    failure"""
    state = partstat(answer)
    info = invite.describe(ics)
    uid, events = invite.parts(ics)
    target = invite.main_part(events)
    found = invite.find(uid)
    if found is None:
        if state == "DECLINED" or not calendar_id:
            return {"done": "none", "said": f"{WORDS[state]}: {info['title']}"}
        import invite_write
        invite_write.run(ics, "add", calendar_id)
        found = invite.find(uid)
    cal, path, stored, old_events = found
    if cal["read_only"]:
        return {"done": "none", "said": f"{WORDS[state]}: {info['title']}",
                "note": f"{cal['name']} is read-only here, so it doesn't show your answer."}
    # One time's answer goes on that time; the event's on each of its VEVENTs, as the organiser's copy has it
    rid = target.get("recurrence-id")
    chosen = [invite.matching(old_events, target)] if rid is not None else old_events
    marked = 0
    for event in filter(None, chosen):
        mine = me(event, address)
        if mine is not None:
            mine.params["PARTSTAT"] = state
            mine.params.pop("RSVP", None)
            marked += 1
        elif "recurrence-id" not in event or rid is not None:
            event.add("attendee", attendee(event, address, "", state)[0])
            marked += 1
    if not marked:
        return {"done": "none", "said": f"{WORDS[state]}: {info['title']}"}
    import invite_write
    result = invite_write.save(path, stored, cal, f"{WORDS[state]}: {info['title']}")
    return {"done": "answered", "uid": uid, **result}


def main(args, as_json):
    """invite.py's --reply and --answered (and their --as, --name, --add), args without --json"""
    def take(flag):
        if flag not in args:
            return None
        i = args.index(flag)
        if i + 1 >= len(args):
            sys.exit(f"{flag} needs a value.")
        value = args[i + 1]
        del args[i:i + 2]
        return value

    reply, done = take("--reply"), take("--answered")
    address, name, calendar_id = (take("--as") or "").strip(), take("--name") or "", take("--add")
    if len(args) > 1 or (reply is None) == (done is None):
        sys.exit(__doc__)
    ics = invite.read(args[0] if args else "-")
    if reply is not None:
        out = build(ics, reply, address, name)
        print(json.dumps(out, ensure_ascii=False) if as_json else out["ics"])
        return
    if not ADDRESS.match(address):
        sys.exit("--answered needs the address that answered (--as ADDRESS).")
    out = answered(ics, done, address, calendar_id)
    print(json.dumps(out, ensure_ascii=False) if as_json else out["said"])
