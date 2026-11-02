#!/usr/bin/env python3
"""Hides secrets in what a read tool gives Claude (Dashboard #1789, the security review's decisions: logs 3300, 3301,
3304, 3306, note 93). Mail, notifications, Ferry's box, notes and calendar invitations are full of what neither Claude
nor Anthropic needs and what a prompt injection would want most: one-time codes, login and password-reset links, card
numbers, passwords. They are replaced before the answer leaves the computer:

    4242 4242 4242 4242, CVV 123, exp 12/27   ->  •••• 4242, CVV [CVV hidden], exp [expiry hidden]
    FI21 1234 5600 0007 85                    ->  FI •••• 0785
    131052-308T                               ->  [identity code hidden]
    Password: Tr0ub4dor&3                     ->  Password: [password hidden]
    sk-ant-api03-…, ghp_…, a JWT, a private key  ->  [key hidden]
    Your verification code is 482913          ->  Your verification code is [code hidden]
    https://app.example.com/magic?token=…     ->  [login link hidden]
    Passcode: 8xYz42, …zoom.us/j/123?pwd=…    ->  Passcode: [code hidden], …zoom.us/j/123?pwd=[hidden]

The rest stays as it is: order and phone numbers, dates, prices and plain links aren't secrets, and the user often asks
about them. So each rule wants proof: a card number passes Luhn and looks like one, an IBAN its mod-97 check, an identity
code its check character, a code needs a word that says it is one ("code", "koodi", "PIN") next to it.
Invisible characters go first, and digits of other forms become 0-9 (visible()): "48<zero-width space>2913" is a code.

The registry applies it (registry.call) to the fields a tool's mcp.json names in `mask`, unless the user turned the area's
choice `secrets` on in Access (areas.py). `python3 mask.py` masks stdin, for trying a text; mask_test.py has the samples.
"""

import bisect
import importlib.util
import json
import re
import sys
import unicodedata
from pathlib import Path
from urllib.parse import unquote

CODE = "[code hidden]"
PASSWORD = "[password hidden]"
KEY = "[key hidden]"
LINK = "[login link hidden]"
ID_CODE = "[identity code hidden]"
CVV = "[CVV hidden]"
EXPIRY = "[expiry hidden]"
SECRET = "[code or password hidden]"   # a whole text its tool marked secret (Ferry's box: `"secret": true`)

NEAR_CARD = 120      # characters after a card number in which a bare expiry or CVV is the card's
CODE_REACH = 80      # characters between a code word and the code, after it
CODE_BEFORE = 60     # … and before it ("482913 is your code")
YEAR_REACH = 20      # a 4-digit year (1900–2099) is a code only this close after the word: "Code 2024", not "© 2024"
LINK_CONTEXT = 200   # characters before a link in which "sign in" or "reset your password" makes it a login link

# --- Keeping what is found ------------------------------------------------------------------------------------------
# What a rule found is swapped for a mark that no later rule matches (private-use characters, no digits or letters), so
# "•••• 4242" isn't read as a code, nor a link's digits as a card. The marks become their text at the end.
MARK = re.compile("\ue000(.)\ue001")


class Found:
    def __init__(self):
        self.texts = []

    def mark(self, text, kind=""):
        self.texts.append((text, kind))
        return "\ue000" + chr(0xF0000 + len(self.texts) - 1) + "\ue001"

    def kinds(self, text, kind):
        """The spans of the marks of one kind in text."""
        return [m.span() for m in MARK.finditer(text) if self.texts[ord(m.group(1)) - 0xF0000][1] == kind]

    def restore(self, text):
        return MARK.sub(lambda m: self.texts[ord(m.group(1)) - 0xF0000][0], text)


# --- Links ----------------------------------------------------------------------------------------------------------
URL = re.compile(r"https?://[^\s<>\"'`\]\)]+(?:\([^\s<>\"'`()]*\)[^\s<>\"'`\]\)]*)*", re.I)
LOGIN_WORDS = re.compile(r"reset|passw|magic|log-?in|sign-?in|sign_in|signon|auth|verif|confirm|activat|otp|one-?time|"
                         r"passwordless|token|kirjaudu|vahvist", re.I)
