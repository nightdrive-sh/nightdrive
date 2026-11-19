"""What a Claude Code session did last, from its transcript: the last tool call ("Bash: npm test") or the start of its
last text, which is the question when it waits for you.

Claude Code keeps each conversation in <its config dir>/projects/<its folder, every character but letters and digits
as ->/<session id>.jsonl, one JSON object a line. claude-sessions finds a session's own by its id and account; without
that, this takes the folder's newest transcript written since the session started.
A question asked with AskUserQuestion isn't written here until it is answered: it shows only in the terminal.
"""
import glob
import json
import os
import re

CLAUDE = os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude"))
TAIL = 256 * 1024     # bytes read from the end: a last message is rarely longer
SHOWN = 160           # characters of a command (one line on its tile)
SAID = 1200           # characters of a text: the tile shows the whole lines it has room for (web/sessions.js fitLines)
RECENT = 60           # things said and done the session's own view shows
RECENT_TAIL = 1024 * 1024   # bytes read for it
LONG = 6000           # characters of one text in it
# The input key that says what a tool call does, by tool
KEYS = ("command", "file_path", "notebook_path", "url", "pattern", "query", "description", "prompt", "skill", "to")
# A tool_result that says you said no, rather than that the tool failed (Claude Code's wording, and its safety check's)
DENIED = re.compile(r"doesn't want to proceed|tool use was rejected|denied by|permission .{0,40}denied", re.I)
# A command's own `cd somewhere &&` (or ;) before what it runs: the session's folder is on its tile already
CD = re.compile(r"^\s*cd\s+(\"[^\"]*\"|'[^']*'|\S+)\s*(&&|;)\s*")

_cache = {}           # path → (mtime, size, result), for last()
_recent_cache = {}    # the same for recent()


def _short(text, limit=SHOWN):
    text = re.sub(r"\s+", " ", str(text)).strip()
    text = text.replace(os.path.expanduser("~"), "~")
    return text if len(text) <= limit else text[:limit - 1] + "…"


def _tool(name):
    """A tool's name to read (#3218): mcp__claude_ai_Dashboard__log_add → Dashboard: log add, mcp__nightdrive__inbox_update
    → Inbox: update (Nightdrive's tools are named area_verb), mcp__easel__chart → Easel: chart; the rest as it is."""
    parts = name.split("__")
    if len(parts) < 3 or parts[0] != "mcp":
        return name
    server, tool = re.sub(r"^(claude_ai_|plugin_[^_]+_)", "", parts[1]), "__".join(parts[2:])
    if server == "nightdrive" and "_" in tool:
        server, tool = tool.split("_", 1)
    server = server.replace("_", " ").replace("-", " ").strip()
    return f"{server[:1].upper()}{server[1:]}: {tool.replace('_', ' ')}"


def _describe(item):
    if item.get("type") == "tool_use":
        inp = item.get("input") or {}
        what = next((inp[k] for k in KEYS if inp.get(k)), "")
        if item.get("name") == "Bash" and isinstance(what, str):
            what = CD.sub("", what, count=1)
        name = _tool(item.get("name") or "Tool")
        # an MCP tool's name has its own colon: what it did on goes after a dot
        return _short(f"{name}{' · ' if ': ' in name else ': '}{what}" if what else name)
    if item.get("type") == "text" and item.get("text", "").strip():
        return _short(item["text"], SAID)
    return None


