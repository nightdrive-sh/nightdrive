#!/usr/bin/env python3
"""A message's calendar invitation, by Nightdrive Calendar: `nightmail invitation` (Mail's card on the message, and
Claude's mail_invitation).

    invitation.py MSGID                    what it is: Calendar's `calendar invite --json` of it, as JSON
    invitation.py MSGID --add CALENDAR     its event into that calendar, or the copy already in one brought up to date
    invitation.py MSGID --remove           a cancelled one's event out of the calendar it is in

The invitation is the message's text/calendar part (an invitation's own), else an application/ics part or an .ics
attachment: the first, at most MAX_BYTES. It goes to Calendar on stdin, never as a file here, and Calendar reads it as
data only (its lib/invite.py). Without Calendar, or a message with no invitation, the answer is {"error": …} with
"calendar": false or "invitation": false, so the card knows to stay away.
"""

import email
import email.policy
import json
import subprocess
import sys
from pathlib import Path

import ids

CALENDAR = Path(__file__).resolve().parents[2] / "calendar/bin/calendar"
MAX_BYTES = 1_000_000
TIMEOUT = 120   # --add syncs the calendar with its server
TYPES = ("text/calendar", "application/ics")


def part(msgid):
    """The invitation's bytes, or None"""
    raw = subprocess.run(["notmuch", "show", "--format=raw", "--query=sexp", ids.exact(msgid)],
                         capture_output=True, check=True).stdout
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    found = [p for p in msg.walk() if not p.is_multipart() and
             (p.get_content_type() in TYPES or (p.get_filename() or "").lower().endswith(".ics"))]
    # An invitation's own part says its METHOD in its type; a plain .ics attachment is the next best
    found.sort(key=lambda p: (p.get_content_type() != "text/calendar", not p.get_param("method")))
    for p in found:
        data = p.get_payload(decode=True) or b""
        if 0 < len(data) <= MAX_BYTES:
            return data
    return None


def main(argv):
    if not argv or argv[0].startswith("--"):
        sys.exit(__doc__)
    msgid, rest = argv[0], argv[1:]
    if rest not in ([], ["--remove"]) and not (len(rest) == 2 and rest[0] == "--add"):
        sys.exit(__doc__)
    if not CALENDAR.exists():
        return {"error": "Nightdrive Calendar isn't installed (Settings › Plugins).", "calendar": False}
    if msgid.startswith("thread:"):
        return {"error": "Give a message's id (mail_thread lists them), not a thread's."}
    try:
        data = part(msgid)
    except (subprocess.CalledProcessError, OSError, ValueError, LookupError) as e:
        return {"error": str(e).strip() or "notmuch couldn't read the message"}
    if data is None:
        return {"error": "This message has no calendar invitation.", "invitation": False}
    try:
        done = subprocess.run([str(CALENDAR), "invite", "-", "--json", *rest], input=data, capture_output=True,
                              timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return {"error": "Calendar took too long; try again in a while."}
    if done.returncode != 0:
        return {"error": done.stderr.decode(errors="replace").strip()[-500:] or "Calendar couldn't read it."}
    try:
        return json.loads(done.stdout)
    except ValueError:
        return {"error": "No answer from Calendar."}


if __name__ == "__main__":
    print(json.dumps(main(sys.argv[1:]), ensure_ascii=False))