LOGIN_CONTEXT = re.compile(r"sign(?:ing)? in|log(?:ging)? in|login link|magic link|reset (?:your )?password|"
                           r"password reset|verify your (?:email|account)|confirm your (?:email|account)|"
                           r"kirjaudu|kirjautu|salasanan (?:vaihto|palautus|nollaus)|vaihda salasana|vahvista", re.I)
TOKEN_KEYS = re.compile(r"(?:^|[?&;])(?:token|code|key|otp|sig|signature|hash|auth|ticket|nonce|jwt|login|t|k)=([^&#;]{6,})",
                        re.I)
OPAQUE = re.compile(r"[A-Za-z0-9_~%=.-]{16,}")
MEETING_PASSWORD = re.compile(r"([?&](?:pwd|pass|password|passcode)=)[^&#\s]+", re.I)


def opaque(part):
    """A path segment or a query value that is a random token: long, letters and digits mixed."""
    return any(re.search(r"\d", t) and re.search(r"[A-Za-z]", t) for t in OPAQUE.findall(part))


def login_link(url, before):
    """A link that signs in or resets a password by itself: a word that says so and a token, in the link or just
    before it in the text. A link without a token (https://example.com/login) is only a page, and stays."""
    plain = unquote(unquote(url))
    path_and_query = plain.split("://", 1)[-1].partition("/")[2]
    has_token = bool(TOKEN_KEYS.search(path_and_query)) or opaque(path_and_query)
    return has_token and bool(LOGIN_WORDS.search(path_and_query) or LOGIN_CONTEXT.search(before[-LINK_CONTEXT:]))


def links(text, found):
    def one(m):
        url = m.group(0)
        tail = re.search(r"[.,;:!?]+$", url)   # the sentence's own punctuation after a link
        if tail:
            url = url[:tail.start()]
        rest = m.group(0)[len(url):]
        if login_link(url, text[:m.start()]):
            return found.mark(LINK) + rest
        return found.mark(MEETING_PASSWORD.sub(lambda p: p.group(1) + "[hidden]", url)) + rest
    return URL.sub(one, text)


# --- Keys and labelled secrets --------------------------------------------------------------------------------------
PRIVATE_KEY = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(?:-----END [A-Z ]*PRIVATE KEY-----|\Z)", re.S)
KEYS = re.compile(r"(?<![\w-])(?:"
                  r"sk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}|"                     # Anthropic, OpenAI
                  r"(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|"
                  r"glpat-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|"      # GitLab, Slack
                  r"(?:AKIA|ASIA)[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|"             # AWS, Google
                  r"(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{16,}|whsec_[A-Za-z0-9]{20,}|"   # Stripe
                  r"eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"  # a JWT
                  r")(?![\w-])")
BEARER = re.compile(r"(?<!\w)(Bearer\s+)[A-Za-z0-9._~+/=-]{16,}")

# A label, its separator (":" or "=", or " is "), its value. The kind decides the placeholder
LABELS = [
    (PASSWORD, r"passwords?|passwd|pwd|(?<!boarding )(?<!season )(?<!bus )pass|passphrase|app password|wi-?fi password|wlan key|network key|wpa key|"
               r"salasana(?:si|nsa|n)?|sovellussalasana|tunnussana|verkkoavain"),
    (KEY, r"api[ _-]?key|api[ _-]?token|secret[ _-]?key|client[ _-]?secret|secret|access[ _-]?key|access[ _-]?token|"
          r"auth[ _-]?token|refresh[ _-]?token|token|private[ _-]?key|recovery (?:key|codes?)|backup codes?|"
          r"palautusavain|varmuuskoodit"),
    (CODE, r"passcode|pin(?: code)?|puk|access code|meeting password|door code|gate code|alarm code|pääsykoodi|"
           r"ovikoodi|porttikoodi|hälytyskoodi|tunnusluku|verification code|security code|login code|"
           r"(?:vahvistus|kirjautumis)koodi"),
]
LABELLED = [(kind, re.compile(r"(?<![\w-])(" + words + r")((?:(?:\*\*|__)?[ \t]*[:=：][ \t]*(?:\*\*|__)?[ \t]*\n?[ \t]*)|[ \t]+(?:is|on|was)[ \t]+)"
                                    r"(\"[^\"\n]{1,200}\"|'[^'\n]{1,200}'|\d+(?:[ -]\d+)+#?(?=[.,;:)]*(?!\S))|[a-z]{4}(?: [a-z]{4}){3}(?!\S)|[^\s\ue000\ue001]+)", re.I))
            for kind, words in LABELS]


