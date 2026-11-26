#!/usr/bin/env python3
"""A VTODO in an .ics file, read and written with the standard library (RFC 5545): one task per file, as a vdir keeps
them, so CalDAV (vdirsyncer) or another app can sync the same files later without a conversion.

A task is kept as its lines, so what Nightdrive doesn't know (VALARM, RRULE, an app's own X- fields, the VCALENDAR's
VTIMEZONE) is written back as it came: Tasks only changes the properties it sets. Task(text) reads one, .get()/.set()
change a property, str(task) writes the whole file again.
"""

import re
import uuid
from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

PRODID = "-//Nightdrive//Tasks//EN"
FOLD = 75   # octets a content line may take before it is folded


class Line:
    """One content line: NAME;PARAM=VALUE:value, the value still escaped as in the file"""

    def __init__(self, name, params=None, value=""):
        self.name, self.params, self.value = name.upper(), dict(params or {}), value

    @classmethod
    def parse(cls, text):
        # The value starts at the first colon outside a quoted parameter
        quoted, cut = False, len(text)
        for i, ch in enumerate(text):
            if ch == '"':
                quoted = not quoted
            elif ch == ":" and not quoted:
                cut = i
                break
        head, value = text[:cut], text[cut + 1:]
        parts = re.findall(r'(?:[^;"]|"[^"]*")+', head)
        params = {}
        for p in parts[1:]:
            k, _, v = p.partition("=")
            params[k.upper()] = v.strip('"')
        return cls(parts[0] if parts else head, params, value)

    def __str__(self):
        head = self.name + "".join(f";{k}={quote(v)}" for k, v in self.params.items())
        return fold(f"{head}:{self.value}")


def quote(v):
    return f'"{v}"' if re.search(r'[;:,]', v) else v


def fold(line):
    """Lines past 75 octets go on with a space, cut between characters, not inside one"""
    out, cur = [], ""
    for ch in line:
        if len((cur + ch).encode()) > (FOLD if not out else FOLD - 1):
            out.append(cur)
            cur = ""
        cur += ch
    out.append(cur)
    return "\r\n ".join(out)


# Every character Python's splitlines() would end a line at: CRLF and CR, VT, FF, the file, group and record
# separators, NEL and Unicode's line and paragraph separators. escape() writes each as \n (a backslash and an n), so a
# title or note can't end its own line and start a property (END:VTODO, STATUS, a VALARM) in a reader that splits
# there, as unfold() did (#1925).
BREAKS = re.compile("\r\n|[\n\r\x0b\x0c\x1c-\x1e\x85\u2028\u2029]")


def unfold(text):
    # Lines end at CRLF (or a bare LF) only, as RFC 5545 has them: a value written by another app with one of the
    # other BREAKS in it stays one value, where splitlines() would have read the rest as a line of its own
    return re.split(r"\r?\n", re.sub(r"\r?\n[ \t]", "", text))


def escape(text):
    text = text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,")
    return BREAKS.sub(r"\\n", text)


def unescape(value):
    return re.sub(r"\\([\\;,nN])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), value)


def local_zone():
    return datetime.now().astimezone().tzinfo


def parse_time(line):
    """A DATE or DATE-TIME as a date (all-day) or a naive local datetime; None if it can't be read"""
    v = line.value.strip()
    try:
        if line.params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", v):
            return datetime.strptime(v[:8], "%Y%m%d").date()
        t = datetime.strptime(v[:15], "%Y%m%dT%H%M%S")
    except ValueError:
        return None
    if v.endswith("Z"):
        return t.replace(tzinfo=timezone.utc).astimezone(local_zone()).replace(tzinfo=None)
    if "TZID" in line.params:
        try:
            return t.replace(tzinfo=ZoneInfo(line.params["TZID"])).astimezone(local_zone()).replace(tzinfo=None)
        except (KeyError, ValueError):
            pass   # a zone the system doesn't know (an Outlook name): taken as local
    return t


def time_line(name, when):
    """A date as an all-day VALUE=DATE; a time as floating local time, which every client reads as the user's own"""
    if isinstance(when, datetime):
        return Line(name, {}, when.strftime("%Y%m%dT%H%M%S"))
    return Line(name, {"VALUE": "DATE"}, when.strftime("%Y%m%d"))


def stamp():
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


class Task:
    """The file's lines, with the VTODO's own (not those of a VALARM inside it) reachable by name"""

    def __init__(self, text):
        self.lines = [Line.parse(t) for t in unfold(text) if t.strip()]
        begins = [i for i, l in enumerate(self.lines) if l.name == "BEGIN" and l.value.upper() == "VTODO"]
        if not begins:
            raise ValueError("no VTODO in it")
        self.start = begins[0]

    @classmethod
    def new(cls, summary):
        text = "\r\n".join(["BEGIN:VCALENDAR", "VERSION:2.0", f"PRODID:{PRODID}", "BEGIN:VTODO",
                            f"UID:{uuid.uuid4()}", f"DTSTAMP:{stamp()}", f"CREATED:{stamp()}",
                            "STATUS:NEEDS-ACTION", "END:VTODO", "END:VCALENDAR"])
        task = cls(text)
        task.set("SUMMARY", summary)
        return task

    def own(self):
        """Indexes of the VTODO's lines, without its nested components (VALARM)"""
        depth = 0
        for i in range(self.start + 1, len(self.lines)):
            l = self.lines[i]
            if l.name == "END" and depth == 0:
                return
            if l.name == "BEGIN":
                depth += 1
            elif l.name == "END":
                depth -= 1
            elif depth == 0:
                yield i

    def line(self, name):
        return next((self.lines[i] for i in self.own() if self.lines[i].name == name), None)

    def get(self, name, default=""):
        l = self.line(name)
        return unescape(l.value) if l else default

    def time(self, name):
        l = self.line(name)
        return parse_time(l) if l else None

    def remove(self, name):
        own = set(self.own())
        self.lines = [l for i, l in enumerate(self.lines) if not (l.name == name and i in own)]

    def put(self, line):
        """Replaces the property, or adds it before the VTODO's nested parts and its END"""
        idx = [i for i in self.own() if self.lines[i].name == line.name]
        if idx:
            self.lines[idx[0]] = line
            return
        end = max(self.own(), default=self.start) + 1
        self.lines.insert(end, line)

    def set(self, name, text):
        if text:
            self.put(Line(name, {}, escape(text)))
        else:
            self.remove(name)

    def set_time(self, name, when):
        if when is None:
            self.remove(name)
        else:
            self.put(time_line(name, when))

    def touch(self):
        """What a sync and other clients look at to see that it changed"""
        self.put(Line("DTSTAMP", {}, stamp()))
        self.put(Line("LAST-MODIFIED", {}, stamp()))
        seq = self.get("SEQUENCE", "0")
        self.put(Line("SEQUENCE", {}, str(int(seq) + 1 if seq.isdigit() else 1)))

    def __str__(self):
        return "\r\n".join(str(l) for l in self.lines) + "\r\n"


def as_text(when):
    """A due date or time as the JSON gives it: YYYY-MM-DD or YYYY-MM-DDTHH:MM"""
    if when is None:
        return None
    return when.strftime("%Y-%m-%dT%H:%M") if isinstance(when, datetime) else when.isoformat()


def is_date(when):
    return isinstance(when, date) and not isinstance(when, datetime)
