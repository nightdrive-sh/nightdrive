#!/usr/bin/env python3
"""Desktop notifications for new mail, run after each `notmuch new` (the post-new hook `nightmail install` adds).

    notify.py            notify of new unread mail in the inbox, then tag it notified
    notify.py wait ID    show one message's notification and act on the button pressed (run detached by the above)

A notification has Reply, Reply with Claude, Archive and Delete buttons, and a click opens the message in Mail. More than MAX_EACH new messages at
once get one notification that counts them. Messages are tagged `notified` so each is announced once; mail older
than RECENT (an inbox synced for the first time) is tagged without a notification.
"""

import json
import os
import shutil
import subprocess
import sys

NEW = "folder:/INBOX$/ and tag:inbox and tag:unread and not tag:notified"
# Mail sent from one of your accounts to another: its Message-ID is the Sent copy's, so notmuch adds the received file
# to that message and gives it no new.tags. Tags belong to the message, not the file, so the inbox tag goes on by the
# file's folder: a file just delivered to an inbox (new/), and once only: notify tags it notified, and the file stays
# in new/ until it is read.
# The other account's Inbox and Sent are path terms (folderQuery in app/shell.qml), so its Sent shows it as before.
SELF_SENT = r"tag:sent and not tag:inbox and not tag:notified and path:/\/INBOX\/new$/"
RECENT = "date:2d.."
MAX_EACH = 3
APP = "Mail"
ICON = "nightmail"
NIGHTMAIL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "nightmail")


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def detached(*args):
    """Runs this script again outside the caller: the mail sync's service would end a waiting child with itself."""
    cmd = [sys.executable, os.path.abspath(__file__), *args]
    if shutil.which("systemd-run") and os.environ.get("XDG_RUNTIME_DIR"):
        # It starts from the user manager's environment: carry over which notmuch database this is.
        env = [f"--setenv={k}={os.environ[k]}" for k in ("NOTMUCH_CONFIG", "NOTMUCH_PROFILE", "XDG_CONFIG_HOME", "XDG_CACHE_HOME")
               if k in os.environ]
        cmd = ["systemd-run", "--user", "--quiet", "--collect", *env, "--"] + cmd
    subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def name(sender):
    s = sender.split("<")[0].strip().strip('"')
    return s or sender.strip("<> ")


def announce():
    if notmuch("count", SELF_SENT).strip() != "0":
        notmuch("tag", "+inbox", "+unread", "--", SELF_SENT)
    new = json.loads(notmuch("search", "--format=json", "--output=summary", "--sort=oldest-first",
                             f"({NEW}) and {RECENT}") or "[]")
    if len(new) > MAX_EACH:
        detached("many", str(len(new)))
    else:
        for thread in new:
            # The thread's newest unread message in the inbox: the one that is new.
            msg = notmuch("search", "--output=messages", "--sort=newest-first", "--limit=1",
                          f"thread:{thread['thread']} and ({NEW})").split()
            if msg:
                detached("wait", msg[0].removeprefix("id:"))
    # Everything new is announced now, older mail stays quiet.
    if notmuch("count", NEW).strip() != "0":
        notmuch("tag", "+notified", "--", NEW)


def wait(msgid):
    m = json.loads(notmuch("show", "--format=json", "--body=false", f'id:"{msgid}"'))
    while isinstance(m, list):
        m = m[0]
    h = m["headers"]
    summary = name(h.get("From", ""))
    body = h.get("Subject", "") or "(no subject)"
    out = subprocess.run(["notify-send", "--app-name=" + APP, "--icon=" + ICON, "--hint=string:desktop-entry:nightmail",
                          "--action=default=Open", "--action=reply=Reply", "--action=claude=Reply with Claude",
                          "--action=archive=Archive", "--action=delete=Delete",
                          summary, body], capture_output=True, text=True).stdout.strip()
    if out == "default":
        subprocess.run([NIGHTMAIL, "show", msgid])
    elif out == "reply":
        subprocess.run([NIGHTMAIL, "reply", msgid])
    elif out == "claude":
        subprocess.run([NIGHTMAIL, "claude", msgid])
    elif out in ("archive", "delete"):
        subprocess.run([NIGHTMAIL, out, msgid])


def many(n):
    out = subprocess.run(["notify-send", "--app-name=" + APP, "--icon=" + ICON, "--hint=string:desktop-entry:nightmail",
                          "--action=default=Open", f"{n} new messages", "In the inbox"],
                         capture_output=True, text=True).stdout.strip()
    if out == "default":
        subprocess.run([NIGHTMAIL])


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "wait":
        wait(sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[1] == "many":
        many(sys.argv[2])
    else:
        announce()


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, OSError, ValueError) as e:
        print(f"notify.py: {e}", file=sys.stderr)