def strong(token):
    """A value that looks made, not written: a digit, a symbol, or capitals inside."""
    return bool(re.search(r"\d|[^\w\s]", token) or re.search(r"[a-z].*[A-Z]", token))


def labelled(text, found):
    for kind, pattern in LABELLED:
        def one(m, kind=kind, text=text):
            label, sep, value = m.groups()
            end = text.find("\n", m.end())
            after = text[m.end():end if end >= 0 else len(text)]
            if MARK.search(value):
                return m.group(0)
            # The sentence's full stop after it isn't the password's: "Your PIN is 1234."
            tail = "" if value[0] in "\"'" else re.search(r"[.,;:)]*$", value).group(0)
            value = value[:len(value) - len(tail)] or value
            spoken = sep.strip().lower() in ("is", "on", "was")
            # "Password: must be 8 characters" and "Your password is incorrect" are about one, not one
            if (spoken and not strong(value)) or (value.isalpha() and len(after.split()) >= 2):
                return m.group(0)
            return label + sep + found.mark(kind) + (tail if value != m.group(3) else "")
        text = pattern.sub(one, text)
    return text


# --- Card numbers ---------------------------------------------------------------------------------------------------
CARD = re.compile(r"(?<![\w+.,/#-])[2-6](?:[ ._-]?\d){12,18}(?![\w])(?![.,/-]\d)")   # 4111.1111…, 4111_1111… too
CARD_GROUPS = ([4, 6, 5], [4, 6, 4])   # American Express, Diners; the rest are fours
LABELLED_CVV = re.compile(r"(?<![\w-])(CVV2?|CVC2?|CID|CSC|security code|card code|turvakoodi|tarkistusnumero|"
                          r"varmistusnumero)(\W{0,3})(\d{3,4})(?!\d)", re.I)
LABELLED_EXPIRY = re.compile(r"(?<![\w-])(exp(?:iry|iration|ires)?(?: date)?|valid (?:thru|through)|good thru|"
                             r"voimassa(?:olo)?|vanhenee)(\W{0,3})((?:0?[1-9]|1[0-2])[ ]?/[ ]?(?:20)?\d{2})(?![\d/])",
                             re.I)
BARE_EXPIRY = re.compile(r"(?<![\d/.])(?:0?[1-9]|1[0-2])[ ]?/[ ]?(?:20)?\d{2}(?![\d/])")
BARE_CVV = re.compile(r"(?<![\w.,:/+-])(?<!\d[ -])\d{3}(?![\w]|[.,:/-]\d|[ -]\d)")


def luhn(digits):
    total = 0
    for i, d in enumerate(reversed(digits)):
        n = int(d) * (2 if i % 2 else 1)
        total += n - 9 if n > 9 else n
    return total % 10 == 0


def card_number(text):
    """The digits of a card number: Luhn, and written as cards are, in fours (Amex 4-6-5) or unbroken 15 or 16."""
    digits = re.sub(r"\D", "", text)
    if not 13 <= len(digits) <= 19 or not luhn(digits) or len(set(digits)) < 2:
        return None
    groups = [len(g) for g in re.split(r"[ ._-]", text)]
    if len(groups) == 1:
        return digits if len(digits) in (15, 16) else None
    fours = all(g == 4 for g in groups[:-1]) and 1 <= groups[-1] <= 4
    return digits if fours or groups in CARD_GROUPS else None


def cards(text, found):
    def one(m):
        # The longest start of it that is a card: "4242 4242 4242 4242 2027" is a card and then a year
        s = m.group(0)
        for end in [len(s)] + [i for i in range(len(s) - 1, 0, -1) if s[i] in " ._-"]:
            digits = card_number(s[:end])
            if digits:
                return found.mark("•••• " + digits[-4:], "card") + s[end:]
        return s
    text = CARD.sub(one, text)
    text = LABELLED_CVV.sub(lambda m: m.group(1) + m.group(2) + found.mark(CVV), text)
    # Only the labels that are a card's on their own: "Voimassa 12/26" is as often an offer's last month
    text = LABELLED_EXPIRY.sub(lambda m: m.group(0) if m.group(1).lower().startswith(("voimassa", "vanhenee"))
                               and not near_card(text, m.start(), found)
                               else m.group(1) + m.group(2) + found.mark(EXPIRY), text)
    # A bare 12/27 and 123 right after a card number are its expiry and CVV (a note: "Visa 4242… 12/27 123")
    for start, end in reversed(found.kinds(text, "card")):
        tail = text[end:end + NEAR_CARD]
        tail = BARE_EXPIRY.sub(lambda m: found.mark(EXPIRY), tail, count=1)
        tail = BARE_CVV.sub(lambda m: found.mark(CVV), tail, count=1)
        text = text[:end] + tail + text[end + NEAR_CARD:]
    return text


