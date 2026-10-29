#!/usr/bin/env python3
"""Which of a CalDAV account's collections hold events: written once per collection after `vdirsyncer discover`.

    components.py NAME…     for each CalDAV source, each of its collections without COMPONENTS yet

vdirsyncer's discover lists every collection of the account, and iCloud's include the user's Reminders lists (VTODO
only, "Shopping ⚠️"): synced with item_types = ["VEVENT"] they stay empty, but would still show as calendars. The
server says what each takes (supported-calendar-component-set, RFC 4791), so it's asked once and kept in the folder as
COMPONENTS ("VEVENT VTODO"), which khal leaves alone (not .ics). calendars.py skips a folder that takes no VEVENT.

The password comes from the account's password-cmd, as vdirsyncer's does, and stays in memory: it is in no argv,
file or log line.
"""

import base64
import json
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET

import sources

COMPONENTS = "nightdrive-components"
TIMEOUT = 20
BODY = b"""<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><c:supported-calendar-component-set/></d:prop>
</d:propfind>"""
NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav"}


def collections(name):
    """[(collection, url, folder)] from vdirsyncer's status of the pair (written by discover)"""
    try:
        data = json.loads((sources.STATUS_DIR / f"{name}.collections").read_text())
    except (OSError, ValueError):
        return []
    out = []
    for collection, (remote, local) in data.get("collections", []):
        if remote and local and "url" in remote and "path" in local:
            out.append((collection, remote["url"], local["path"]))
    return out


def ask(url, auth):
    """The component names the collection takes, e.g. ["VEVENT"]; None when the server doesn't say"""
    req = urllib.request.Request(url, data=BODY, method="PROPFIND",
                                 headers={"Depth": "0", "Content-Type": "application/xml; charset=utf-8",
                                          "Authorization": auth})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as reply:
        tree = ET.fromstring(reply.read())
    comps = tree.findall(".//c:supported-calendar-component-set/c:comp", NS)
    return [c.get("name", "").upper() for c in comps] or None


def main(names):
    wanted = [s for s in sources.sources() if s["kind"] == "caldav" and (not names or s["name"] in names)]
    for s in wanted:
        todo = [(c, url, folder) for c, url, folder in collections(s["name"])
                if not (sources.Path(folder) / COMPONENTS).exists()]
        if not todo:
            continue
        got = subprocess.run(["sh", "-c", s["password_cmd"]], capture_output=True, text=True)
        if got.returncode != 0:
            print(f"calendar: {s['name']}: password-cmd failed", file=sys.stderr)
            continue
        token = base64.b64encode(f"{s['user']}:{got.stdout.rstrip(chr(10))}".encode()).decode()
        auth = f"Basic {token}"
        for collection, url, folder in todo:
            try:
                comps = ask(url, auth)
            except (OSError, ET.ParseError) as e:
                print(f"calendar: {s['name']}/{collection}: {e}", file=sys.stderr)
                continue
            # A server that doesn't say takes everything (RFC 4791 5.2.3)
            (sources.Path(folder) / COMPONENTS).write_text(" ".join(comps or ["VEVENT", "VTODO", "VJOURNAL"]) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
