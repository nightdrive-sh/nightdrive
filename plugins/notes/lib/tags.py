"""A note's tags, read from its text: nothing is stored anywhere else (#2016). A tag is "#" and a word that starts with a
letter, as Bear and Obsidian write them: #idea, #työ, #project/notes (a slash nests it: #project takes it in too). It
begins a line or follows a space or an opening bracket, so a heading ("# Title", a space after the mark), a task's
number (#2016), a link's anchor (page#part) and a colour's hex (#1e1e2e) aren't tags; neither is anything in code (a
fenced block or `code`) or in a link's address.

The window shows the same tags (Markdown.js draws them by the same pattern: keep the two alike).
"""

import re

# The tag's word: it starts with a letter, then letters, digits, _ - and / inside it, ending in a letter, digit or _
# ("#a-" is "#a"). A letter is Latin (with its accents), Greek or Cyrillic: QML's JavaScript has no \p{L}, and the window
# must draw as tags the same ones the sidebar lists.
L = "A-Za-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u024F\u0370-\u03FF\u0400-\u04FF"
TAG = re.compile(rf"(?:^|(?<=[\s(\[]))#([{L}][{L}0-9_/-]*[{L}0-9_]|[{L}])")
FENCE = re.compile(r"^\s*(```|~~~)")
CODE = re.compile(r"`[^`]*`")
LINK_TARGET = re.compile(r"\]\([^)]*\)")


def tags_of(text):
    """The note's tags in the order they first come, each once (case aside: the first way it is written is kept)."""
    seen, tags = set(), []
    fenced = False
    for line in text.splitlines():
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        line = LINK_TARGET.sub("]", CODE.sub(" ", line))
        for m in TAG.finditer(line):
            tag = m.group(1).rstrip("/")
            if tag.lower() not in seen:
                seen.add(tag.lower())
                tags.append(tag)
    return tags


def has_tag(tags, tag):
    """Whether a note with these tags is under the tag: it itself, or one nested in it (#project takes #project/notes)."""
    want = tag.lstrip("#").lower()
    return any(t.lower() == want or t.lower().startswith(want + "/") for t in tags)


def counts(notes):
    """Every tag of the notes (their briefs) with how many notes have it, by name (case aside)."""
    named, n = {}, {}
    for note in notes:
        for t in note.get("tags", []):
            key = t.lower()
            named.setdefault(key, t)
            n[key] = n.get(key, 0) + 1
    return [{"name": named[k], "count": n[k]} for k in sorted(named)]