def near_card(text, at, found):
    return any(0 <= at - end <= NEAR_CARD for _, end in found.kinds(text, "card"))


# --- IBAN and the Finnish identity code -----------------------------------------------------------------------------
IBAN = re.compile(r"(?<![\w])([A-Z]{2})(\d{2})((?:[ ]?[A-Z0-9]{4}){2,7}(?:[ ]?[A-Z0-9]{1,3})?)(?![\w])")
ID_CHECK = "0123456789ABCDEFHJKLMNPRSTUVWXY"
IDENTITY = re.compile(r"(?<![\w-])(\d{2})(\d{2})(\d{2})([-+A-FU-Y])(\d{3})([0-9A-Y])(?![\w-])")


def iban_valid(compact):
    if not 15 <= len(compact) <= 34:
        return False
    moved = compact[4:] + compact[:4]
    return int("".join(str(int(c, 36)) for c in moved)) % 97 == 1


def ibans(text, found):
    def one(m):
        compact = re.sub(r"\s", "", m.group(0))
        # RF is a creditor reference (an invoice's), checked the same way but not an account
        if m.group(1) == "RF" or not iban_valid(compact):
            return m.group(0)
        return found.mark(f"{m.group(1)} •••• {compact[-4:]}")
    return IBAN.sub(one, text)


def identity_codes(text, found):
    def one(m):
        day, month, year, _, number, check = m.groups()
        if not (1 <= int(day) <= 31 and 1 <= int(month) <= 12):
            return m.group(0)
        valid = ID_CHECK[int(day + month + year + number) % 31] == check
        return found.mark(ID_CODE) if valid else m.group(0)
    return IDENTITY.sub(one, text)


# --- One-time codes -------------------------------------------------------------------------------------------------
CODE_WORD = re.compile(r"(?<!\w)(?:[\w-]*(?:code|koodi)\w*|passcodes?|otp|2fa|mfa|one[- ]time|kertakäyttö\w*|"
                       r"two[- ](?:factor|step)|kaksivaihe\w*|verification|verify|varmennus\w*|vahvistus\w*|"
                       r"tunnusluku\w*|PIN|PUK)(?!\w)", re.I)
# A code word that names another kind of code: these stay ("postal code 00100", "alennuskoodi KESÄ24")
NOT_CODE = re.compile(r"postal|post|zip|area|country|qr|source|error|status|promo|discount|coupon|voucher|gift|"
                      r"referral|alennus|kampanja|etu|lahja|posti|lähde|virhe|tuote|product|dress|bar|viiva|html|ean|"
                      r"tax|vat|unicode|codebase|decode|encode|codec|morse|maa|swift|bic|sort|iata|airport|sale|"
                      r"tracking|seuranta|lähetys|shipment|order|tilaus|reference|viite|invoice|lasku|customer|"
                      r"asiakas|booking|varaus", re.I)
NOT_CODE_AFTER = re.compile(r"reviews?|of|editor|block|snippet|style|quality|changes?|commits?|repo(?:sitory)?|signing|"
                            r"base|owners?", re.I)
# A code as one number, or as digits spaced out one or two at a time ("4 8 2 9 1 3", "48-29-13"): read aloud the same.
# One at a time also with underscores ("4_8_2_9_1_3", #1884) or dots, five or more ("4.8.2.9.1.3": 1.2.3.4 is a
# version); two at a time, not: 12.10.26 is a date
DIGITS = re.compile(r"(?<![\w.,:/+#€$£-])(?<!\d[ -])(?:G-)?(\d{4,8}|\d{3}[ _-]\d{3}|\d{4}[ _-]\d{4}|"
                    r"\d(?:[ -]\d){3,7}|\d(?:\.\d){4,7}|\d(?:_\d){3,7}|\d\d(?:[ -]\d\d){1,3})"
                    r"(?![\w%€$£]|[.,:/-]\d|[ -]\d)")
