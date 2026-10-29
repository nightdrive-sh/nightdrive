#!/usr/bin/env python3
"""Calendar's sources and vdirsyncer's config written from them (README.md › Your calendars).

    sources.py write             write VDIRSYNCER_CONFIG, print its pairs: the CalDAV sources (one a line)
    sources.py names [KIND]      print the sources' names (KIND: caldav or ics)
    sources.py list              the sources as JSON: name, kind, read_only

The CalDAV accounts are Contacts' (~/.config/contacts/accounts.conf, read by Contacts' own lib/config.py): one account
and one app password in the keyring for both apps. Calendar's own calendars.conf adds to them:

    [account icloud]          a Contacts account: options for its calendars (off = yes; read-only = yes for the whole
                              account, which the sync then only downloads, or read-only = Family, Work for those
                              calendars, which Calendar won't add to or delete from)
    [account work]            with type, address and password-cmd: an account of Calendar's own, in Contacts' form
    [ics family]              a calendar read from an address (Google's private ICS address), never written:
    name = Family               the name the window shows, and its colour (color = #4F8FE6)
    url-cmd = secret-tool lookup service nightdrive-calendar ics family

An ICS address is as good as a password (anyone with it reads the calendar), so it comes from a command, as the
passwords do, and never goes in a file. The ICS sources are fetched by feeds.py, not vdirsyncer.
"""

import configparser
import json
import os
import re
import sys
from pathlib import Path

HOME = Path.home()
REPO = Path(__file__).resolve().parents[3]
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "calendar"
CALENDARS = CONFIG_DIR / "calendars.conf"
VDIRSYNCER_CONFIG = CONFIG_DIR / "vdirsyncer"
# The events, a folder per source and calendar in it (vdir: one .ics per event): khal and the window read them here
DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "calendar"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "calendar"
STATUS_DIR = STATE_DIR / "vdirsyncer"
FEED = "default"    # an ICS source's one calendar folder

ICLOUD_URL = "https://caldav.icloud.com/"
YES = ("yes", "true", "on", "1")
# vdirsyncer's pair and storage names take only letters, digits and _ (Contacts' account names allow - too)
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_]*$")

sys.path.insert(0, str(REPO / "plugins/contacts/lib"))
import config as contacts  # noqa: E402  (Contacts' accounts.conf; its files are in every checkout)


def own():
    """calendars.conf's sections as {section: values}; a missing file is none"""
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(CALENDARS)
    return {s: parser[s] for s in parser.sections()}


def caldav_url(values, extra):
    """The account's CalDAV address, or None: Google's CalDAV wants OAuth, so a Google calendar comes as ICS"""
    kind = values.get("type")
    if kind == "icloud":
        return ICLOUD_URL
    if kind == "carddav":
        return extra.get("caldav-url") or values.get("caldav-url")
    return None


def read_only(value):
    """read-only's value: (the whole account, [calendar names]); yes is the account, a list of names those calendars"""
    value = (value or "").strip()
    if value.lower() in YES:
        return True, []
    if value.lower() in ("", "no", "false", "off", "0"):
        return False, []
    return False, [n.strip().lower() for n in value.split(",") if n.strip()]


def caldav(name, values, extra):
    """A CalDAV source, or None when it has no CalDAV address or is off"""
    url = caldav_url(values, extra)
    if not url or extra.get("off", "").lower() in YES:
        return None
    whole, some = read_only(extra.get("read-only"))
    return {"name": name, "kind": "caldav", "url": url, "user": values["address"], "password_cmd": values["password-cmd"],
            "read_only": whole, "read_only_calendars": some}


def sources():
    """[{name, kind: caldav|ics, read_only, …}] in order: Contacts' accounts, then calendars.conf's own"""
    sections = own()
    found = []
    try:
        theirs = contacts.accounts() if contacts.ACCOUNTS.exists() else []
    except SystemExit as e:  # a broken accounts.conf is Contacts' to report; Calendar goes on with its own
        print(f"calendar: Contacts' accounts left out: {e}", file=sys.stderr)
        theirs = []
    names = {name for name, _ in theirs}
    for name, values in theirs:
        s = caldav(name, values, sections.get(f"account {name}", {}))
        if s:
            found.append(s)
    for section, values in sections.items():
        kind, _, name = section.partition(" ")
        problem = None
        if not NAME_RE.match(name):
            problem = "the name takes only a-z, 0-9 and _"
        elif kind == "ics":
            if not values.get("url-cmd"):
                problem = "an ics calendar needs url-cmd"
            else:
                found.append({"name": name, "kind": "ics", "url_cmd": values["url-cmd"], "read_only": True,
                              "title": values.get("name", name), "color": values.get("color", "")})
        elif kind == "account" and name not in names:
            if not (values.get("address") and values.get("password-cmd") and caldav_url(values, values)):
                problem = "an account of its own needs type (icloud, or carddav with caldav-url), address and password-cmd"
            elif caldav(name, values, values):
                found.append(caldav(name, values, values))
        elif kind != "account":
            problem = "a section is [account NAME] or [ics NAME]"
        if problem:
            sys.exit(f"{CALENDARS}: [{section}]: {problem}")
    return found


def command(cmd):
    return json.dumps(["command", "sh", "-c", cmd])


def pair(s):
    """A CalDAV source's pair and storages, as vdirsyncer's config text"""
    name = s["name"]
    remote = (f'type = "caldav"\nurl = {json.dumps(s["url"])}\nusername = {json.dumps(s["user"])}\n'
              f'password.fetch = {command(s["password_cmd"])}\n'
              # Only events: iCloud lists its old Reminders lists as calendars too (Tasks is apart)
              'item_types = ["VEVENT"]')
    if s["read_only"]:
        remote += "\nread_only = true"
    return f"""
[pair {name}]
a = "{name}_remote"
b = "{name}_local"
collections = ["from a"]
# Calendar only adds and deletes (calendar add, delete), never edits: an event changed on both sides is the server's
conflict_resolution = "a wins"
metadata = ["displayname", "color"]

[storage {name}_remote]
{remote}

[storage {name}_local]
type = "filesystem"
path = {json.dumps(str(DATA_DIR / name))}
fileext = ".ics"
"""


def write():
    found = sources()
    text = (f"# Written by Calendar (plugins/calendar/lib/sources.py) from Contacts' accounts and {CALENDARS}: edit "
            f"those instead.\n[general]\nstatus_path = {json.dumps(str(STATUS_DIR))}\n")
    caldav = [s for s in found if s["kind"] == "caldav"]
    text += "".join(pair(s) for s in caldav)
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = VDIRSYNCER_CONFIG.with_suffix(".tmp")
    tmp.write_text(text)
    tmp.replace(VDIRSYNCER_CONFIG)
    # vdirsyncer makes a calendar's folder only after asking (discover); an ICS source's one is ours
    for s in found:
        (DATA_DIR / s["name"] / (FEED if s["kind"] == "ics" else "")).mkdir(parents=True, exist_ok=True)
    return caldav


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "names"
    if what == "write":
        found = write()
    elif what in ("names", "list"):
        kind = sys.argv[2] if len(sys.argv) > 2 else None
        found = [s for s in sources() if kind in (None, s["kind"])]
    else:
        sys.exit(__doc__)
    if what == "list":
        print(json.dumps([{"name": s["name"], "kind": s["kind"], "read_only": s["read_only"]} for s in found]))
    else:
        for s in found:
            print(s["name"])
