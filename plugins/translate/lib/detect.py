"""Which of the pair's two languages a text is in, so nobody has to pick a direction.

Only Finnish against English is told apart here: by the words' letter trigrams (detect.json, made by
detect_build.py), which is right for most single words and nearly every sentence, and costs 30 kB instead of a
model. A single word that is in the system's English spelling dictionary (hunspell's, when installed) and doesn't look
clearly Finnish counts as English: the trigrams alone take "milk" and "lake" for Finnish. A wrong guess is one key
away in the launcher ("the other way"). Any other pair gets None, and the caller takes the pair's first language.
"""
import json
import re
from pathlib import Path

DATA = Path(__file__).with_name("detect.json")
WORD = re.compile(r"[a-zäöå]+")
# The few short words that settle a sentence whatever its other words look like
EN_WORDS = frozenset("a an the and or of to in on at by for from with is are was were be it you he she we they not "
                     "this that what which who when where why how can could will would have has had do does did "
                     "my your i me".split())
FI_WORDS = frozenset("ja tai on ei en et oli ole olen olet se ne tämä tuo minä sinä hän me te he että kun koska niin "
                     "kuin myös vain jo nyt mikä kuka missä miksi miten kanssa voi voisi".split())
SURE = 30            # a function word's weight, in the table's unit (tenths of log odds)
ENGLISH_DIC = Path("/usr/share/hunspell/en_US.dic")
CLEARLY_FINNISH = 45  # a score above this stays Finnish though the word is in the English dictionary too
_grams = None
_english = None


def _table():
    global _grams
    if _grams is None:
        try:
            _grams = json.loads(DATA.read_text())["grams"]
        except (OSError, ValueError, KeyError):
            _grams = {}
    return _grams


def _english_words():
    """The dictionary's lower-case entries; empty without hunspell-en-US (the trigrams then decide alone)."""
    global _english
    if _english is None:
        try:
            lines = ENGLISH_DIC.read_text(encoding="utf-8", errors="replace").splitlines()[1:]
            _english = frozenset(w for w in (line.split("/", 1)[0] for line in lines) if w.islower())
        except OSError:
            _english = frozenset()
    return _english


def score(text):
    """Above zero: Finnish, below: English. 0 when nothing in the text tells."""
    table, total = _table(), 0
    for word in WORD.findall(text.lower()):
        if re.search(r"[äö]", word):
            total += SURE                    # ä and ö never appear in English
        if word in FI_WORDS:
            total += SURE
        if word in EN_WORDS:
            total -= SURE
        padded = f"^{word}$"
        total += sum(table.get(padded[i:i + 3], 0) for i in range(len(padded) - 2))
    return total


def detect(text, first, second):
    """`first` or `second`, whichever the text looks like; None when this pair can't be told apart here."""
    if {first, second} != {"fi", "en"}:
        return None
    value = score(text)
    words = WORD.findall(text.lower())
    if len(words) == 1 and value < CLEARLY_FINNISH and words[0] not in FI_WORDS and words[0] in _english_words():
        return "en"
    if value == 0:
        return None
    return "fi" if value > 0 else "en"
