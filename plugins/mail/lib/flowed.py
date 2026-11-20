#!/usr/bin/env python3
"""Which messages' plain text is format=flowed (#3321), for the read view (app/flowed.js joins its lines).

notmuch's JSON gives a part's Content-Type without its parameters, so the header is read from the message's file.
Usage: flowed.py ID FILE [ID FILE ...]. Prints one JSON object: {ID: delsp} for each message whose first plain text
part not sent as an attachment (the one Notmuch.qml's collect() shows) says format=flowed; delsp is true when it also
says DelSp=yes. A file that can't be read is left out, so its text keeps its lines."""

import email
import email.policy
import json
import sys


def flowed(path):
    """None when the message's shown text isn't flowed, else whether DelSp=yes."""
    with open(path, "rb") as f:
        msg = email.message_from_binary_file(f, policy=email.policy.compat32)
    for part in msg.walk():
        if part.is_multipart() or part.get_content_type() != "text/plain":
            continue
        if part.get_content_disposition() == "attachment":
            continue
        if (part.get_param("format") or "").lower() != "flowed":
            return None
        return (part.get_param("delsp") or "").lower() == "yes"
    return None


def main(args):
    out = {}
    for msgid, path in zip(args[0::2], args[1::2]):
        try:
            delsp = flowed(path)
        except OSError:
            continue
        if delsp is not None:
            out[msgid] = delsp
    print(json.dumps(out))


if __name__ == "__main__":
    main(sys.argv[1:])
