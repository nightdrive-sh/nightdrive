"""Runs one tool's command for Nightdrive's MCP server (registry.py calls it; the format is plugins/README.md › Tools
for Claude: mcp.json).

A tool is a command a plugin already has: argv from its `command` template, with the call's arguments in place of
the `{name}` placeholders, run without a shell in the tool's folder, with a timeout. stdout comes back as the result
Claude reads; a failure comes back as a ToolError in plain words, which the server hands Claude as an error result.
"""

import json
import os
import re
import signal
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TIMEOUT = 30          # seconds, when a tool doesn't say
TIMEOUT_MAX = 300     # a tool can't ask for more: Claude Code waits on the call
OUTPUT_MAX = 100_000  # characters of stdout Claude gets; a long listing would only fill its context
MESSAGE_MAX = 4_000   # characters of stderr in an error

PLACEHOLDER = re.compile(r"\{([a-z_][a-z0-9_]*)\}")

TYPES = {
    "string": str, "boolean": bool, "object": dict, "array": list, "null": type(None),
    "number": (int, float), "integer": int,
}


class ToolError(Exception):
    """The tool ran and failed, or couldn't run; the message is for Claude to read."""


def placeholders(template):
    """The argument names a command template (or one string of it) uses."""
    if isinstance(template, str):
        return set(PLACEHOLDER.findall(template))
    return set().union(*(placeholders(t) for t in template)) if template else set()


def check(tool, arguments):
    """The arguments against the top level of the tool's inputSchema: Claude gets a message it can correct instead
    of a command that fails halfway. Deeper levels are the command's to check."""
    schema = tool.spec["inputSchema"]
    props = schema.get("properties", {})
    missing = [n for n in schema.get("required", []) if n not in arguments]
    if missing:
        raise ToolError(f"{tool.name} needs {', '.join(missing)}.")
    if schema.get("additionalProperties") is False:
        extra = sorted(set(arguments) - set(props))
        if extra:
            raise ToolError(f"{tool.name} has no argument {', '.join(extra)} (it takes: {', '.join(props) or 'none'}).")
    for name, value in arguments.items():
        prop = props.get(name)
        if not isinstance(prop, dict):
            continue
        if not is_type(value, prop.get("type")):
            raise ToolError(f"{tool.name}: {name} must be {prop['type']}, not {json_type(value)}.")
        if "enum" in prop and value not in prop["enum"]:
            raise ToolError(f"{tool.name}: {name} must be one of {', '.join(map(str, prop['enum']))}.")
        items = prop.get("items")
        if isinstance(value, list) and isinstance(items, dict) and not all(is_type(v, items.get("type")) for v in value):
            raise ToolError(f"{tool.name}: each of {name} must be {items['type']}.")


def is_type(value, wanted):
    if wanted is None:
        return True
    if isinstance(wanted, list):
        return any(is_type(value, w) for w in wanted)
    if wanted in ("number", "integer") and isinstance(value, bool):
        return False  # True is an int in Python, not in JSON
    if wanted == "integer" and isinstance(value, float):
        return value.is_integer()
    return isinstance(value, TYPES.get(wanted, object))


def json_type(value):
    return next((t for t, py in TYPES.items() if is_type(value, t) and t != "integer"), "something else")


def text(value):
    """One argument as command-line text: JSON's own spelling for what isn't a string."""
    return value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)


def given(value):
    return value is not None and value is not False


def expand(template, values, group=False):
    """A command template with the values in place: a whole-element placeholder of a list gives one element per item,
    a nested list (a group) is left out unless all its values are given, and a boolean in a group is the switch
    itself (its other elements are what it turns on)."""
    out = []
    for item in template:
        if isinstance(item, list):
            if all(given(values.get(n)) for n in placeholders(item)):
                out += expand(item, values, group=True)
            continue
        whole = PLACEHOLDER.fullmatch(item)
        if whole:
            name = whole.group(1)
            if name not in values:
                raise ToolError(f"needs {name}.")
            value = values[name]
            if isinstance(value, bool) and group:
                continue
            out += [text(v) for v in value] if isinstance(value, list) else [text(value)]
            continue
        for name in placeholders(item):
            if name not in values:
                raise ToolError(f"needs {name}.")
        out.append(PLACEHOLDER.sub(lambda m: text(values[m.group(1)]), item))
    return out


