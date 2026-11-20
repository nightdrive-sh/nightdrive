#!/usr/bin/env python3
"""Builds detect.json, the letter statistics detect.py tells Finnish from English by.

    python3 detect_build.py > detect.json

The text is the desktop's own: every Finnish message catalogue in /usr/share/locale (the programs' English messages
and their Finnish translations), so both sides are the same kind of words. For each language it counts the words'
letter trigrams (with ^ and $ at the ends) and keeps, for the trigrams that tell the two apart, how much likelier one
is in Finnish than in English (log odds, in tenths). Nothing of the texts themselves ends up in the file.
"""
import gettext
import glob
import json
import math
import re
import sys
from collections import Counter

CATALOGUES = "/usr/share/locale/fi/LC_MESSAGES/*.mo"
KEEP = 6000          # trigrams kept: the most telling ones
WORD = re.compile(r"[a-zäöå]+")


def grams(word):
    padded = f"^{word}$"
    return [padded[i:i + 3] for i in range(len(padded) - 2)]


def main():
    counts = {"en": Counter(), "fi": Counter()}
    for path in sorted(glob.glob(CATALOGUES)):
        try:
            with open(path, "rb") as handle:
                catalogue = gettext.GNUTranslations(handle)._catalog
        except Exception:            # a catalogue gettext can't read: the others are plenty
            continue
        for source, target in catalogue.items():
            if source == target:         # left untranslated: English on the Finnish side
                continue
            for lang, text in (("en", source), ("fi", target)):
                if isinstance(text, tuple):
                    text = text[0]
                if not isinstance(text, str):
                    continue
                # Each word once per message, so one long repeated string doesn't weigh
                for word in set(WORD.findall(text.lower())):
                    if len(word) > 1:
                        counts[lang].update(grams(word))
    total = {lang: sum(c.values()) for lang, c in counts.items()}
    if min(total.values()) < 100000:
        sys.exit("detect_build: too little text in " + CATALOGUES)
    vocab = len(set(counts["en"]) | set(counts["fi"]))
    odds = {}
    for gram in set(counts["en"]) | set(counts["fi"]):
        if counts["en"][gram] + counts["fi"][gram] < 8:
            continue
        fi = (counts["fi"][gram] + 1) / (total["fi"] + vocab)
        en = (counts["en"][gram] + 1) / (total["en"] + vocab)
        odds[gram] = round(10 * math.log(fi / en))
    # The most telling of the common ones: weight by how often the trigram is met at all
    best = sorted(odds, key=lambda g: -abs(odds[g]) * math.log(counts["en"][g] + counts["fi"][g]))[:KEEP]
    json.dump({"grams": {g: odds[g] for g in sorted(best) if odds[g]}}, sys.stdout, ensure_ascii=False,
              separators=(",", ":"))
    print()


if __name__ == "__main__":
    main()
