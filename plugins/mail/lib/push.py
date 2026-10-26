#!/usr/bin/env python3
"""New mail as it arrives (`nightmail push`, run by nightdrive-mail-push.service).

    push.py    watch each account's INBOX in ~/.config/isyncrc and sync as soon as mail comes

mbsync only polls (nightdrive-mail-sync.timer, every 5 minutes), so an activation link could wait that long. Here one
IMAP IDLE connection per account stays open: when the server says the INBOX has a new message, `nightmail sync` runs,
which fetches it and brings its notification. The timer stays for the other folders and for whatever arrives while a
connection is down.

The password comes from the account's PassCmd, as mbsync gets it, and only once the login keyring is open: before that,
secret-tool would pop up gnome-keyring's password prompt. It stays in this process's memory.
"""

import imaplib
import os
import shlex
import ssl
import subprocess
import sys
import threading
import time

import keyring

ISYNCRC = os.path.expanduser("~/.config/isyncrc")
NIGHTMAIL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "nightmail")
# IDLE is renewed this often: a connection that died in a suspend or a network change shows on the renewal at the latest
IDLE_SECONDS = 4 * 60
# A reply slower than this means the connection is gone
TIMEOUT = 60
# A burst of new messages makes one sync: wait this long for the rest before starting it
SETTLE = 2
# Waits after a failure, growing up to the last
RETRY = (15, 30, 60, 120, 300)
KEYRING_WAIT = 60


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def sections(path=ISYNCRC):
    """An isyncrc's sections as (kind, name, settings), kind and keys lowercased: ("imapaccount", "work", {"host": …})"""
    found = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition(" ")
            key, value = key.lower(), value.strip()
            if key in ("imapaccount", "imapstore", "maildirstore", "channel", "group"):
                found.append((key, value, {}))
            elif found:
                found[-1][2][key] = value
    return found


def accounts(path=ISYNCRC):
    """The IMAPAccount sections, each with "name" and "inbox": the mbsync channel that fetches its INBOX alone (a
    channel of that folder, or channel:INBOX of one with Patterns), or None to fetch everything"""
    parts = sections(path)
    stores = {name: settings.get("account") for kind, name, settings in parts if kind == "imapstore"}
    inboxes = {}
    for kind, name, settings in parts:
        if kind != "channel":
            continue
        store, _, box = unquote(settings.get("far", "")).strip(":").partition(":")
        account = stores.get(store)
        if box == "INBOX":
            inboxes[account] = name
        elif not box and "patterns" in settings:
            inboxes.setdefault(account, f"{name}:INBOX")
    return [dict(settings, name=name, inbox=inboxes.get(name)) for kind, name, settings in parts if kind == "imapaccount"]


def unquote(value):
    return shlex.split(value)[0] if value.startswith('"') else value


class Sync:
    """Fetches the inboxes asked for, once per burst of requests, and again for requests that came during a fetch.

    Only the inbox (`nightmail sync CHANNEL`) takes a second or two, where the full round with every folder can take
    half a minute; the timer brings the rest. A fetch that comes during the timer's round waits for it (nightmail's
    fetch lock)."""

    def __init__(self):
        self.lock = threading.Lock()
        self.channels = set()
        self.wanted = threading.Event()
        threading.Thread(target=self.run, daemon=True).start()

    def request(self, channel):
        with self.lock:
            self.channels.add(channel)
        self.wanted.set()

    def run(self):
        while True:
            self.wanted.wait()
            time.sleep(SETTLE)
            self.wanted.clear()
            with self.lock:
                channels, self.channels = self.channels, set()
            # An account without an inbox channel of its own: everything
            command = [NIGHTMAIL, "sync"] if None in channels else [NIGHTMAIL, "sync", *sorted(channels)]
            result = subprocess.run(command, stdout=subprocess.DEVNULL)
            if result.returncode:
                log(f"{' '.join(command[1:])} failed ({result.returncode})")


class Watch:
    def __init__(self, account, sync):
        self.account, self.sync = account, sync
        self.name = account["name"]
        self.password = None

    def get_password(self):
        if "pass" in self.account:
            return unquote(self.account["pass"])
        while keyring.is_locked():
            time.sleep(KEYRING_WAIT)
        result = subprocess.run(["sh", "-c", unquote(self.account["passcmd"])], capture_output=True, text=True)
        if result.returncode or not result.stdout.strip():
            raise RuntimeError("its PassCmd gave no password")
        return result.stdout.rstrip("\n")

    def tls_context(self):
        """Verifies the server's certificate, as mbsync does: IMAP4_SSL's default doesn't, which would give the password
        to anyone in the middle. The account's CertificateFile (a self-signed server's) is trusted on top of the system's."""
        context = ssl.create_default_context()
        if "certificatefile" in self.account:
            context.load_verify_locations(os.path.expanduser(unquote(self.account["certificatefile"])))
        return context

    def connect(self):
        host = self.account["host"]
        tls = (self.account.get("tlstype") or self.account.get("ssltype") or "STARTTLS").upper()
        if tls == "IMAPS":
            imap = imaplib.IMAP4_SSL(host, int(self.account.get("port", 993)), ssl_context=self.tls_context(),
                                     timeout=TIMEOUT)
        else:
            imap = imaplib.IMAP4(host, int(self.account.get("port", 143)), timeout=TIMEOUT)
            if tls != "NONE":
                imap.starttls(self.tls_context())
        try:
            if self.password is None:
                self.password = self.get_password()
            imap.login(self.account["user"], self.password)
        except imaplib.IMAP4.error:
            # A changed password: ask the keyring again next time
            self.password = None
            imap.shutdown()
            raise
        imap.select("INBOX", readonly=True)
        return imap

    def run(self):
        failures, connected_before = 0, False
        while True:
            try:
                imap = self.connect()
                if "IDLE" not in imap.capabilities:
                    log(f"{self.name}: the server has no IMAP IDLE, so its mail comes with the 5-minute sync")
                    imap.logout()
                    return
                log(f"{self.name}: watching INBOX")
                # Mail may have come while the connection was down
                if connected_before:
                    self.sync.request(self.account["inbox"])
                connected_before, failures = True, 0
                while True:
                    with imap.idle(duration=IDLE_SECONDS) as idler:
                        for typ, _ in idler:
                            if typ == "EXISTS":
                                log(f"{self.name}: new mail")
                                self.sync.request(self.account["inbox"])
            except (OSError, imaplib.IMAP4.error, RuntimeError) as error:
                wait = RETRY[min(failures, len(RETRY) - 1)]
                failures += 1
                log(f"{self.name}: {error or type(error).__name__}; again in {wait} s")
                time.sleep(wait)


def main():
    if not os.path.exists(ISYNCRC):
        log(f"No {ISYNCRC}: no account to watch")
        return 0
    sync = Sync()
    watches = []
    for account in accounts():
        if not {"host", "user"} <= account.keys() or not {"pass", "passcmd"} & account.keys():
            log(f"{account['name']}: no Host, User and Pass/PassCmd, not watched")
            continue
        if account.get("authmechs", "").upper() not in ("", "*", "LOGIN", "PLAIN"):
            log(f"{account['name']}: AuthMechs {account['authmechs']} isn't supported here, not watched")
            continue
        watch = Watch(account, sync)
        watches.append(threading.Thread(target=watch.run, name=watch.name, daemon=True))
    for thread in watches:
        thread.start()
    for thread in watches:
        thread.join()
    return 0


if __name__ == "__main__":
    sys.exit(main())
