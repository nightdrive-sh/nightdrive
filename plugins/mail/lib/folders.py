#!/usr/bin/env python3
"""Your own folders: an account's folders besides Mail's six (INBOX, Sent, Drafts, Archive, Spam, Trash). Each sorts
by sender: mail dragged into it brings that sender's later mail there too (sorting.py, rules.py, classify.py). They
are real IMAP folders, so a phone sees them.

    folders.py list                    {"folders": {ACCOUNT: ["Offers", …]}}, by name
    folders.py create ACCOUNT NAME     {"folder": NAME, "channel": the isyncrc channel added, or null}
    folders.py delete ACCOUNT NAME     its mail back to the inbox, its rules gone, then the folder here, on the server
                                       and in isyncrc: {"moved": N, "rules": [removed], "server": true|false}

A folder is a maildir at ~/Mail/<account>/<NAME>, at the top: nested ones (Work/2025) aren't Mail's to show, as
move.py moves only between an account's top folders. Failures print {"error": "..."} with exit status 1.
"""

import fcntl
import imaplib
import json
import os
import shutil
import subprocess
import sys
import unicodedata

import compose
import ids
import isync
import rules
import sorting

MAILS = {"inbox", "sent", "drafts", "archive", "spam", "trash"}
HERE = os.path.dirname(os.path.abspath(__file__))
NIGHTMAIL = os.path.join(os.path.dirname(HERE), "bin", "nightmail")
# The sync's lock (bin/nightmail fetch): a folder isn't taken away while mbsync is at it
FETCH_LOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "nightdrive", "mail-fetch.lock")
NAME_MAX = 60


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def maildirs():
    """{account id: its folder under ~/Mail}"""
    return {k: a["maildir"] for k, a in compose.accounts().items() if a.get("maildir")}


def own(path):
    """The own folders in an account's folder, by name."""
    try:
        names = os.listdir(path)
    except OSError:
        return []
    return sorted((n for n in names if not n.startswith(".") and n.lower() not in MAILS and
                   os.path.isdir(os.path.join(path, n, "cur"))), key=str.lower)


def listing(root):
    return {acc: own(os.path.join(root, m)) for acc, m in maildirs().items()}


def checked(name, existing):
    """A new folder's name, trimmed; ValueError for one that can't be: empty, Mail's own, taken, or with a character
    IMAP or a path gives a meaning to."""
    name = unicodedata.normalize("NFC", name.strip())
    if not name:
        raise ValueError("A folder needs a name")
    if len(name) > NAME_MAX:
        raise ValueError(f"At most {NAME_MAX} characters")
    if name.lower() in MAILS:
        raise ValueError(f"{name} is one of Mail's own folders")
    if name.startswith((".", "-")) or any(ch in name for ch in '/\\*%"&') or any(unicodedata.category(ch)[0] == "C" for ch in name):
        raise ValueError("A name can't start with . or - or hold / \\ * % \" &")
    if name.lower() in (n.lower() for n in existing):
        raise ValueError(f"There is a folder {name} already")
    return name


def create(account, name, root):
    m = maildirs().get(account)
    if not m:
        raise ValueError(f"No account {account}")
    base = os.path.join(root, m)
    name = checked(name, own(base))
    for sub in ("cur", "new", "tmp"):
        os.makedirs(os.path.join(base, name, sub), exist_ok=True)
    return {"folder": name, "channel": isync.ensure(m, name, root=root)}


def server_delete(m, name, root):
    """Deletes the folder on the server (IMAP DELETE), its account's login as mbsync's. True if it went, False if
    there was none; an error raises."""
    box, account = isync.far_box(m, name, root=root)
    if not box or not account:
        return False
    from push import Watch          # its connection: the certificate checked, the password from PassCmd
    imap = Watch(account, None).connect()
    try:
        quoted = '"' + box.replace("\\", "\\\\").replace('"', '\\"') + '"'
        typ, found = imap.list('""', quoted)
        if typ != "OK" or not [f for f in found if f]:
            return False
        typ, said = imap.delete(quoted)
        if typ != "OK":
            raise RuntimeError(f"The server didn't delete {box}: {said[0].decode(errors='replace') if said else typ}")
        return True
    finally:
        try:
            imap.logout()
        except (OSError, imaplib.IMAP4.error):
            pass


def delete(account, name, root):
    m = maildirs().get(account)
    if not m or name not in own(os.path.join(root, m)):
        raise ValueError(f"No folder {name} in {account}")
    os.makedirs(os.path.dirname(FETCH_LOCK), exist_ok=True)
    with open(FETCH_LOCK, "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Its mail first, back to the inbox (move.py: uploaded there at the next sync), announced as old
        where = f"{m}/{name}"
        query = f'(path "{where}/**")'
        found = notmuch("search", "--output=messages", "--exclude=false", "--query=sexp", query).split()
        moved = 0
        if found:
            out = subprocess.run([sys.executable, os.path.join(HERE, "move.py"), "--sexp", "INBOX", query, where],
                                 capture_output=True, text=True, check=True).stdout
            result = json.loads(out)
            if result.get("error"):
                raise RuntimeError(result["error"])
            moved = result.get("moved", 0)
            sorting.tag(["+inbox", "+notified"], ids.messages([i.removeprefix("id:") for i in found]))
        gone = rules.remove_where(lambda r: r["account"] == account and r["folder"] == name)
        try:
            on_server = server_delete(m, name, root)
        except (OSError, imaplib.IMAP4.error, RuntimeError) as e:
            raise RuntimeError(f"Its mail is back in the inbox, but the server's {name} stays: {e or type(e).__name__}."
                               " Delete it again once the server can be reached.")
        shutil.rmtree(os.path.join(root, m, name))
        isync.remove(m, name)
        notmuch("new", "--quiet", "--no-hooks")
    # The inbox's new files go up now, not at the timer's round (not from the tests' throwaway mail)
    if not os.environ.get("NIGHTMAIL_NO_SYNC"):
            subprocess.Popen([NIGHTMAIL, "sync"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    return {"moved": moved, "rules": gone, "server": on_server}


def main():
    args = sys.argv[1:]
    root = isync.mail_root()
    if args[:1] == ["list"]:
        print(json.dumps({"folders": listing(root)}, ensure_ascii=False))
    elif args[:1] == ["create"] and len(args) == 3:
        print(json.dumps(create(args[1], args[2], root), ensure_ascii=False))
    elif args[:1] == ["delete"] and len(args) == 3:
        print(json.dumps(delete(args[1], args[2], root), ensure_ascii=False))
    else:
        sys.exit(__doc__.split("\n\n")[1])


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        print(json.dumps({"error": f"{os.path.basename(e.cmd[0])} failed: {(e.stderr or '').strip() or e.returncode}"}))
        sys.exit(1)
    except (ValueError, RuntimeError, OSError) as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
    except SystemExit as e:
        if not str(e).startswith("{"):      # compose.accounts()'s error is JSON already; usage isn't
            raise
        print(e)
        sys.exit(1)