LETTERS_AND_DIGITS = re.compile(r"(?<![\w-])(?=[A-Z0-9-]*\d)(?=[A-Z0-9-]*[A-Z])[A-Z0-9]{2,8}(?:-[A-Z0-9]{2,8}){0,2}"
                                r"(?![\w-])")
NOT_A_CODE_TOKEN = {"2FA", "MFA", "OTP", "PIN", "PUK", "SMS", "G-", "4G", "5G", "3G", "MP3", "MP4", "A4", "USB-C"}
SENTENCE = re.compile(r"(?<=[.!?])(?=\s)|(?<=\n)")   # where re.split cuts a text into sentences and lines
LONE_CODE = re.compile(r"\s*(?:G-)?(?:\d{4,8}|\d{3}[ -]\d{3}|\d(?:[ -]\d){3,7}|\d\d(?:[ -]\d\d){1,3}|"
                       r"(?=[A-Z0-9-]*\d)(?=[A-Z0-9-]*[A-Z])[A-Z0-9-]{4,12})\s*")
# A number to use to sign in, with no code word: "Use 482913 to log in to Acme", "Sign in with 482913" (#1884). Only
# right after use/enter and before the sign-in, or after "sign in with": "Order 482913 shipped, log in to track it"
# and "Use 2024 budget, then log in" keep their numbers
SIGN_IN = r"(?:log(?:ging)?|sign(?:ing)?)[- ]?in|kirjaudu\w*|kirjautu\w*"
LOGIN_NUMBER = r"(?:G-)?(?:\d{4,8}|\d{3}[ -]\d{3})(?![\w.,/-]\d|\w)"
LOGIN_CODE = [re.compile(r"(?<!\w)(?:use|enter|type|input|käytä|syötä)\s+(?:the\s+)?(" + LOGIN_NUMBER +
                         r")(?=[ \t]*,?[ \t]*(?:(?:to|for|when|while|as|and|kun|ja)[ \t]+){0,2}(?:" + SIGN_IN +
                         r")(?!\w))", re.I),
              re.compile(r"(?<!\w)(?:" + SIGN_IN + r")\s+(?:with|using|by entering|by typing)\s+(" + LOGIN_NUMBER + ")",
                         re.I)]
DIAL_PASSCODE = re.compile(r"(,,\d{6,12}#(?:,,+)?\*?)(\d{4,10})(#)")   # a dial-in string's passcode: ,,845…#,,,,*123456#


def code_words(sentence):
    """The words in a sentence that say a code is near: not "postal code", "code review" nor "pin it"."""
    for m in CODE_WORD.finditer(sentence):
        before = sentence[max(0, m.start() - 20):m.start()].split()
        after = sentence[m.end():m.end() + 20].split()
        if m.group(0).lower() == "pin" and m.group(0) != "PIN":
            continue
        if NOT_CODE.search(m.group(0)) or (before and NOT_CODE.fullmatch(before[-1].strip(":,").lower())) or \
                (after and NOT_CODE_AFTER.fullmatch(after[0].strip(":,.").lower())):
            continue
        yield m


def codes_in(sentence, words, found):
    """The codes near a code word in one sentence."""
    # The words in order, looked up by bisect: a long text of codes and code words isn't every number by every word
    ends, starts = [w.end() for w in words], [w.start() for w in words]

    def word_before(at, reach):   # a word that ends at most reach characters before at
        i = bisect.bisect_right(ends, at)
        return i > 0 and at - ends[i - 1] <= reach

    def word_after(at, reach):    # a word that starts at most reach characters after at
        i = bisect.bisect_left(starts, at)
        return i < len(starts) and starts[i] - at <= reach

    spans = []
    for m in DIGITS.finditer(sentence):
        year = re.fullmatch(r"(?:19|20)\d\d", m.group(1))
        if word_before(m.start(), YEAR_REACH if year else CODE_REACH) or (not year and word_after(m.end(), CODE_BEFORE)):
            spans.append(m.span())
    numbers = list(spans)   # in order, apart: the last that starts before a token is the only one it can overlap
    for m in LETTERS_AND_DIGITS.finditer(sentence):
        i = bisect.bisect_left(numbers, (m.end(),))
        if m.group(0) in NOT_A_CODE_TOKEN or (i > 0 and numbers[i - 1][1] > m.start()):
            continue
        if word_before(m.start(), 40):
            spans.append(m.span())
    for s, e in sorted(spans, reverse=True):
        sentence = sentence[:s] + found.mark(CODE) + sentence[e:]
    return sentence


