#!/usr/bin/env python3
"""Nightdrive's documentation as MCP tools: docs_search, docs_read and shortcuts (tools/docs.json; plan: Dashboard
#1761, #1764).

The docs are this checkout's own files, so Claude reads what this machine runs, not the website's newest: the README,
docs/*.md, each plugin's README.md (external plugins' too) and every SHORTCUTS.md. Only those files are readable:
docs_read takes a path docs_search gave and nothing else, so a tool for reading docs can't read the home folder.

A section is a Markdown heading and what follows it. Search scores sections by the query's words (in the heading
counts more), and read returns one section with its subsections.

Run as a command too: `docs.py TOOL` with the tool's arguments as JSON on stdin prints the result's text; a failure
exits 1 with the message on stderr.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
EXTERNAL = Path.home() / ".local/share/nightdrive/plugins"  # plugins from elsewhere (nightdrive plugins add)
SHORTCUTS = REPO / "config/hypr/scripts/shortcuts"  # the key list as the launcher and ⌘⇧K show it

RESULTS = 8          # docs_search's default number of sections, and its most (MAX_RESULTS)
MAX_RESULTS = 20
EXCERPT = 280        # characters of context around the first match
WHOLE_FILE = 12000   # docs_read without a section: a file up to this long whole, a longer one as its contents
MAX_READ = 30000     # docs_read's most, so one call can't flood the context

HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
FENCE = re.compile(r"^\s*(```|~~~)")
TAG = re.compile(r" *\{!?[a-z0-9-]+\}$")  # SHORTCUTS.md's "only with plugin X" marks (scripts/shortcuts)


class DocsError(Exception):
    """A call that can't be answered; the message tells Claude what to do instead."""


def files():
    """{shown path: file} of every readable doc. Paths are relative to the repo; an external plugin's start with
    plugins/ too (its id), as if it were in the repo, so Claude needn't know where it lives."""
    found = {}

    def add(path, label):
        if path.is_file():
            found[label] = path

    add(REPO / "README.md", "README.md")
    for p in sorted((REPO / "docs").glob("*.md")):
        add(p, f"docs/{p.name}")
    add(REPO / "config/hypr/SHORTCUTS.md", "config/hypr/SHORTCUTS.md")
    for base in (REPO / "plugins", EXTERNAL):
        for d in sorted(p for p in base.glob("*") if p.is_dir()):
            for name in ("README.md", "SHORTCUTS.md"):
                label = f"plugins/{d.name}/{name}"
                if label not in found:  # a repo plugin wins over an external one of the same id
                    add(d / name, label)
    if (REPO / "plugins/README.md").is_file():
        found["plugins/README.md"] = REPO / "plugins/README.md"
    return found


def sections(text):
    """The file's sections in order: {level, title, trail (the headings above it and its own), start, end, body}.
    end runs to the next heading of any level; read() widens it to take the subsections. Headings inside code
    fences don't count. Text before the first heading is a section titled "" at level 0."""
    lines = text.splitlines()
    out, trail, fenced = [], [], False
    current = {"level": 0, "title": "", "trail": [], "start": 0}
    for i, line in enumerate(lines):
        if FENCE.match(line):
            fenced = not fenced
        m = None if fenced else HEADING.match(line)
        if not m:
            continue
        current["end"] = i
        out.append(current)
        level, title = len(m.group(1)), m.group(2)
        trail = [t for t in trail if t[0] < level] + [(level, title)]
        current = {"level": level, "title": title, "trail": [t[1] for t in trail], "start": i}
    current["end"] = len(lines)
    out.append(current)
    for s in out:
        s["body"] = "\n".join(lines[s["start"]:s["end"]])
    return [s for s in out if s["title"] or s["body"].strip()]


def words(query):
    return [w for w in re.findall(r"[\w⌘⌥⇧⌃⌫+-]+", query.casefold()) if len(w) > 1 or not w.isascii()]


