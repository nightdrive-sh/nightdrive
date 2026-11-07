"""An invitation answered: Accept, Maybe or Decline sent to its organiser from the account it came to (#2130):
`nightmail invitation MSGID --reply accept|maybe|decline [--calendar ID] [--card]` (invitation.py calls run()).

Calendar builds the iTIP REPLY (`calendar invite --reply`, its lib/invite_reply.py), this sends it as Mail sends any
message (compose.py: the account's SMTP server, a copy in Sent), a reply to the invitation's message, and then Calendar
keeps the answer in the event (`--answered`): an Accept or Maybe of one in no calendar puts it in --calendar's. Only a
press on the card's button, or Claude's call allowed on Nightdrive's card, runs it: nothing goes out by itself.
--card prints what the confirmation card shows, and sends nothing.

If sending fails, nothing is written and the error says so; if the mail went but the calendar can't take the answer,
it says so in note: the organiser has it either way.
"""

import smtplib
import ssl
import subprocess
from email.utils import formataddr

import compose

ANSWERS = ("accept", "maybe", "decline")


def options(args):
    """(answer, calendar, card) from --reply's arguments, or an error's text"""
    if not args or args[0] not in ANSWERS:
        return None, None, None, "The answer is accept, maybe or decline."
    answer, rest, calendar, card = args[0], args[1:], None, False
    while rest:
        if rest[0] == "--card":
            card, rest = True, rest[1:]
        elif rest[0] == "--calendar" and len(rest) > 1:
            calendar, rest = rest[1], rest[2:]
        else:
            return None, None, None, f"Unknown option {rest[0]}."
    return answer, calendar, card, None


def run(msgid, data, args, ask):
    """ask: invitation.py's `calendar invite` on the invitation's bytes"""
    answer, calendar, card, wrong = options(args)
    if wrong:
        return {"error": wrong}
    try:
        aid = compose.account_id(msgid)
        acc = compose.account(aid)
    except SystemExit as e:   # compose says a missing account.conf this way, as JSON
        return {"error": "No mail account to answer from: set one up in Mail first.", "detail": str(e)}
    reply = ask(data, ["--reply", answer, "--as", acc["address"], "--name", acc.get("name", "")])
    if reply.get("error"):
        return reply
    to = formataddr((reply["to_name"], reply["to"]))
    if card:
        shown = f"{reply['to_name']} <{reply['to']}>" if reply["to_name"] else reply["to"]   # not formataddr's =?utf-8?
        return {"Answer": reply["subject"].split(":", 1)[0], "To": shown, "From": acc["address"],
                "Invitation": reply["body"].split("\n\n", 1)[-1].strip()}
    original = compose.parsed(msgid)
    mid = str(original.get("Message-ID", "")).strip()
    fields = {"account": aid, "to": to, "subject": reply["subject"], "body": reply["body"], "calendar": reply["ics"]}
    if mid:
        fields["in_reply_to"] = mid
        fields["references"] = " ".join(filter(None, [str(original.get("References", "")).strip(), mid]))
    try:
        sent = compose.send(fields)
    except subprocess.CalledProcessError as e:
        return {"error": f"Not sent: {e.cmd[0]} failed ({(e.stderr or '').strip() or e.returncode})"}
    except ssl.SSLCertVerificationError as e:
        return {"error": f"Not sent: the mail server's certificate is not valid ({e.verify_message})"}
    except (smtplib.SMTPException, OSError) as e:
        return {"error": f"Not sent: {e}"}
    if sent.get("error"):
        return {"error": "Not sent: " + sent["error"]}
    out = {"ok": True, "answer": reply["answer"], "id": sent.get("id"),
           "said": f"Answer sent to {reply['to_name'] or reply['to']}: {reply['subject'].split(':', 1)[0]}"}
    kept = ask(data, ["--answered", answer, "--as", acc["address"], *(["--add", calendar] if calendar else [])])
    if kept.get("error"):
        out["note"] = "Your calendar doesn't show the answer: " + kept["error"]
    elif kept.get("note"):
        out["note"] = kept["note"]
    elif kept.get("done") == "answered" and kept.get("calendar_name"):
        out["said"] += f", and kept in {kept['calendar_name']}"
    return out
