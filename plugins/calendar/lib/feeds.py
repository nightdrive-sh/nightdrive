#!/usr/bin/env python3
"""The calendars read from an ICS address (calendars.conf's [ics NAME]: Google's private address), fetched into their
folder as one .ics per event, as vdirsyncer leaves a CalDAV calendar, so khal and the rest read both alike.

    feeds.py [NAME…]     fetch every ICS source (or these); exit 1 if one failed

Not vdirsyncer's http storage: it mangles an address with %40 in it (https:///…), which Google's all have. The
address comes from the source's url-cmd and stays in memory: in no argv, file or log line (an error names the source,
not the address). An event the address no longer has is removed here too; nothing here is ever sent anywhere.
"""

import hashlib
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import icalendar

import sources

TIMEOUT = 60
SIZE_MAX = 50_000_000       # bytes: a calendar is far smaller; more is something else
AGENT = "Nightdrive Calendar"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as reply:
        data = reply.read(SIZE_MAX + 1)
    if len(data) > SIZE_MAX:
        raise ValueError("more than 50 MB")
    return data


def split(data):
    """{file name: .ics bytes}: each UID's events (a recurring one with its changed times) with the zones they use"""
    cal = icalendar.Calendar.from_ical(data)
    zones = {str(z.get("tzid")): z for z in cal.walk("VTIMEZONE")}
    by_uid = {}
    for e in cal.walk("VEVENT"):
        uid = str(e.get("uid") or "")
        if uid:
            by_uid.setdefault(uid, []).append(e)
    out = {}
    for uid, events in by_uid.items():
        one = icalendar.Calendar()
        one.add("prodid", "-//Nightdrive//Calendar feed//EN")
        one.add("version", "2.0")
        used = {p.params.get("TZID") for e in events for k in ("dtstart", "dtend") if (p := e.get(k)) is not None}
        for tzid in sorted(t for t in used if t in zones):
            one.add_component(zones[tzid])
        for e in events:
            one.add_component(e)
        # The UID can hold anything (/, @): the file is named by its hash, as vdirsyncer does for an awkward one
        out[hashlib.sha1(uid.encode()).hexdigest() + ".ics"] = one.to_ical()
    return out


def store(folder, files):
    """The folder holds exactly these events now; a file is written only when it changed (khal reindexes by mtime)"""
    folder.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        path = folder / name
        try:
            if path.read_bytes() == data:
                continue
        except OSError:
            pass
        tmp = path.with_suffix(".tmp")
        tmp.write_bytes(data)
        tmp.replace(path)
    for path in folder.glob("*.ics"):
        if path.name not in files:
            path.unlink()


def main(names):
    wanted = [s for s in sources.sources() if s["kind"] == "ics" and (not names or s["name"] in names)]
    failed = False
    for s in wanted:
        got = subprocess.run(["sh", "-c", s["url_cmd"]], capture_output=True, text=True)
        url = got.stdout.strip()
        if got.returncode != 0 or not url.startswith(("https://", "http://", "webcal://")):
            print(f"calendar: {s['name']}: url-cmd gave no address", file=sys.stderr)
            failed = True
            continue
        if url.startswith("webcal://"):
            url = "https://" + url[len("webcal://"):]
        try:
            files = split(fetch(url))
        except (OSError, ValueError, urllib.error.URLError) as e:
            # The reason, never the address: it is as good as a password
            why = e.reason if isinstance(e, urllib.error.URLError) else type(e).__name__
            print(f"calendar: {s['name']}: couldn't fetch it ({why})", file=sys.stderr)
            failed = True
            continue
        store(sources.DATA_DIR / s["name"] / sources.FEED, files)
        print(f"{s['name']}: {len(files)} events")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