def one_time_codes(text, found):
    text = DIAL_PASSCODE.sub(lambda m: m.group(1) + found.mark(CODE) + m.group(3), text)
    for pattern in LOGIN_CODE:
        text = pattern.sub(lambda m: m.group(0)[:m.start(1) - m.start()] + found.mark(CODE) +
                           m.group(0)[m.end(1) - m.start():], text)
    out, carry = [], False
    for sentence in SENTENCE.split(text):
        words = list(code_words(sentence))
        if words:
            # "Your verification code:" or "Enter this code", then the code alone on a line of its own
            carry = sentence.rstrip().endswith(":") or not DIGITS.search(sentence[words[-1].end():])
            sentence = codes_in(sentence, words, found)
        elif carry and sentence.strip():
            if LONE_CODE.fullmatch(sentence) and sentence.strip() not in NOT_A_CODE_TOKEN:
                sentence = sentence.replace(sentence.strip(), found.mark(CODE))
            carry = False
        out.append(sentence)
    return "".join(out)


# --- A password alone on a line -------------------------------------------------------------------------------------
NOT_PASSWORD = re.compile(r"[A-Za-z]+[- ]?\d+[A-Za-z]?|"            # iPhone15, COVID-19, Windows11
                          r"v?\d+(?:\.\d+)+[\w.-]*|"                 # a version
                          r"\d[\d.,]*[A-Za-z/%°]+|"                  # a number with its unit: 100km/h
                          r"[#@].*|.*@.*\..*|[~/.].*|"               # a tag, a mention, an address, a path
                          r"(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?:/.*)?")   # a host or a file name


def lone_passwords(text, found):
    """A line that is one made-up word: letters, digits and capitals or symbols mixed (a note: "Gmail" then
    "Tr0ub4dor&3"). Product codes in capitals (INV-2024-0012) and versions stay."""
    def one(m):
        token = m.group(2)
        if not 8 <= len(token) <= 64 or MARK.search(token) or NOT_PASSWORD.fullmatch(token):
            return m.group(0)
        mixed_case = re.search(r"[a-z]", token) and re.search(r"[A-Z]", token)
        symbol = re.search(r"[^\w.\-/]", token)
        if re.search(r"\d", token) and re.search(r"[A-Za-z]", token) and (mixed_case or symbol):
            return m.group(1) + found.mark(PASSWORD) + m.group(3)
        return m.group(0)
    return re.sub(r"(?m)^([ \t]*)(\S+)([ \t]*)$", one, text)


# --- Invisible characters -------------------------------------------------------------------------------------------
# A model reads 482913 in "48<zero-width space>29<zero-width space>13" and in keycap emoji digits, but no rule above
# would see a number there, and an injection can ask a sender to write a code so (Dashboard #1861). So before the
# rules: digits of other forms (fullwidth, superscript, circled, mathematical) become 0-9 and spaces of other widths a
# space, then every character the confirmation card spells out goes (invisible.py: format characters, controls,
# Hangul fillers and the rest of Unicode's default-ignorables, #1932), and marks on a digit go. Only Claude's copy
# changes. A line break of another kind (U+2028, a lone CR) becomes a line feed, so two lines don't run together; a
# CR before a line feed stays. Emoji, keycaps and the joiners of Persian or Indic words read as before.


