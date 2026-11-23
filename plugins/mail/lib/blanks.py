"""A plain-text message's blank lines tidied (#3318): the reply's quote, as app/blanks.js does for the read view.

A line of only whitespace and invisible characters (newsletters' NBSP lines and preheader filler) counts as blank:
each run of them becomes one empty line, and those at the start and end go. Other lines stay as they are, trailing
spaces too ("-- " is a signature's separator). blanks_test.py (in app/) tests both on the same cases."""

import re

# The same class as blanks.js: whitespace, and the characters that draw nothing (soft hyphen, combining grapheme
# joiner, zero-width and direction marks, word joiner and its kin, Hangul fillers). Python's \s lacks U+FEFF.
BLANK = re.compile("^[\\s﻿­͏؜ᅟᅠ឴឵᠎​-‏‪-‮"
                   "⁠-⁯ㅤﾠ]*$")


def tidy(text):
    out = []
    for line in re.split(r"\r?\n", text):
        if not BLANK.match(line):
            out.append(line)
        elif out and out[-1] != "":
            out.append("")
    if out and out[-1] == "":
        out.pop()
    return "\n".join(out)
