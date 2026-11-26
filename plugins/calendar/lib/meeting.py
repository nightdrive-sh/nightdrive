#!/usr/bin/env python3
"""An event's meeting link (#3444): the address that joins its video call, found in one place for the window's Join
(EventPanel), the reminders' notifications (remind.py, notice.py), `calendar events --json` and Claude's calendar_events.

    find(url, location, notes) -> {"url", "service"} or None
    meeting.py < TEXT          the link in a text, as JSON (null for none): for trying an invitation

The event's URL field first, then its place, then its notes: an invitation puts the link in any of them, and the field
and the place are the organiser's choice, while the notes also hold the service's other links. Only an address that
joins a call counts: Teams' meeting options, "Download Teams" and the help pages don't.

SERVICES lists what is known, each a host (itself or a subdomain of it) and the paths that join. An Outlook that wraps
links in Safe Links (…safelinks.protection.outlook.com/?url=…) has the real address in its url parameter.
"""

import json
import re
import sys
from urllib.parse import parse_qs, urlsplit

# (name, hosts, path pattern): a host matches itself and its subdomains (example.zoom.us)
SERVICES = [
    ("Teams", ("teams.microsoft.com", "teams.live.com", "teams.microsoft.us"), r"^/(l/meetup-join/|meet/)"),
    ("Google Meet", ("meet.google.com",), r"^/(lookup/)?[a-z]{3,}-[a-z]{3,}-[a-z]{3,}"),
    ("Zoom", ("zoom.us", "zoomgov.com"), r"^/(j/|w/|my/|wc/join/)"),
    ("Webex", ("webex.com",), r"^/(meet/|join/|wbxmjs/joinservice/|[^/]+/j\.php|[^/]+/meet/)"),
    ("Jitsi", ("meet.jit.si",), r"^/[^/]+"),
]
SAFE_LINKS = "safelinks.protection.outlook.com"
# An address in a text: up to a space, a quote or an angle bracket (Outlook's "Join<https://…>")
URL = re.compile(r"https?://[^\s<>\"']+", re.I)


def trim(url):
    """Without what follows it in the sentence: a full stop, comma, or a bracket it didn't open"""
    while url:
        if url[-1] in ".,;:!?*'":
            url = url[:-1]
        elif url[-1] in ")]" and url.count(url[-1]) > url.count("(" if url[-1] == ")" else "["):
            url = url[:-1]
        else:
            break
    return url


def unwrap(url):
    """Outlook's Safe Links address: the real one is its url parameter"""
    parts = urlsplit(url)
    if parts.hostname and (parts.hostname == SAFE_LINKS or parts.hostname.endswith("." + SAFE_LINKS)):
        inner = parse_qs(parts.query).get("url", [""])[0]
        if URL.match(inner):
            return inner
    return url


def service(url):
    """The service whose call the address joins, or None"""
    try:
        parts = urlsplit(url)
    except ValueError:
        return None
    host = (parts.hostname or "").lower()
    for name, hosts, path in SERVICES:
        if any(host == h or host.endswith("." + h) for h in hosts) and re.match(path, parts.path, re.I):
            return name
    return None


def in_text(text):
    """The first meeting link in a text, as {url, service}, or None"""
    for m in URL.finditer(text or ""):
        url = unwrap(trim(m.group(0)))
        name = service(url)
        if name:
            return {"url": url, "service": name}
    return None


def find(url="", location="", notes=""):
    for text in (url, location, notes):
        found = in_text(text)
        if found:
            return found
    return None


if __name__ == "__main__":
    print(json.dumps(in_text(sys.stdin.read())))