def _lines(path, tail):
    """The transcript's last tail bytes as entries, oldest first (the first line, cut by the seek, left out)."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        f.seek(max(0, f.tell() - tail))
        lines = f.read().decode("utf-8", "replace").splitlines()
    out = []
    for line in lines:
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict) and not entry.get("isSidechain"):
            out.append(entry)
    return out


def _items(entry):
    content = (entry.get("message") or {}).get("content") or []
    return [{"type": "text", "text": content}] if isinstance(content, str) else \
        [c for c in content if isinstance(c, dict)]


def _from_file(path):
    for entry in reversed(_lines(path, TAIL)):
        if entry.get("type") != "assistant":
            continue
        for item in reversed(_items(entry)):
            said = _describe(item)
            if said:
                return said
    return ""


def _queued(entry):
    """A prompt you gave while the session was at work (#3147): Claude Code reads it in with its next tool result and
    writes it not as a user's message but as an attachment, {"type": "attachment", "attachment": {"type":
    "queued_command", "prompt": …, "origin": {"kind": "human"}}}, where it was read in. The prompt is text, or a
    list of parts when it came with an image. Another session's message and a background task's notice come the same
    way, with another origin: not yours, so not shown."""
    a = entry.get("attachment") or {}
    if a.get("type") != "queued_command" or (a.get("origin") or {}).get("kind") != "human":
        return None
    prompt = a.get("prompt")
    if isinstance(prompt, list):
        prompt = "\n".join(str(c.get("text") or "") for c in prompt if isinstance(c, dict) and c.get("type") == "text")
    text = str(prompt or "").strip()
    return text if text and not text.startswith("<") else None


def _conversation(path):
    """What the session's own view shows (web/detail.js): your prompts, also those given while it worked, Claude's
    texts whole up to LONG, and its tool calls as one line each. Tool results, thinking and Claude Code's own wrappers
    (<command-name>, <system-reminder>, which come as a user's text) are left out, but a result's outcome marks its
    call (#3218): "error" (is_error: a command's exit code other than 0, a refused edit), "denied" (you, or a safety
    check, said no), "running" (no result yet: at work, or waiting for your permission); none when it went through."""
    out = []
    calls = {}            # tool_use id → its line in out
    for entry in _lines(path, RECENT_TAIL):
        role = entry.get("type")
        if role == "attachment":
            text = _queued(entry)
            if text:
                out.append({"role": "user", "kind": "text", "text": text[:LONG]})
            continue
        if role not in ("user", "assistant") or entry.get("isMeta"):
            continue
        for item in _items(entry):
            if item.get("type") == "tool_result" and item.get("tool_use_id") in calls:
                _outcome(calls.pop(item["tool_use_id"]), item)
                continue
            text = str(item.get("text") or "").strip()
            if item.get("type") == "text" and text and not (role == "user" and text.startswith("<")):
                out.append({"role": role, "kind": "text", "text": text[:LONG]})
            elif item.get("type") == "tool_use" and role == "assistant":
                out.append({"role": role, "kind": "tool", "text": _describe(item), "status": "running"})
                if item.get("id"):
                    calls[item["id"]] = out[-1]
    waiting = {id(line) for line in calls.values()}
    for line in out:
        if line.get("status") == "running" and id(line) not in waiting:
            del line["status"]            # a call with no id to match its result by: nothing known, shown as done
    return out[-RECENT:]


def _outcome(line, result):
    del line["status"]
    if not result.get("is_error"):
        return
    said = result.get("content")
    if isinstance(said, list):
        said = " ".join(str(c.get("text") or "") for c in said if isinstance(c, dict))
    line["status"] = "denied" if DENIED.search(str(said or "")[:300]) else "error"


def _newest(cwd, started):
    """(mtime, size, path) of the folder's newest transcript written since the session started, or None."""
    folder = os.path.join(CLAUDE, "projects", re.sub(r"[^A-Za-z0-9]", "-", cwd))
    files = []
    for p in glob.glob(os.path.join(folder, "*.jsonl")):
        try:
            st = os.stat(p)
        except OSError:
            continue
        if st.st_mtime >= started - 5:
            files.append((st.st_mtime, st.st_size, p))
    return max(files) if files else None


def _find(path, cwd, started):
    """(mtime, size, path): the session's own transcript when claude-sessions found it, else the folder's newest (an
    older claude-sessions, or a Claude Code without a session record: two sessions in one folder then show one)."""
    if path:
        try:
            st = os.stat(path)
            return st.st_mtime, st.st_size, path
        except OSError:
            pass
    return _newest(cwd, started)


def _cached(cache, where, read, empty):
    found = _find(*where)
    if not found:
        return empty
    mtime, size, path = found
    hit = cache.get(path)
    if hit and hit[:2] == (mtime, size):
        return hit[2]
    try:
        result = read(path)
    except OSError:
        result = empty
    cache[path] = (mtime, size, result)
    return result


def last(path, cwd, started):
    return _cached(_cache, (path, cwd, started), _from_file, "")


def recent(path, cwd, started):
    """The last RECENT things said and done in the session, oldest first."""
    return _cached(_recent_cache, (path, cwd, started), _conversation, [])
