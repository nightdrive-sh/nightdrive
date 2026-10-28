#!/usr/bin/env python3
"""Nightdrive's MCP server: the protocol only (`nightdrive mcp` runs it; plan: Dashboard #1761).

JSON-RPC 2.0 over stdio, one message a line (MCP's stdio transport), Python's stdlib only. It answers initialize,
ping, tools/list and tools/call; every other request gets MCP's "method not found". What the tools are and how they
run is not this file's business: it asks a tool provider (`list()` and `call(name, arguments)`, see testtools.py),
so the registry of plugins' mcp.json files (registry.py) slots in without the protocol changing.

stdout carries the protocol and nothing else; diagnostics go to stderr, which Claude Code keeps as the server's log.
"""

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from testtools import TestTools, ToolError, UnknownTool  # noqa: E402  (after the path above)

NAME = "nightdrive"
# Newest first. A client asking for one of these gets it back; any other gets the newest, and the client decides
# whether it can live with that (MCP › Lifecycle › Version negotiation).
PROTOCOL_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

INSTRUCTIONS = """\
Nightdrive is a desktop for Fedora built on Hyprland and Quickshell: a top bar with menus, a launcher, and its own \
apps (Mail, Contacts, Deck, Ferry) and plugins. These tools act on the desktop of the person you are talking to, on \
this machine. Which tools you see follows their Settings › Claude › Access: what is off isn't listed at all. Tools \
that change something tell the user, who can undo it; those with consequences (sending, devices, installing) ask the \
user on screen first, and a refusal there is the user's answer, not an error to work around.

Nightdrive's documentation is in your tools, as this machine has it: docs_search before you guess how something \
works, where a setting is or which command does it, then docs_read for the section; shortcuts for the keys; \
nightdrive_status for the version, channel, theme, displays and which apps and plugins are installed. Settings are in \
the launcher (⌘ Space › Settings), and most have a `nightdrive` command (`nightdrive help` lists them). Answer with \
the path a user clicks or the key they press, as the docs give it."""

# JSON-RPC 2.0's error codes, as MCP uses them
PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INTERNAL_ERROR = -32603


class RpcError(Exception):
    """A request that gets an error response instead of a result."""

    def __init__(self, code, message, data=None):
        super().__init__(message)
        self.code, self.message, self.data = code, message, data


def version():
    """The release tag this checkout is at, as `nightdrive version` reads it (e.g. 0.6.1-3-gabc1234), else "dev":
    serverInfo shouldn't fail for want of git."""
    repo = Path(__file__).resolve().parents[2]
    try:
        out = subprocess.run(["git", "-C", str(repo), "describe", "--tags", "--match", "v[0-9]*.[0-9]*.[0-9]*"],
                             capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return "dev"
    return out.stdout.strip().removeprefix("v") or "dev"


class Server:
    def __init__(self, tools):
        self.tools = tools
        self.client = None  # clientInfo from initialize, for the log

    # The methods, by name. A handler takes params (a dict) and returns the result, or raises RpcError.

    def initialize(self, params):
        asked = params.get("protocolVersion")
        if not isinstance(asked, str):
            raise RpcError(INVALID_PARAMS, "initialize needs protocolVersion")
        self.client = params.get("clientInfo") or {}
        who = " ".join(str(self.client[k]) for k in ("name", "version") if k in self.client) or "a client"
        log(f"initialize from {who}, protocol {asked}")
        return {
            "protocolVersion": asked if asked in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0],
            # listChanged: false until Access changes reach a running server (MCP 7, #1768)
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": NAME, "title": "Nightdrive", "version": version()},
            "instructions": INSTRUCTIONS,
        }

    def ping(self, params):
        return {}

    def tools_list(self, params):
        # One page: the tools are a few dozen at most, so no cursor
        return {"tools": self.tools.list()}

    def tools_call(self, params):
        name = params.get("name")
        arguments = params.get("arguments", {})
        if not isinstance(name, str):
            raise RpcError(INVALID_PARAMS, "tools/call needs a tool name")
        if not isinstance(arguments, dict):
            raise RpcError(INVALID_PARAMS, "arguments must be an object")
        try:
            return self.tools.call(name, arguments)
        except UnknownTool:
            raise RpcError(INVALID_PARAMS, f"Unknown tool: {name}")
        except ToolError as e:
            # A tool that ran and failed is a result Claude reads and can act on, not a protocol error
            return {"content": [{"type": "text", "text": str(e)}], "isError": True}

    METHODS = {
        "initialize": initialize,
        "ping": ping,
        "tools/list": tools_list,
        "tools/call": tools_call,
    }

    def handle(self, message):
        """One parsed message in, the response to write out (a dict), or None for a notification."""
        if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
            # A batch (a list) too: MCP left JSON-RPC batches out in 2025-06-18
            return error_response(None, INVALID_REQUEST, "Not a JSON-RPC 2.0 message")
        if "method" not in message:
            return None  # a response to a request of ours: we send none yet
        mid = message.get("id")
        notification = "id" not in message
        method = message["method"]
        params = message.get("params", {})
        if notification:
            # notifications/initialized, notifications/cancelled: nothing runs long enough yet to cancel
            return None
        if not isinstance(mid, (str, int)) or isinstance(mid, bool):
            return error_response(None, INVALID_REQUEST, "id must be a string or a number")
        if not isinstance(method, str) or not isinstance(params, dict):
            return error_response(mid, INVALID_REQUEST, "method must be a string and params an object")
        handler = self.METHODS.get(method)
        if handler is None:
            return error_response(mid, METHOD_NOT_FOUND, f"Method not found: {method}")
        try:
            return {"jsonrpc": "2.0", "id": mid, "result": handler(self, params)}
        except RpcError as e:
            return error_response(mid, e.code, e.message, e.data)
        except Exception as e:  # a bug in a handler mustn't end the session
            log(f"{method} failed: {e!r}")
            return error_response(mid, INTERNAL_ERROR, f"Internal error: {e}")

    def serve(self, stdin, stdout):
        for line in stdin:
            if not line.strip():
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError as e:
                response = error_response(None, PARSE_ERROR, f"Parse error: {e}")
            else:
                response = self.handle(message)
            if response is not None:
                # ensure_ascii off: the tools speak Finnish too, and MCP's stdio is UTF-8
                stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
                stdout.flush()


def error_response(mid, code, message, data=None):
    error = {"code": code, "message": message}
    if data is not None:
        error["data"] = data
    return {"jsonrpc": "2.0", "id": mid, "error": error}


def log(text):
    print(f"nightdrive mcp: {text}", file=sys.stderr, flush=True)


def main():
    # UTF-8 whatever the locale: a client may start us with LANG unset
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    # The seam for MCP 2 (#1763): registry.Registry(), filtered by Access, takes TestTools' place here
    server = Server(TestTools())
    try:
        server.serve(sys.stdin, sys.stdout)
    except (KeyboardInterrupt, BrokenPipeError):
        pass  # the client went away: that is how a stdio session ends


if __name__ == "__main__":
    main()