def excerpt(body, terms):
    flat = " ".join(TAG.sub("", line).strip() for line in body.splitlines()[1:] if line.strip())
    low = flat.casefold()
    hits = [low.find(t) for t in terms if t in low]
    at = min(hits) if hits else 0
    start = max(0, at - EXCERPT // 3)
    text = flat[start:start + EXCERPT]
    return ("…" if start else "") + text + ("…" if start + EXCERPT < len(flat) else "")


def docs_search(args):
    query = args.get("query")
    if not isinstance(query, str) or not words(query):
        raise DocsError("docs_search needs a query: a few words, e.g. \"wallpaper\" or \"clipboard history\"")
    terms = words(query)
    limit = args.get("limit", RESULTS)
    limit = max(1, min(MAX_RESULTS, limit if isinstance(limit, int) else RESULTS))
    phrase = " ".join(terms)
    scored = []
    for label, path in files().items():
        for s in sections(path.read_text(errors="replace")):
            title, body = s["title"].casefold(), s["body"].casefold()
            matched = [t for t in terms if t in body]
            if not matched:
                continue
            # Every word found ranks first, then how often: a heading hit counts three times, the words together
            # as typed ten, and a word's count stops at five; over the length, so a long section that mentions
            # everything doesn't bury the short one about it
            score = sum(3 * title.count(t) + min(5, body.count(t)) for t in matched)
            score += 10 * min(2, body.count(phrase)) if len(terms) > 1 else 0
            score /= (1 + len(body) / 3000) ** 0.5
            scored.append((len(matched), score, label, s))
    if not scored:
        return f"Nothing in Nightdrive's docs matches \"{query}\". Try other words, or fewer."
    scored.sort(key=lambda r: (-r[0], -r[1]))
    lines = [f"Sections of Nightdrive's docs matching \"{query}\", best first. Read one whole with docs_read "
             "(path and section as shown).", ""]
    for n, (_, _, label, s) in enumerate(scored[:limit], 1):
        where = " › ".join(s["trail"]) or "(top)"
        lines.append(f"{n}. {where}")
        lines.append(f"   path: {label}   section: {s['title'] or '(top)'}")
        lines.append(f"   {excerpt(s['body'], terms)}")
    if len(scored) > limit:
        lines.append(f"\n{len(scored) - limit} more sections match; a narrower query finds the right one sooner.")
    return "\n".join(lines)


def docs_read(args):
    label, wanted = args.get("path"), args.get("section")
    known = files()
    if not isinstance(label, str) or label.strip().lstrip("./") not in known:
        raise DocsError(f"No doc at {label!r}. docs_read reads only the paths docs_search shows: "
                        f"{', '.join(sorted(known))}")
    text = known[label.strip().lstrip("./")].read_text(errors="replace")
    parts = sections(text)
    if not wanted or not isinstance(wanted, str):
        if len(text) <= WHOLE_FILE:
            return clip(text)
        contents = "\n".join("  " * (s["level"] - 1) + f"- {s['title']}" for s in parts if s["level"])
        return clip(f"{label} is long; its sections (read one with section):\n{contents}\n\n{parts[0]['body']}")
    # The heading's own text, or its trail "A › B" when one title repeats; case doesn't matter
    key = wanted.strip().lstrip("#").strip().casefold()
    hit = next((i for i, s in enumerate(parts) if " › ".join(s["trail"]).casefold() == key), None)
    if hit is None:
        hit = next((i for i, s in enumerate(parts) if s["title"].casefold() == key), None)
    if hit is None:
        hit = next((i for i, s in enumerate(parts) if key in s["title"].casefold()), None)
    if hit is None:
        titles = ", ".join(s["title"] for s in parts if s["level"])
        raise DocsError(f"No section {wanted!r} in {label}. Its sections: {titles}")
    s = parts[hit]
    lines = text.splitlines()
    end = next((p["start"] for p in parts[hit + 1:] if 0 < p["level"] <= s["level"]), len(lines))
    return clip(f"{label} › {' › '.join(s['trail'])}\n\n" + "\n".join(lines[s["start"]:end]))


def shortcuts(args):
    """The key list as the user's desktop has it: only the installed plugins' lines, their own app keys in."""
    try:
        out = subprocess.run([str(SHORTCUTS)], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise DocsError(f"Couldn't read the keys: {e}")
    if out.returncode != 0 or not out.stdout.strip():
        raise DocsError(f"Couldn't read the keys: {out.stderr.strip() or 'no output'}")
    text = out.stdout
    query = args.get("query")
    terms = words(query) if isinstance(query, str) else []
    if terms:
        # The lines with every word, under their section's title
        keep, section = [], None
        for line in text.splitlines():
            if line.startswith("#"):
                section = line
            elif line.strip() and all(t in line.casefold() for t in terms):
                if section:
                    keep.append(section)
                    section = None
                keep.append(line)
        if not keep:
            return f"No key matches \"{query}\". Without a query, shortcuts lists them all."
        text = "\n".join(keep)
    return "⌘ is Super; Hyper is Caps Lock (Launcher › Settings › Apps › App shortcuts).\n\n" + text


def clip(text):
    if len(text) <= MAX_READ:
        return text
    return text[:MAX_READ] + "\n\n[cut here: read a narrower section]"


TOOLS = {"docs_search": docs_search, "docs_read": docs_read, "shortcuts": shortcuts}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in TOOLS:
        sys.exit(f"usage: docs.py {'|'.join(TOOLS)}  (the arguments as JSON on stdin)")
    raw = sys.stdin.read().strip()
    try:
        args = json.loads(raw) if raw else {}
        print(TOOLS[sys.argv[1]](args if isinstance(args, dict) else {}))
    except (json.JSONDecodeError, DocsError) as e:
        sys.exit(str(e))


if __name__ == "__main__":
    main()