def _sibling(name):
    """A module beside this one, loaded by its path: Mail loads mask.py so (plugins/mail/lib/unseen.py), and its
    sys.path doesn't have this folder."""
    spec = importlib.util.spec_from_file_location("nightdrive_" + name, Path(__file__).resolve().with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


invisible = _sibling("invisible")
LINE_BREAKS = "\r\x0b\x0c\x1c\x1d\x1e\x85\u2028\u2029"
# Joiners and style selectors, the ones that stay or go by their neighbours
NEIGHBOURLY = re.compile("[" + invisible.NEIGHBOURLY + "]+")
# 4 + FE0F + 20E3 (a keycap), and a joiner after a digit with whatever marks follow
DIGIT_MARK = re.compile("(?<=[0-9])[\u0300-\u036f\u20d0-\u20ff\ufe00-\ufe0f" + invisible.JOINERS + "]+")


def plain(text, i):
    c = text[i]
    if invisible.always(c):
        if c == "\r" and text[i + 1:i + 2] == "\n":
            return c   # a CRLF line end stays as it was
        return "\n" if c in LINE_BREAKS else ""
    if not c.isascii() and unicodedata.digit(c, None) is not None:
        return str(unicodedata.digit(c))
    if c != " " and unicodedata.category(c) == "Zs":
        return " "   # a thin or no-break space between digits is a space: "482 913" (U+2009) is a code (#1884)
    return c


def neighbourly(text, m):
    """A run of joiners and style selectors, less those out of place. A joiner is judged by the characters around the
    whole run, not by its neighbour in it: 4 ZWJ ZWJ 8 is no more a word's than 4 ZWJ 8, nor 4 ZWJ <filler> ZWJ 8
    once plain() has taken the filler out."""
    before, after = text[m.start() - 1:m.start()] or "a", text[m.end():m.end() + 1] or "a"
    run = m.group(0)
    kept = []
    for i, c in enumerate(run, 1):
        if c in invisible.JOINERS:
            gone = invisible.hidden(before + c + after, 1)
        else:
            gone = invisible.hidden(before + run + after, i)   # a selector by its own neighbours
        if not gone:
            kept.append(c)
    return "".join(kept)


def visible(text):
    text = "".join(plain(text, i) for i in range(len(text)))
    text = NEIGHBOURLY.sub(lambda m: neighbourly(text, m), text)
    return DIGIT_MARK.sub("", text)


# --- All together ---------------------------------------------------------------------------------------------------
def mask(text):
    """text with its secrets hidden; anything else as it was."""
    if not isinstance(text, str) or not text:
        return text
    found = Found()
    text = visible(text)
    text = re.sub("[\ue000\ue001]", lambda m: found.mark(m.group(0)), text)   # the text's own, kept as they are
    text = PRIVATE_KEY.sub(lambda m: found.mark(KEY), text)
    text = links(text, found)
    text = KEYS.sub(lambda m: found.mark(KEY), text)
    text = BEARER.sub(lambda m: m.group(1) + found.mark(KEY), text)
    text = labelled(text, found)
    text = cards(text, found)
    text = ibans(text, found)
    text = identity_codes(text, found)
    text = one_time_codes(text, found)
    text = lone_passwords(text, found)
    return found.restore(text)


def apply(data, paths):
    """data (a tool's JSON output) with the fields at paths masked in place: "messages.text" is each message's text,
    a list on the way taken item by item. A field whose object says "secret": true is hidden whole."""
    for path in paths:
        walk(data, path.split("."))
    return data


def walk(node, keys):
    if isinstance(node, list):
        for item in node:
            walk(item, keys)
        return
    if not isinstance(node, dict) or keys[0] not in node:
        return
    if len(keys) > 1:
        walk(node[keys[0]], keys[1:])
        return
    whole = node.get("secret") is True
    value = node[keys[0]]
    if isinstance(value, str):
        node[keys[0]] = SECRET if whole and value else mask(value)
    elif isinstance(value, list):
        node[keys[0]] = [(SECRET if whole and v else mask(v)) if isinstance(v, str) else v for v in value]


def answer(result, paths):
    """A tools/call result with its secrets hidden: the JSON output's fields at paths, or the whole text when it isn't
    JSON (a cut one: run.OUTPUT_MAX)."""
    data = result.get("structuredContent")
    if isinstance(data, dict):
        apply(data, paths)
        return {"content": [{"type": "text", "text": json.dumps(data, ensure_ascii=False)}], "structuredContent": data}
    content = [dict(c, text=mask(c["text"])) if c.get("type") == "text" else c for c in result.get("content", [])]
    return dict(result, content=content)


if __name__ == "__main__":
    sys.stdout.write(mask(sys.stdin.read()))
