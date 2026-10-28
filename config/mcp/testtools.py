"""The tool provider server.py runs with until the registry exists (MCP 2, #1763): one test tool.

A tool provider is what server.py asks about tools, and all it asks:
    list()                  the tools as MCP's tools/list shows them: name, title, description, inputSchema
    call(name, arguments)   run one, return MCP's tools/call result ({"content": [...]}); raise UnknownTool for a
                            name it doesn't have, ToolError for a tool that ran and failed (Claude sees the message)
registry.py will be the real one, built from plugins/<id>/mcp.json and config/mcp/tools/*.json; this file goes then.
"""


class UnknownTool(Exception):
    """No tool by that name (or not one the user's Access lets Claude see)."""


class ToolError(Exception):
    """The tool ran and failed; the message is for Claude to read."""


ECHO = {
    "name": "nightdrive_echo",
    "title": "Echo",
    "description": "Test tool of Nightdrive's MCP server: returns the text it is given. Use it only to check that "
                   "the server answers.",
    "inputSchema": {
        "type": "object",
        "properties": {"text": {"type": "string", "description": "What to send back"}},
        "required": ["text"],
        "additionalProperties": False,
    },
    "annotations": {"readOnlyHint": True, "openWorldHint": False},
}


class TestTools:
    def list(self):
        return [ECHO]

    def call(self, name, arguments):
        if name != ECHO["name"]:
            raise UnknownTool(name)
        text = arguments.get("text")
        if not isinstance(text, str):
            raise ToolError("nightdrive_echo needs text (a string)")
        return {"content": [{"type": "text", "text": text}]}
