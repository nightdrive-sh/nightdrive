"""A permission request whole, as Companion shows it before its Allow (protocol.md › Permission requests).

Allow answers for the whole tool_input, so Companion offers it for an edit, a write, an MCP tool or a command with more
than its text set only after showing every key of it in full: claude-notify leaves the input in <address>.input
({request, input}) beside <address>.perm, while it waits, when it is short enough (WHOLE there). Each value comes as
text, nothing cut, and a character that wouldn't show (a bidi override, a zero-width space, a control) is written out
as ⟨U+XXXX⟩, so what you read is what Claude Code runs.
"""
import json
import os
import re
import unicodedata

REQUEST = re.compile(r"[A-Za-z0-9]{1,32}")      # mktemp's random part, in claude-notify
# Categories of characters that show nothing, or something other than themselves: controls (but a line break and a
# tab, which <pre> shows as such), format characters (bidi overrides and isolates, zero-width ones), private use,
# surrogates, unassigned; line and paragraph separators; and spaces other than the plain one (U+00A0 and the like look
# like it and aren't).
HIDDEN = {"Cc", "Cf", "Co", "Cs", "Cn", "Zl", "Zp", "Zs"}
SHOWN_AS_THEMSELVES = {"\n", "\t", " "}


def visible(text):
    """(text with every character that wouldn't show as ⟨U+XXXX⟩, how many there were)."""
    out, n = [], 0
    for ch in text:
        if ch not in SHOWN_AS_THEMSELVES and unicodedata.category(ch) in HIDDEN:
            out.append(f"⟨U+{ord(ch):04X}⟩")
            n += 1
        else:
            out.append(ch)
    return "".join(out), n


def fields(tool_input):
    """[{key, text, hidden}]: each key of the input in its order, its value as text (a string as it is, anything else as
    JSON) with hidden characters written out. A key's name gets the same treatment: it is shown too."""
    out = []
    for key, value in tool_input.items():
        raw = value if isinstance(value, str) else json.dumps(value, indent=2, ensure_ascii=False)
        name, n_key = visible(str(key))
        text, n = visible(raw)
        out.append({"key": name, "text": text, "hidden": n + n_key})
    return out


def read(state, address, request):
    """The request's input as fields, or None: no input left (too long, an old hook), or one for another request
    (the session asks something new, and its input isn't this one's)."""
    if not REQUEST.fullmatch(str(request or "")):
        return None
    try:
        with open(os.path.join(state, f"{address}.input")) as f:
            got = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(got, dict) or got.get("request") != request or not isinstance(got.get("input"), dict):
        return None
    return fields(got["input"])


def whole(state, address, request):
    """Whether Companion can show the request whole, and so offer its Allow after it."""
    return read(state, address, request) is not None
