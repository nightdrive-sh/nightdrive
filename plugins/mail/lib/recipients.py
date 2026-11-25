"""To and Cc as Mail splits and shows them (#3593).

A name may hold a comma ("Virtanen, Aino" <aino@example.com>), quotes, or come as an encoded word
(=?utf-8?q?Nieminen=2C_Ville?=), so a list is never split on commas by hand: getaddresses() keeps a quoted name
whole. Its names are then decoded, so a draft shows "Mäkinen, Liisa" rather than =?utf-8?b?…?= (formataddr()
encodes any name that isn't ASCII, which is right in a header but unreadable on Claude's card)."""

import re
from email.header import decode_header, make_header
from email.utils import getaddresses

# A name with one of these goes in quotes, as RFC 5322 wants: a bare comma would split it again
SPECIALS = re.compile(r'[()<>\[\]:;@\\,."]')


def decoded(name):
    """A name with its encoded words (RFC 2047) decoded; a name that doesn't decode stays as it was."""
    if "=?" not in name:
        return name
    try:
        return str(make_header(decode_header(name)))
    except (ValueError, LookupError):
        return name


def pairs(value):
    """(name, address) for each recipient, from a header's text or a list of them; entries without an address dropped."""
    texts = [str(v) for v in value] if isinstance(value, (list, tuple)) else [str(value or "")]
    return [(decoded(n).strip(), a.strip()) for n, a in getaddresses(texts) if a.strip()]


def shown(name, address):
    """One recipient as a person reads it: Name <address>, the name quoted when it must be, never encoded."""
    if not name:
        return address
    if SPECIALS.search(name):
        name = '"' + name.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return f"{name} <{address}>"


def listed(value):
    """Each recipient as shown(), from a header's text or a list."""
    return [shown(n, a) for n, a in pairs(value)]


def addresses(value):
    """Only the addresses, as SMTP gets them."""
    return [a for _, a in pairs(value)]
