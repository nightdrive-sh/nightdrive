"""What a Claude Code session did last, from its transcript: the last tool call ("Bash: npm test") or the start of its
last text, which is the question when it waits for you.

Claude Code keeps each conversation in ~/.claude/projects/<its folder, every character but letters and digits as ->/
<session id>.jsonl, one JSON object a line. A window doesn't say which conversation it runs, so this takes the folder's
newest transcript written since the session started: two sessions in one folder both show the one that wrote last.
"""
import glob
import json
import os
import re

CLAUDE = os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude"))
TAIL = 256 * 1024     # bytes read from the end: a last message is rarely longer
SHOWN = 160           # characters of a text or a command
# The input key that says what a tool call does, by tool
KEYS = ("command", "file_path", "notebook_path", "url", "pattern", "query", "description", "prompt")

_cache = {}           # path → (mtime, size, result)


def _short(text):
    text = re.sub(r"\s+", " ", str(text)).strip()
    text = text.replace(os.path.expanduser("~"), "~")
    return text if len(text) <= SHOWN else text[:SHOWN - 1] + "…"


def _describe(item):
    if item.get("type") == "tool_use":
        inp = item.get("input") or {}
        what = next((inp[k] for k in KEYS if inp.get(k)), "")
        return _short(f"{item.get('name', 'Tool')}: {what}" if what else item.get("name", "Tool"))
    if item.get("type") == "text" and item.get("text", "").strip():
        return _short(item["text"])
    return None


def _from_file(path):
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        f.seek(max(0, f.tell() - TAIL))
        lines = f.read().decode("utf-8", "replace").splitlines()
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue    # the first line, cut by the seek
        if entry.get("type") != "assistant" or entry.get("isSidechain"):
            continue
        content = (entry.get("message") or {}).get("content") or []
        if isinstance(content, str):
            return _short(content)
        for item in reversed(content):
            said = _describe(item)
            if said:
                return said
    return ""


def last(cwd, started):
    folder = os.path.join(CLAUDE, "projects", re.sub(r"[^A-Za-z0-9]", "-", cwd))
    files = []
    for p in glob.glob(os.path.join(folder, "*.jsonl")):
        try:
            st = os.stat(p)
        except OSError:
            continue
        if st.st_mtime >= started - 5:
            files.append((st.st_mtime, st.st_size, p))
    if not files:
        return ""
    mtime, size, path = max(files)
    hit = _cache.get(path)
    if hit and hit[:2] == (mtime, size):
        return hit[2]
    try:
        said = _from_file(path)
    except OSError:
        said = ""
    _cache[path] = (mtime, size, said)
    return said
