#!/usr/bin/env python3
"""Attachments of a message being read: open one, or save it.

    parts.py open MSGID PART NAME    copies the part to ~/.cache/nightmail/parts/ and prints {"path": ...} to open
    parts.py save MSGID PART NAME    copies it to the downloads folder, next to what is there, and prints {"path": ...}
    parts.py save-all MSGID PART NAME [PART NAME …]
                                     the same for each, and prints {"paths": [...]}
    parts.py html MSGID              writes the message's HTML for the browser, with nothing that loads from the network,
                                     to $XDG_RUNTIME_DIR/nightmail/ and prints {"path": ...} to open. With remote images
                                     in it, a bar at the top links to a second page that loads them.

PART is notmuch's part number (`notmuch show --format=json` lists them), NAME the attachment's file name.
Failures are {"error": "..."}.
"""

import base64
import email
import email.policy
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import urllib.parse

PARTS = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "nightmail", "parts")
# The HTML pages: in memory (tmpfs), the user's alone, gone at logout. Never in /tmp, where another user could make
# the folder first and read the mail.
PAGES = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "nightmail")

# First in the page: the browser loads nothing but what is in the file, so no remote image or font tells the sender
# the message was opened. Pictures sent with the message are in the file (data: URIs); links still open when clicked.
HEAD = """<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:{images}; style-src 'unsafe-inline'; font-src data:; form-action 'none'">
<meta http-equiv="x-dns-prefetch-control" content="off">
<meta name="referrer" content="no-referrer">
"""
# Remote images, which the sender may use to see that the message was opened: on the blocked page only this bar says
# so, and links to the page that loads them (images only: scripts and the rest stay out there too)
REMOTE = re.compile(r"""(\b(src|srcset|background)\s*=\s*["']?\s*|url\(\s*["']?\s*)(https?:)?//""", re.I)
BAR = """<div style="all: initial; display: block; padding: 9px 16px; background: #2a2631; color: #e8e4ee;
 font: 14px/1.4 system-ui, sans-serif; text-align: center">Remote images are blocked, so the sender
 can't tell you opened this. <a href="{href}" style="all: initial; color: #c9a7f0; font: inherit; font-weight: 600;
 cursor: pointer; text-decoration: underline">Load images</a></div>
"""


def downloads():
    try:
        d = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True).stdout.strip()
    except OSError:
        d = ""
    return d if d and d != os.path.expanduser("~") else os.path.expanduser("~/Downloads")


def free(folder, name):
    """A path in folder that takes nothing over: name, then name (2), name (3) …"""
    stem, ext = os.path.splitext(name)
    path, n = os.path.join(folder, name), 2
    while os.path.exists(path):
        path, n = os.path.join(folder, f"{stem} ({n}){ext}"), n + 1
    return path


def write(cmd, msgid, part, name):
    name = os.path.basename(name) or "attachment"
    data = raw(msgid, part)
    if cmd == "open":
        folder = os.path.join(PARTS, hashlib.sha1(msgid.encode()).hexdigest()[:12])
        path = os.path.join(folder, name)
    else:
        folder = downloads()
        path = free(folder, name)
    os.makedirs(folder, exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)
    return path


def raw(msgid, part=None):
    args = ["notmuch", "show", "--format=raw"] + (["--part=" + part] if part else []) + [f'id:"{msgid}"']
    return subprocess.run(args, capture_output=True, check=True).stdout


def page(msgid):
    msg = email.message_from_bytes(raw(msgid), policy=email.policy.default)
    body = msg.get_body(preferencelist=("html",))
    if body is None:
        raise ValueError("This message has no HTML version")
    text = body.get_content()
    # Pictures sent with the HTML (multipart/related), by Content-ID, as data: URIs
    pics = {}
    for part in msg.walk():
        cid = part.get("Content-ID")
        if cid and not part.is_multipart():
            data = part.get_payload(decode=True) or b""
            pics[cid.strip().strip("<>")] = f"data:{part.get_content_type()};base64,{base64.b64encode(data).decode()}"
    text = re.sub(r"cid:([^\"'\s)>]+)", lambda m: pics.get(urllib.parse.unquote(m.group(1)), m.group(0)), text, flags=re.I)
    # What could still reach out, or take the page's head over: scripts, frames, linked files, the sender's own meta
    # tags (a refresh, which no policy stops, a policy, a charset) and a base for relative links. Again until nothing
    # changes: a tag split by another (<me<meta>ta http-equiv=refresh …>) forms once the inner one goes.
    while True:
        was = text
        text = re.sub(r"<script\b.*?</script\s*>", "", text, flags=re.I | re.S)
        text = re.sub(r"<(script|link|meta|base|i?frame|object|embed)\b[^>]*>", "", text, flags=re.I)
        if text == was:
            break
    title = ""
    if not re.search(r"<title\b[^>]*>\s*[^<\s]", text, re.I):
        title = f"<title>{html.escape(msg.get('Subject', '') or '(no subject)')}</title>\n"
    # Our head before anything of the sender's: after their doctype, a comment or <textarea> of theirs could swallow it
    # (<!--><textarea><!-- --><!doctype html></textarea>) and leave the policy as text. Their doctype moves up to the
    # top, so the page keeps the mode it was laid out for, and any others go. The bar opens the body: the sender's
    # <html>, <head> and <body> after it only add their attributes.
    doctype = re.search(r"<!doctype\b[^<>]*>", text, re.I)
    text = re.sub(r"<!doctype\b[^>]*>", "", text, flags=re.I)
    top = (doctype.group(0) if doctype else "") + "\n<html><head>\n"
    stem = hashlib.sha1(msgid.encode()).hexdigest()[:12]
    os.makedirs(PAGES, mode=0o700, exist_ok=True)

    def write(name, images, bar):
        page = top + HEAD.format(images=images) + title + "</head><body>\n" + bar + text
        path = os.path.join(PAGES, name)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(page)
        return path

    bar = ""
    if REMOTE.search(text):
        write(stem + "-images.html", " https: http:", "")
        bar = BAR.format(href=stem + "-images.html")
    return write(stem + ".html", "", bar)


def main():
    cmd, msgid = sys.argv[1:3]
    if cmd == "html":
        print(json.dumps({"path": page(msgid)}))
    elif cmd == "save-all":
        pairs = sys.argv[3:]
        print(json.dumps({"paths": [write("save", msgid, pairs[i], pairs[i + 1]) for i in range(0, len(pairs) - 1, 2)]}))
    else:
        print(json.dumps({"path": write(cmd, msgid, sys.argv[3], sys.argv[4])}))


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, OSError, ValueError, LookupError) as e:
        print(json.dumps({"error": str(e)}))
