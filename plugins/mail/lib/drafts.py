#!/usr/bin/env python3
"""Drafts without Mail's window: written, thrown away and sent from a terminal, a script or Claude's tools (mcp.json).

    drafts.py draft                 a new draft in Drafts, from JSON on stdin: {to, cc, subject, body, account}, or a
                                    reply: {reply_to: message id, reply_all, body} (to, cc and subject then come from
                                    the message, unless given). Prints the draft as `show` does
    drafts.py show ID               a draft as it would be sent: {id, account, from, to, cc, subject, body, attachments}
    drafts.py discard ID            throws a draft away (only a draft: a message in an account's Drafts folder)
    drafts.py send ID [--check]     sends a draft through the account's SMTP server (compose.py), files it in Sent and
                                    takes it out of Drafts

send --check reads on stdin what the user was shown ({from, to, cc, subject, body, attachments}: Claude's confirmation
card) and sends only if the draft says exactly that, so what goes out is what was allowed, even if the draft was
changed in between. A new draft gets the account's signature, a reply also the quote, as Mail's own do.
Failures go to stderr with exit status 1.
"""

import json
import os
import smtplib
import ssl
import subprocess
import sys
from email.utils import formataddr, getaddresses

import blocked
import compose


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def addresses(value):
    """To or Cc as a list of "Name <address>", from a list or a comma-separated string."""
    text = ", ".join(value) if isinstance(value, list) else str(value or "")
    return [formataddr(p) for p in getaddresses([text]) if p[1]]


def is_draft(msgid):
    """Every file of the message is in an account's Drafts folder: discard and send touch nothing else."""
    root = notmuch("config", "get", "database.path").strip()
    drafts = {os.path.normpath(a["drafts"]) for a in compose.accounts().values() if a.get("drafts")}
    paths = [p for p in notmuch("search", "--output=files", "--exclude=false", f'id:"{msgid}"').split("\n") if p]
    if not paths:
        raise LookupError(f"No draft {msgid} (it may have been sent or thrown away)")
    for p in paths:
        folder = os.path.relpath(os.path.dirname(os.path.dirname(p)), root)   # account/Drafts of …/cur/<file>
        if os.path.normpath(folder) not in drafts:
            raise LookupError(f"{msgid} isn't a draft (it is in {folder}): only drafts are sent or thrown away")


def show(msgid):
    is_draft(msgid)
    msg = compose.parsed(msgid)
    aid = compose.account_id(msgid)
    acc = compose.account(aid)
    return {"id": msgid, "account": aid,
            # What sending puts in From: the account's name and address (compose.build), whatever the file says
            "from": formataddr((acc.get("name", ""), acc["address"])),
            "to": addresses(str(msg.get("To", ""))), "cc": addresses(str(msg.get("Cc", ""))),
            "subject": str(msg.get("Subject", "")), "body": compose.body_text(msg),
            "attachments": [os.path.basename(p.get_filename() or "") for p in msg.iter_attachments()]}


def draft(f):
    accs = compose.accounts()
    if f.get("account") and f["account"] not in accs:
        raise LookupError(f"No account {f['account']!r}: the accounts are {', '.join(accs)}")
    text = str(f.get("body", "")).rstrip()
    if f.get("reply_to"):
        # The reply quotes it: mail Access › Mail keeps from Claude isn't answered by Claude either (blocked.py)
        if blocked.among([f["reply_to"]], blocked.query(blocked.entries())):
            raise LookupError(f"No message {f['reply_to']} (it may have been deleted, or not synced yet)")
        r = compose.reply(f["reply_to"], bool(f.get("reply_all")))
        fields = {k: r[k] for k in ("to", "cc", "subject", "in_reply_to", "references")}
        fields["account"] = f.get("account") or r["account"]
        fields["body"] = text + r["body"]                     # the signature and the quote, below the text
    else:
        sig = compose.signature(compose.account(f.get("account")))
        fields = {"account": f.get("account") or next(iter(accs)), "body": text + ("\n\n" + sig if sig else "") + "\n"}
    for key in ("to", "cc", "subject"):
        if key in f:
            fields[key] = ", ".join(addresses(f[key])) if key != "subject" else str(f[key])
    saved = compose.draft(fields)
    if saved.get("error"):
        raise RuntimeError(saved["error"])
    return show(saved["id"])


def discard(msgid):
    is_draft(msgid)
    compose.drop(msgid)
    return {"discarded": msgid}


def lines(text):
    """A text as compared: line ends and trailing spaces don't count, as the card doesn't show them."""
    return "\n".join(line.rstrip() for line in str(text or "").replace("\r\n", "\n").split("\n")).strip()


def differences(have, shown):
    """The fields where the draft isn't what the user was shown."""
    def pairs(v):
        return [(n.strip(), a.lower()) for n, a in getaddresses([", ".join(v) if isinstance(v, list) else str(v or "")]) if a]
    out = []
    for key in ("from", "to", "cc"):
        if pairs(have[key]) != pairs(shown.get(key, [] if key != "from" else "")):
            out.append(key)
    if lines(have["subject"]) != lines(shown.get("subject")):
        out.append("subject")
    if lines(have["body"]) != lines(shown.get("body")):
        out.append("body")
    if sorted(have["attachments"]) != sorted(shown.get("attachments") or []):
        out.append("attachments")
    return out


def send(msgid, shown=None):
    have = show(msgid)
    if shown is not None:
        wrong = differences(have, shown)
        if wrong:
            raise LookupError(f"Not sent: the draft isn't what was shown for it ({', '.join(wrong)} differ). Read it "
                              f"again (nightmail draft-show), and send it with exactly what it says.")
    if not have["to"] and not have["cc"]:
        raise LookupError("Not sent: the draft has no recipient")
    fields = compose.resume(msgid)
    fields["account"] = have["account"]
    result = compose.send(fields)
    if result.get("error"):
        raise RuntimeError(result["error"])
    return {"sent": result["id"], "from": have["from"], "to": have["to"], "cc": have["cc"], "subject": have["subject"]}


def main():
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "draft" and not args:
        result = draft(json.loads(sys.stdin.read() or "{}"))
    elif cmd in ("show", "discard") and len(args) == 1:
        result = show(args[0]) if cmd == "show" else discard(args[0])
    elif cmd == "send" and len([a for a in args if a != "--check"]) == 1:
        check = "--check" in args
        result = send(next(a for a in args if a != "--check"), json.loads(sys.stdin.read() or "{}") if check else None)
    else:
        sys.exit("usage: drafts.py draft < JSON | show ID | discard ID | send ID [--check < JSON]")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except SystemExit as e:
        # compose.accounts() exits with {"error": …} as JSON when there's no account
        if isinstance(e.code, str) and e.code.startswith("{"):
            sys.exit(json.loads(e.code).get("error", e.code))
        raise
    except subprocess.CalledProcessError as e:
        sys.exit(f"{e.cmd[0]} failed: {(e.stderr or '').strip() or e.returncode}")
    except StopIteration:
        sys.exit("The message's file is missing: sync, then try again")
    except ssl.SSLCertVerificationError as e:
        sys.exit(f"Not sent: the mail server's certificate is not valid ({e.verify_message})")
    except (smtplib.SMTPException, OSError) as e:
        sys.exit(f"Sending failed: {e}")
    except (LookupError, RuntimeError, ValueError) as e:
        sys.exit(str(e))
