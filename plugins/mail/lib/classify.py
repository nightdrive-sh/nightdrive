#!/usr/bin/env python3
"""New mail sorted by your rules (rules.py) before its notification: run by `nightmail notify`, notmuch's post-new
hook, ahead of notify.py.

    classify.py    each new message in an inbox whose sender has a rule goes to that folder, unannounced

A message is new while it has no `notified` tag (notify.py gives it one). One that a rule sorts moves from the
account's INBOX to the folder (move.py, so the next sync moves it on the server and a phone sees it there), loses
the inbox tag and gets `notified`: no notification, but it stays unread, and the folder's count shows it. Then the
inbox and the folder are synced at once, not at the timer's round, so the phone's inbox doesn't keep it for minutes.
Prints {"sorted": N, "folders": {"account/folder": N}}.
"""

import json
import os
import shutil
import subprocess
import sys
from collections import defaultdict

import browse
import compose
import ids
import isync
import rules
import sorting

NEW = "(and (tag inbox) (not (tag notified)) (folder (rx \"INBOX$\")))"
HERE = os.path.dirname(os.path.abspath(__file__))
NIGHTMAIL = os.path.join(os.path.dirname(HERE), "bin", "nightmail")


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def plan(root, current, accounts):
    """{(maildir, folder): [message ids]} for the new inbox messages a rule sorts."""
    if not current:
        return {}
    by_dir = {a["maildir"]: k for k, a in accounts.items() if a.get("maildir")}
    shown = json.loads(notmuch("show", "--format=json", "--body=false", "--entire-thread=false", "--exclude=false",
                               "--query=sexp", NEW) or "[]")
    found = defaultdict(list)
    for m in browse.walk(shown, []):
        files = m.get("filename") or []
        files = files if isinstance(files, list) else [files]
        inbox = next((f for f in files if os.path.basename(os.path.dirname(os.path.dirname(f))) == "INBOX"), None)
        if not inbox:
            continue
        top = os.path.relpath(inbox, root).split(os.sep)[0]
        account = by_dir.get(top)
        folder = account and rules.match(current, account, rules.address(m["headers"].get("From", "")))
        # A rule into a folder that is gone (deleted elsewhere) sorts nothing
        if folder and os.path.isdir(os.path.join(root, top, folder, "cur")):
            found[(top, folder)].append(m["id"])
    return found


def sync_now(boxes):
    """The inboxes and folders mail moved between, synced in the background: this runs inside the sync's own lock,
    which the new sync waits for (bin/nightmail fetch). Detached like notify.py's notifications (systemd-run, waited
    for, so the oneshot service doesn't take it down with itself)."""
    channels = sorted({c for m, box in boxes for c in [isync.channel_for(m, box)] if c})
    if not channels or os.environ.get("NIGHTMAIL_NO_SYNC"):     # the tests' throwaway mail has no server
        return
    cmd = [NIGHTMAIL, "sync", *channels]
    quiet = dict(stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if shutil.which("systemd-run") and os.environ.get("XDG_RUNTIME_DIR"):
        env = [f"--setenv={k}={os.environ[k]}" for k in ("NOTMUCH_CONFIG", "NOTMUCH_PROFILE", "XDG_CONFIG_HOME")
               if k in os.environ]
        try:
            if subprocess.run(["systemd-run", "--user", "--quiet", "--collect", *env, "--", *cmd], timeout=20,
                              **quiet).returncode == 0:
                return
        except subprocess.TimeoutExpired:
            return
        except OSError:
            pass
    subprocess.Popen(cmd, start_new_session=True, **quiet)


def main():
    current = rules.load()
    if not current:
        print(json.dumps({"sorted": 0, "folders": {}}))
        return
    root = isync.mail_root()
    try:
        accounts = compose.accounts()
    except SystemExit:
        return
    found = plan(root, current, accounts)
    done = {}
    for (top, folder), mids in found.items():
        exact = ids.messages(mids)
        out = subprocess.run([sys.executable, os.path.join(HERE, "move.py"), "--sexp", "--unread", folder, exact, f"{top}/INBOX"],
                             capture_output=True, text=True, check=True).stdout
        if json.loads(out).get("error"):
            continue
        sorting.tag(["-inbox", "+notified"], exact)
        done[f"{top}/{folder}"] = len(mids)
    if done:
        sync_now({(k.split("/")[0], box) for k in done for box in ("INBOX", k.split("/", 1)[1])})
    print(json.dumps({"sorted": sum(done.values()), "folders": done}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, OSError, ValueError) as e:
        # The notifications come after this all the same
        print(f"classify.py: {e}", file=sys.stderr)
