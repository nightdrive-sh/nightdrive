#!/usr/bin/env python3
"""A newsletter's unsubscribe link (#2393): Mail's Unsubscribe button in a message's header, and mail_thread's
"unsubscribe".

    unsubscribe.py MSGID…     {"links": {MSGID: {"url", "kind": "web"|"mail", "from": "header"|"body"}}}, only the
                              messages that have one

Where it comes from, the first that has one:
1. The List-Unsubscribe header (RFC 2369): <https://…> and <mailto:…> entries, https preferred, then mailto, then
   plain http. A sender's List-Unsubscribe-Post (RFC 8058's one-click POST) is never used: nothing is posted or sent
   here or by the button, which only opens the link in the browser or a prefilled message the user sends.
2. A link in the body: in the HTML, an <a> whose text or address says unsubscribe (in a few languages); else one whose
   text nearby says it ("To stop these emails, click here"). In a plain text, a URL on a line that says it, or on the
   line after one.

Only web and mailto links are returned: anything else (javascript:, file:) would do something at a stranger's word.
"""

import email
import email.policy
import json
import re
import subprocess
import sys
from html.parser import HTMLParser

import ids

MAX_HTML = 2_000_000     # characters of a body read for links: a newsletter's footer is well within it
NEAR = 120               # characters of text before a link read as "nearby"

# What the words for it look like, case-insensitive. Stems, so Finnish inflections match ("peruuttaa tilauksen").
WORDS = re.compile("|".join([
    r"unsubscri", r"\bunsub\b", r"opt[\s-]?out\b", r"manage (your )?(email )?(subscription|preferences)",
    r"\bperu\w*\s+(\w+\s+)?(tilau|uutiskirj)", r"\blopet\w*\s+(\w+\s+)?(tilau|uutiskirj)", r"tilauksen\s+peru",
    r"postituslista(lta|sta)", r"\birtisano\w*\s+(\w+\s+)?(tilau|uutiskirj)",
    r"avsluta\s+(din\s+)?prenumeration", r"avregistrer", r"säg\s+upp", r"avprenumerer",
    r"abmelde", r"abbestell", r"austragen",
    r"d[ée]sabonn", r"d[ée]sinscri", r"darse de baja", r"cancelar (la )?suscripci", r"disiscriv", r"uitschrijv",
    r"afmeld", r"meld (deg|dig) av",
    # The sentence before a "click here"
    r"no longer (wish|want) to receive", r"stop receiving", r"do(n'?t| not) want to receive",
    r"\bet halua (enää )?(vastaanottaa|saada)", r"vill inte (längre )?(få|ta emot)", r"nicht mehr (erhalten|empfangen)",
]), re.IGNORECASE)

URL = re.compile(r"(?:https?://|mailto:)[^\s<>\"']+", re.IGNORECASE)


def kind(url):
    """"web", "mail", or None for a link that may not open."""
    if re.match(r"https?://[^/\s]", url, re.IGNORECASE):
        return "web"
    if re.match(r"mailto:[^\s]", url, re.IGNORECASE):
        return "mail"
    return None


def link(url, source):
    url = url.strip().rstrip(".,;:)!?")
    k = kind(url)
    return {"url": url, "kind": k, "from": source} if k else None


def from_header(value):
    """The best link in a List-Unsubscribe value: https, then mailto, then http."""
    if not value:
        return None
    # An entry may be folded over lines, with spaces inside the brackets
    found = [re.sub(r"\s+", "", u) for u in re.findall(r"<([^>]*)>", str(value))]
    rank = lambda u: 0 if u.lower().startswith("https:") else 1 if u.lower().startswith("mailto:") else 2
    for url in sorted(found, key=rank):
        got = link(url, "header")
        if got:
            return got
    return None


class _Anchors(HTMLParser):
    """The <a href>s of an HTML body, each with its own text and the text before it."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.text = ""          # all the visible text so far
        self.anchors = []       # [href, text, text before]
        self.open = None
        self.skip = 0           # inside <style> or <script>

    def handle_starttag(self, tag, attrs):
        if tag in ("style", "script"):
            self.skip += 1
        elif tag == "a":
            href = dict(attrs).get("href") or ""
            self.open = [href.strip(), "", self.text[-NEAR:]]
            self.anchors.append(self.open)
        elif tag in ("br", "p", "div", "tr", "td", "li"):
            self.text += " "

    def handle_endtag(self, tag):
        if tag in ("style", "script"):
            self.skip = max(0, self.skip - 1)
        elif tag == "a":
            self.open = None

    def handle_data(self, data):
        if self.skip:
            return
        self.text += data
        if self.open is not None:
            self.open[1] += data


def from_html(html):
    parser = _Anchors()
    try:
        parser.feed(html[:MAX_HTML])
        parser.close()
    except Exception:       # a broken body leaves the anchors found so far
        pass
    anchors = [(h, " ".join(t.split()), b) for h, t, b in parser.anchors if kind(h)]
    # Its own text or address says it; else the text just before it ("…no longer wish to receive, click here").
    # The last such link: a footer's is the newsletter's own, a "manage" link in an article isn't.
    for test in (lambda h, t, b: WORDS.search(t) or WORDS.search(h), lambda h, t, b: WORDS.search(b)):
        hits = [h for h, t, b in anchors if test(h, t, b)]
        if hits:
            return link(hits[-1], "body")
    return None


def from_text(text):
    lines = text.splitlines()
    for i in range(len(lines) - 1, -1, -1):
        urls = URL.findall(lines[i])
        if urls and (WORDS.search(lines[i]) or (i and WORDS.search(lines[i - 1]))):
            hit = [u for u in urls if WORDS.search(u)] or urls
            got = link(hit[-1], "body")
            if got:
                return got
    return None


def body(msg, subtype):
    part = msg.get_body(preferencelist=(subtype,))
    if part is None:
        return ""
    try:
        return part.get_content()
    except Exception:       # an unknown charset: what Python can make of it
        return (part.get_payload(decode=True) or b"").decode("utf-8", "replace")


def find(msg):
    """The unsubscribe link of an email.message.EmailMessage, or None."""
    try:
        header = msg.get("List-Unsubscribe")
    except Exception:       # a header too broken to parse
        header = None
    return from_header(header) or from_html(body(msg, "html")) or from_text(body(msg, "plain"))


def raw(msgid):
    return subprocess.run(["notmuch", "show", "--format=raw", "--query=sexp", ids.message(msgid)],
                          capture_output=True, check=True).stdout


def of(msgid):
    """A message's link by its id as the database gave it, or None (also for one that can't be read)."""
    try:
        return find(email.message_from_bytes(raw(msgid), policy=email.policy.default))
    except (subprocess.CalledProcessError, ValueError, LookupError):
        return None


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: unsubscribe.py MSGID…")
    links = {m: got for m in sys.argv[1:] if (got := of(m))}
    print(json.dumps({"links": links}))


if __name__ == "__main__":
    main()
