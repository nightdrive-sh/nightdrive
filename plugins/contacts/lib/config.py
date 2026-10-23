#!/usr/bin/env python3
"""vdirsyncer's config, written from Contacts' own accounts.conf (README.md › Setting up an account).

    config.py write     write VDIRSYNCER_CONFIG from ACCOUNTS, print the account names (one a line)
    config.py names     only print them

accounts.conf is what the user (or Claude) edits: one section per account, in Mail's account.conf's form. vdirsyncer's
config follows from it, so its pairs, paths and the one-way sync stay the same for everyone and a change to them here
reaches every account at the next sync.
"""

import configparser
import json
import os
import re
import sys
from pathlib import Path

HOME = Path.home()
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "contacts"
ACCOUNTS = CONFIG_DIR / "accounts.conf"
VDIRSYNCER_CONFIG = CONFIG_DIR / "vdirsyncer"
# The vCards, one folder per account and address book in it: the app reads them from here
DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "contacts"
STATUS_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "contacts/vdirsyncer"

ICLOUD_URL = "https://contacts.icloud.com/"
# Google's CardDAV takes an app password (Basic auth) at the address book itself; its discovery wants OAuth
GOOGLE_URL = "https://www.googleapis.com/carddav/v1/principals/{address}/lists/default/"
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")


def accounts():
    """[(name, section)] in the file's order; exits with a message on a section it can't use."""
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(ACCOUNTS)
    found = []
    for section in parser.sections():
        kind, _, name = section.partition(" ")
        if kind != "account":
            continue
        values = parser[section]
        problem = None
        if not NAME_RE.match(name):
            problem = "the name takes only a-z, 0-9, - and _"
        elif values.get("type") not in ("icloud", "google", "carddav"):
            problem = "type is icloud, google or carddav"
        elif not values.get("address") or not values.get("password-cmd"):
            problem = "address and password-cmd are needed"
        elif values["type"] == "carddav" and not values.get("url"):
            problem = "a carddav account needs url"
        if problem:
            sys.exit(f"{ACCOUNTS}: [account {name}]: {problem}")
        found.append((name, values))
    return found


def storage_pair(name, values):
    """The account's pair and its two storages, as vdirsyncer's config text."""
    kind = values["type"]
    url = {"icloud": ICLOUD_URL, "google": GOOGLE_URL.format(address=values["address"])}.get(kind, values.get("url"))
    # Google's URL is the address book itself (one, "default"); the others list theirs, each a folder of its own
    single = kind == "google"
    local = DATA_DIR / name / "default" if single else DATA_DIR / name
    fetch = ["command", "sh", "-c", values["password-cmd"]]
    return f"""
[pair {name}]
a = "{name}_remote"
b = "{name}_local"
collections = {"null" if single else '["from a"]'}
conflict_resolution = "a wins"
# One way for now: the server's contacts come down, and a change made here gives way to the server's at the next sync
partial_sync = "revert"

[storage {name}_remote]
type = "carddav"
url = {json.dumps(url)}
username = {json.dumps(values["address"])}
password.fetch = {json.dumps(fetch)}
read_only = true

[storage {name}_local]
type = "filesystem"
path = {json.dumps(str(local))}
fileext = ".vcf"
"""


def write():
    found = accounts()
    text = (f"# Written by Contacts (plugins/contacts/lib/config.py) from {ACCOUNTS}: edit that file instead.\n"
            f'[general]\nstatus_path = {json.dumps(str(STATUS_DIR))}\n')
    text += "".join(storage_pair(name, values) for name, values in found)
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = VDIRSYNCER_CONFIG.with_suffix(".tmp")
    tmp.write_text(text)
    tmp.replace(VDIRSYNCER_CONFIG)
    # vdirsyncer makes an address book's folder only after asking (discover), and a single one's not at all
    for name, values in found:
        (DATA_DIR / name / ("default" if values["type"] == "google" else "")).mkdir(parents=True, exist_ok=True)
    return found


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "names"
    if command == "write":
        found = write()
    elif command == "names":
        found = accounts()
    else:
        sys.exit(__doc__)
    for name, _ in found:
        print(name)
