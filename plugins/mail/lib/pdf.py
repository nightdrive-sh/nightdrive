"""A message as a PDF (#2291), for save.py: its headers, then its HTML as Mail's browser page shows it with remote
images blocked (parts.cleaned), or its text, printed by headless Chromium (a Nightdrive package, packages.txt).

Nothing is fetched while it is drawn: a stranger's remote image tells them the mail was opened, and when. So:
- the page is parts.cleaned()'s: no scripts, frames, linked files, meta refreshes or base;
- its Content-Security-Policy (parts.HEAD, images: none) lets in only what is in the file, so no image, style sheet,
  @import, font or media loads from anywhere;
- Chromium itself runs with a fresh profile, no background requests, every host name resolving to nothing and a
  proxy that leads nowhere: should anything get past the policy, it has no network to reach. (Scripts are out by the
  first two; Chromium's own switch for them, blink-settings scriptEnabled=false, stops its headless print too.)
Links stay links in the PDF; nothing follows them.
"""

import html
import os
import shutil
import subprocess
import tempfile
import unicodedata
from email.utils import format_datetime, parsedate_to_datetime

import parts

RENDER_TIMEOUT = 45     # seconds for Chromium to print (the tool's timeout is 60)
CHROMIUM = ("chromium-browser", "chromium")
# Chromium's switches that keep it off the network and away from the user's own profile
OFFLINE = ["--headless", "--disable-gpu", "--no-first-run", "--no-default-browser-check", "--disable-extensions",
           "--disable-sync", "--disable-background-networking", "--disable-component-update", "--disable-default-apps",
           "--disable-domain-reliability", "--no-pings",
           "--host-resolver-rules=MAP * ~NOTFOUND", "--proxy-server=socks5://127.0.0.1:9",
           "--no-pdf-header-footer"]
# The page's own: margins, and a remote image (blocked) not drawn as a broken one
STYLE = """<style>
@page { margin: 14mm 12mm; }
img[src^="http" i], img[src^="//"] { display: none !important; }
</style>
"""
HEADER = ("From", "To", "Cc", "Date", "Subject")
# all: initial, so the sender's style sheet doesn't restyle the headers (it may still hide them with !important: then
# the PDF lacks them, which is the sender's page, not a leak)
BOX = "all: initial; display: block; font: 12px/1.45 system-ui, sans-serif; color: #222; margin: 0 0 14px"
ROW = "all: initial; display: block; font: inherit; color: inherit"
KEY = "all: initial; font: inherit; font-weight: 600; color: #555"
TEXT = "white-space: pre-wrap; word-wrap: break-word; font: 13px/1.5 system-ui, sans-serif; color: #111"


def when(value):
    try:
        return format_datetime(parsedate_to_datetime(value).astimezone()).rsplit(" ", 1)[0]   # without the +0200
    except (TypeError, ValueError):
        return value


def visible(text):
    """A header's text without control and format characters: a stranger's right-to-left override would turn the rest
    of the line around ("report\u202etxt.exe" shows as "reportexe.txt")."""
    return "".join(" " if c.isspace() else c for c in text if c.isspace() or unicodedata.category(c) not in ("Cc", "Cf"))


def header(msg, attached):
    rows = []
    for key in HEADER:
        value = msg.get(key)
        if value:
            value = visible(when(str(value)) if key == "Date" else str(value))
            rows.append(f'<span style="{ROW}"><span style="{KEY}">{key}:</span> {html.escape(value)}</span>')
    if attached:
        names = html.escape(visible(", ".join(attached)))
        rows.append(f'<span style="{ROW}"><span style="{KEY}">Attachments:</span> {names}</span>')
    return f'<div style="{BOX}">' + "".join(rows) + '<hr style="all: initial; display: block; border-top: 1px solid ' \
        '#bbb; margin-top: 10px"></div>\n'


def document(msg):
    """The page to print: headers, then the HTML (blocked as Mail's page has it) or the text."""
    attached = [p.get_filename() or "" for p in msg.iter_attachments() if p.get_filename()]
    head = parts.HEAD.format(images="") + STYLE
    if msg.get_body(preferencelist=("html",)) is not None:
        top, title, body = parts.cleaned(msg)
        return top + head + visible(title) + "</head><body>\n" + header(msg, attached) + body
    plain = msg.get_body(preferencelist=("plain",))
    text = plain.get_content() if plain is not None else ""
    title = f"<title>{html.escape(visible(msg.get('Subject', '') or '(no subject)'))}</title>\n"
    return ("<!doctype html>\n<html><head>\n" + head + title + "</head><body>\n" + header(msg, attached)
            + f'<div style="{TEXT}">{html.escape(text)}</div>\n</body></html>\n')


def render(page):
    """The page printed by Chromium, as PDF bytes. Its files are in Mail's runtime folder (the user's alone, in
    memory), gone when it's done."""
    chromium = next((shutil.which(c) for c in CHROMIUM if shutil.which(c)), None)
    if not chromium:
        raise OSError("Saving as PDF needs Chromium (sudo dnf install chromium)")
    os.makedirs(parts.PAGES, mode=0o700, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=parts.PAGES, prefix="pdf-") as tmp:
        src, out = os.path.join(tmp, "message.html"), os.path.join(tmp, "message.pdf")
        fd = os.open(src, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(page)
        argv = [chromium, *OFFLINE, f"--user-data-dir={tmp}/profile", f"--print-to-pdf={out}", "file://" + src]
        try:
            run = subprocess.run(argv, capture_output=True, text=True, timeout=RENDER_TIMEOUT)
        except subprocess.TimeoutExpired:
            raise OSError(f"Chromium didn't finish the PDF in {RENDER_TIMEOUT} s")
        if not os.path.isfile(out) or os.path.getsize(out) == 0:
            said = run.stderr.strip().splitlines() or [f"exit {run.returncode}"]
            raise OSError("Chromium made no PDF: " + said[-1])
        with open(out, "rb") as fh:
            return fh.read()
