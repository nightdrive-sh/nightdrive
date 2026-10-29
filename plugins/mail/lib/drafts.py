#!/usr/bin/env python3
"""Drafts without Mail's window: written, thrown away and sent from a terminal, a script or Claude's tools (mcp.json).

    drafts.py draft                 a new draft in Drafts, from JSON on stdin: {to, cc, subject, body, account}, or a
                                    reply: {reply_to: message id, reply_all, body} (to, cc and subject then come from
                                    the message, unless given). Prints the draft as `show` does
    drafts.py show ID               a draft as it would be sent: {id, account, from, to, cc, subject, body, attachments}
    drafts.py discard ID            throws a draft away (only a draft: a message in an account's Drafts folder)
    drafts.py card ID               mail_send's rows on Nightdrive's card: what goes out that Claude saw hidden
                                    (unseen.py), or an error when it mustn't go from Claude's tools at all
    drafts.py send ID [--check]     sends a draft through the account's SMTP server (compose.py), files it in Sent and
                                    takes it out of Drafts

send --check reads on stdin what the user was shown ({from, to, cc, subject, body, attachments}: Claude's confirmation
card) and sends only if the draft says exactly that, so what goes out is what was allowed, even if the draft was
changed in between: it is sent from the very copy that was compared. An ID (a draft's, reply_to) must be one message's
id, exactly (ids.py): never a query. A new draft gets the account's signature, a reply also the quote, as Mail's own do.
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
import ids
import unseen


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def addresses(value):
    """To or Cc as a list of "Name <address>", from a list or a comma-separated string."""
    text = ", ".join(value) if isinstance(value, list) else str(value or "")
    return [formataddr(p) for p in getaddresses([text]) if p[1]]


def is_draft(msgid):
    """Every file of the message is in an account's Drafts folder: discard and send touch nothing else."""
    try:
        query = ids.one(msgid, threads=False)
    except LookupError:
        raise LookupError(f"No draft {msgid} (it may have been sent or thrown away)") from None
    root = notmuch("config", "get", "database.path").strip()
    drafts = {os.path.normpath(a["drafts"]) for a in compose.accounts().values() if a.get("drafts")}
    paths = [p for p in notmuch("search", "--output=files", "--exclude=false", "--query=sexp", query).split("\n") if p]
    if not paths:
        raise LookupError(f"No draft {msgid} (it may have been sent or thrown away)")
    for p in paths:
        folder = os.path.relpath(os.path.dirname(os.path.dirname(p)), root)   # account/Drafts of …/cur/<file>
        if os.path.normpath(folder) not in drafts:
            raise LookupError(f"{msgid} isn't a draft (it is in {folder}): only drafts are sent or thrown away")


def show(msgid):
    return read(msgid)[0]


def read(msgid):
    """The draft as show gives it, and the message it was read from (send sends that one)."""
    is_draft(msgid)
    msg = compose.parsed(msgid)
    aid = compose.account_id(msgid)
    acc = compose.account(aid)
    return {"id": msgid, "account": aid,
            # What sending puts in From: the account's name and address (compose.build), whatever the file says
            "from": formataddr((acc.get("name", ""), acc["address"])),
            "to": addresses(str(msg.get("To", ""))), "cc": addresses(str(msg.get("Cc", ""))),
            "subject": str(msg.get("Subject", "")), "body": compose.body_text(msg),
            "attachments": [os.path.basename(p.get_filename() or "") for p in msg.iter_attachments()]}, msg


def draft(f):
    accs = compose.accounts()
    if f.get("account") and f["account"] not in accs:
        raise LookupError(f"No account {f['account']!r}: the accounts are {', '.join(accs)}")
    text = str(f.get("body", "")).rstrip()
    if f.get("reply_to"):
        ids.one(f["reply_to"], threads=False)
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


# Claude gets a draft with its secrets hidden (config/mcp/mask.py: a code or a login link in the mail a reply quotes,
# #1861), and gives that copy back to send: the card then shows "[code hidden]" where the draft has the code, and the
# draft goes out whole. The card says so on a line of its own (card, unseen.py: #1878)
def masked(text):
    return unseen.masked(text)


def same(have, shown):
    """shown is the draft's text, or Claude's copy of it with the secrets hidden."""
    if lines(have) == lines(shown):
        return True
    return unseen.MASK.exists() and lines(masked(have)) == lines(shown)


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
    for key in ("subject", "body"):
        if not same(have[key], shown.get(key)):
            out.append(key)
    if sorted(have["attachments"]) != sorted(shown.get("attachments") or []):
        out.append("attachments")
    return out


def send(msgid, shown=None):
    have, msg = read(msgid)
    # A draft from another app may have Bcc, which Nightdrive Mail doesn't keep (compose.resume, build): it would go
    # out without them, and the card wouldn't show that either (#1866)
    if str(msg.get("Bcc", "")).strip():
        raise LookupError("Not sent: the draft has Bcc recipients, which Nightdrive Mail doesn't send (they would be "
                          "left out without a word). Send it from the app it was written in.")
    if shown is not None:
        unseen.check(have, msg)   # what Claude saw hidden doesn't go to someone the mail it quotes wasn't for
        wrong = differences(have, shown)
        if wrong:
            raise LookupError(f"Not sent: the draft isn't what was shown for it ({', '.join(wrong)} differ). Read it "
                              f"again (nightmail draft-show), and send it with exactly what it says.")
    if not have["to"] and not have["cc"]:
        raise LookupError("Not sent: the draft has no recipient")
    # From the copy just compared, not the file read again: a draft synced in between would go out unchecked
    fields = compose.resume(msgid, msg)
    fields["account"] = have["account"]
    result = compose.send(fields)
    if result.get("error"):
        raise RuntimeError(result["error"])
    return {"sent": result["id"], "from": have["from"], "to": have["to"], "cc": have["cc"], "subject": have["subject"]}


def card(msgid):
    """mail_send's rows on the card (confirm.facts): what the draft sends that Claude saw hidden."""
    have, msg = read(msgid)
    return unseen.check(have, msg)


def main():
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "draft" and not args:
        result = draft(json.loads(sys.stdin.read() or "{}"))
    elif cmd in ("show", "discard", "card") and len(args) == 1:
        result = {"show": show, "discard": discard, "card": card}[cmd](args[0])
    elif cmd == "send" and len([a for a in args if a != "--check"]) == 1:
        check = "--check" in args
        result = send(next(a for a in args if a != "--check"), json.loads(sys.stdin.read() or "{}") if check else None)
    else:
        sys.exit("usage: drafts.py draft < JSON | show ID | discard ID | card ID | send ID [--check < JSON]")
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