def environment(tool):
    """The server's environment, with the tool's commands first in PATH: the plugin's bin/ and this checkout's, so a
    worktree's server runs the worktree's commands; ~/.local/bin last, which a client may start us without."""
    env = dict(os.environ)
    path = [p for p in env.get("PATH", "/usr/bin:/bin").split(os.pathsep) if p]
    first = [str(d) for d in (tool.dir / "bin", REPO / "bin") if d.is_dir()]
    local = str(Path.home() / ".local/bin")
    env["PATH"] = os.pathsep.join(first + [p for p in path if p not in first] + ([] if local in path else [local]))
    env["NIGHTDRIVE_MCP"] = "1"
    env["NIGHTDRIVE_MCP_TOOL"] = tool.name
    return env


def execute(tool, argv, stdin, timeout):
    """Runs argv; (stdout, stderr, exit status). Its own session, so a timeout stops what it started too, and stdin
    never the server's: that is the protocol."""
    try:
        proc = subprocess.Popen(argv, cwd=tool.dir, env=environment(tool), start_new_session=True,
                                stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        raise ToolError(f"{argv[0]} isn't installed on this machine (not found in PATH).")
    except PermissionError:
        raise ToolError(f"{argv[0]} can't be run (no permission).")
    try:
        out, err = proc.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise ToolError(f"{tool.name} didn't finish in {timeout} s and was stopped.")
    return out, err, proc.returncode


def picture(body, field):
    """A tool's `image`: the field of its JSON output that holds a picture ({mimeType, data} in base64), taken out of
    the text and given as MCP's image content, which Claude sees. (body, [image content]) as they are without one."""
    try:
        data = json.loads(body)
        image = data.pop(field)
        content = {"type": "image", "data": image["data"], "mimeType": image["mimeType"]}
    except (ValueError, AttributeError, KeyError, TypeError):
        return body, []
    return json.dumps(data, ensure_ascii=False), [content]


def result(out, image=None):
    """stdout as MCP's tools/call result: the text, and a JSON object as structuredContent too."""
    body = out.strip()
    if not body:
        return {"content": [{"type": "text", "text": "Done."}]}
    if image:
        body, pictures = picture(body, image)
        if pictures:
            answer = result(body)
            answer["content"] += pictures
            return answer
    if len(body) > OUTPUT_MAX:
        cut = len(body) - OUTPUT_MAX
        return {"content": [{"type": "text", "text": body[:OUTPUT_MAX] + f"\n… ({cut} more characters left out)"}]}
    answer = {"content": [{"type": "text", "text": body}]}
    try:
        data = json.loads(body)
    except ValueError:
        return answer
    if isinstance(data, dict):
        answer["structuredContent"] = data
    return answer


def prepare(tool, arguments):
    """The argv and stdin text (None for none) of a call: what run() runs, and undo.py keeps for redo."""
    spec = tool.spec
    try:
        argv = expand(spec["command"], arguments)
        stdin = spec.get("stdin")
        if stdin == "json":
            stdin = json.dumps(arguments, ensure_ascii=False)
        elif stdin is not None:
            stdin = "".join(expand([stdin], arguments))
    except ToolError as e:
        raise ToolError(f"{tool.name} {e}")
    return argv, stdin


def timeout_of(tool):
    return min(tool.spec.get("timeout", TIMEOUT), TIMEOUT_MAX)


def run(tool, arguments):
    """One call: the tool's command with these (checked) arguments; MCP's tools/call result, or ToolError."""
    argv, stdin = prepare(tool, arguments)
    out, err, status = execute(tool, argv, stdin, timeout_of(tool))
    if status != 0:
        message = (err.strip() or out.strip() or "no message")[-MESSAGE_MAX:]
        raise ToolError(f"{tool.name} failed ({Path(argv[0]).name} exited with {status}): {message}")
    return result(out, tool.spec.get("image"))


def undo_values(arguments, answer, before=None):
    """What a change tool's `undo` fills its {name}s from: the fields of its `before` command's JSON
    (the state it changed), then of its own JSON output, then the call's arguments."""
    return {**arguments, **(answer.get("structuredContent") or {}), **(before or {})}


def undo_argv(tool, arguments, answer, before=None):
    """The argv that undoes a change tool's call (undo.py keeps it and runs it on Undo)."""
    return expand(tool.spec["undo"], undo_values(arguments, answer, before))
