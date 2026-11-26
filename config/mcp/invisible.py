#!/usr/bin/env python3
"""The characters that are drawn as nothing or change how text reads, defined once for the two that must agree:
the confirmation card spells each one out as ⟨U+…⟩ (confirm.py, #1922), so Allow sends nothing the user didn't see,
and the masking takes them out of Claude's copy (mask.py, #1932), so "48<Hangul filler>2913" is a code like 482913.
When the two had a set each, the masking's (category Cf only) missed the fillers the card showed.

What counts: control characters, the line and paragraph separators Qt breaks a line at (one value would read as two,
#1887), every format character (category Cf: bidi marks, zero-width spaces, the soft hyphen, invisible operators, the
tag letters of "ASCII smuggling") and whatever else Unicode lets a font draw as nothing (Default_Ignorable_Code_Point:
variation selectors, the combining grapheme joiner, Hangul fillers, unassigned tags), which isn't all Cf. Tab and line
feed are text. Two kinds depend on their neighbours, so emoji, keycaps and scripts that need a joiner read as written:
a zero-width joiner or non-joiner between two characters outside ASCII (an emoji family, Persian, Indic), and one
text or emoji style selector after a character it can style (a heart, a keycap's digit).
"""

import re
import unicodedata

# Default_Ignorable_Code_Point (Unicode's DerivedCoreProperties.txt) beyond what the categories below already take
IGNORABLE = re.compile(r"[­͏؜ᅟᅠ឴឵᠋-᠏​-‏‪-‮"
                       r"⁠-⁯ㅤ︀-️﻿ﾠ￰-￸\U0001bca0-\U0001bca3"
                       r"\U0001d173-\U0001d17a\U000e0000-\U000e0fff]")
CATEGORIES = ("Cc", "Cf", "Zl", "Zp")
JOINERS = "‌‍"       # ZWNJ, ZWJ
PRESENTATION = "︎️"  # text style, emoji style
NEIGHBOURLY = JOINERS + PRESENTATION
KEYCAP = "⃣"


def always(c):
    """Whether c is unseen wherever it stands: everything above but the joiners and style selectors."""
    if c in "\t\n" or c in NEIGHBOURLY:
        return False
    return unicodedata.category(c) in CATEGORIES or bool(IGNORABLE.match(c))


def hidden(text, i):
    """Whether text[i] is unseen where it stands: always(), or a joiner or style selector out of place."""
    c = text[i]
    before, after = text[i - 1] if i else "a", text[i + 1:i + 2] or "a"
    if c in JOINERS:
        return before.isascii() or after.isascii()
    if c in PRESENTATION:
        # Only one, and only after a character it can style, so a run of them carries nothing: a keycap's digit, or a
        # letter, number or symbol outside ASCII (an emoji). Not after a mark, a space or another selector.
        keycap = before in "0123456789#*" and after == KEYCAP
        return not (keycap or (not before.isascii() and unicodedata.category(before)[0] in "LNPS"))
    return always(c)
