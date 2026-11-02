#!/usr/bin/env python3
"""The tools of Nightdrive's MCP server: the core's (config/mcp/tools/*.json) and those of the plugins that are
installed and on (plugins/<id>/mcp.json), filtered by the user's Access (access.py). The format is plugins/README.md ›
Tools for Claude: mcp.json.

This is server.py's tool provider: list() and call(name, arguments). The files are read again on each call, so a
plugin turned on or off, or an Access change, applies without restarting the server. A file or tool that breaks the
format is left out with a line in the log; `python3 registry.py` shows what is listed, what is hidden and why.

Each tool belongs to one right of its area (Tool.right: read, modify or delete; #1831), and Access gives that right
Allow, Ask or No. No hides the tool; Ask, and an act tool always, runs it only once the user allows the call on the card.
A change Access allows asks too once its area has had many in a minute, and a call the user just refused isn't shown
to them again at once (pace.py, #1882).
So does a call whose `asks_if` command says yes though Access allows the tool (asks): one that reaches further than
its right says, sound to a speaker on the network or an event into a calendar others see (#1887). One that prints
`first KEY` asks only until the user allows a call for KEY once (an event into a calendar Claude hasn't added to yet,
#1929): allowed.py remembers it, and a refusal or a timeout remembers nothing.
An area's own choices (access.Access.options, #1830) go to the tool too (Tool.keep): what one that is off takes away
isn't in its schema, and its command gets them all to keep to, and another area's too when its mcp.json names that
area in `options_from` (the latest notifications keep to Mail's blocked list: a notification would tell what it hides).
What a read tool gives passes through mask.py on its way to Claude (#1789): the fields its mcp.json names in `mask`,
unless its area's choice `secrets` is on.

The steps of phase 3 slot in as modules beside this one, found by name:
    confirm.ask(tool, arguments) -> bool     the card that allows a call (MCP 5, #1766). Without it, what asks is
                                             refused: nothing runs unasked that the user wanted to be asked about
    undo.before(tool, arguments) -> dict     the state a change tool's call will change, read first (MCP 6, #1767)
    undo.offer(tool, arguments, result, state)  the log entry and the notification that undo the call
"""

import importlib
import json
import re
import sys
from contextlib import contextmanager
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import access  # noqa: E402  (after the path above)
import allowed  # noqa: E402
import mask  # noqa: E402
import pace  # noqa: E402
import run  # noqa: E402
from run import ToolError  # noqa: E402,F401  (server.py takes both errors from here)

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CORE = HERE / "tools"
# id<TAB>folder of each plugin that is installed and on, written by `nightdrive plugins installed` (plugin-parts)
ACTIVE = Path.home() / ".cache/nightdrive/plugins.d/active"

NAME = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
CLASSES = ("read", "change", "act")
HINTS = {  # MCP's annotations, from the class: what Claude Code shows and decides by
    "read": {"readOnlyHint": True, "destructiveHint": False},
    "change": {"readOnlyHint": False, "destructiveHint": False},
    "act": {"readOnlyHint": False, "destructiveHint": True},
}


class UnknownTool(Exception):
    """No tool by that name, or not one the user's Access lets Claude see."""


class Tool:
    def __init__(self, spec, folder, source):
        self.spec = spec          # the definition as its file has it
        self.name = spec["name"]
        self.cls = spec["class"]
        self.area = spec["area"]
        # The right of its area it needs: a read is Read, what removes something Delete, every other change Modify
        self.right = "delete" if spec.get("deletes") else "read" if self.cls == "read" else "modify"
        self.dir = folder         # where its command runs: the plugin's folder, config/mcp for the core's
        self.source = source      # the file, for the log
        self.options = {}         # its area's own choices as Access has them now: {id: on}
        self.options_from = {}    # the choices of the other areas it names in options_from: {area: {id: on}}

    def keep(self, options):
        """Its area's own choices: its command gets them (run.environment), and the values that one that is off takes
        away (its mcp.json `options`) go from its schema, so Claude isn't offered them and run.check refuses them.
        The spec is this load's own copy, read from its file a moment ago."""
        self.options = options
        for option, props in self.spec.get("options", {}).items():
            if options.get(option):
                continue
            for prop, values in props.items():
                schema = self.spec["inputSchema"]["properties"][prop]
                schema["enum"] = [v for v in schema["enum"] if v not in values]

    def listing(self):
        """The tool as tools/list shows it."""
        out = {"name": self.name}
        if self.spec.get("title"):
            out["title"] = self.spec["title"]
        out["description"] = self.spec["description"]
        out["inputSchema"] = run.limited(self.spec["inputSchema"])
        out["annotations"] = {**self.spec.get("annotations", {}), **HINTS[self.cls]}
        return out


def is_template(value, nested=False):
    """A command template: a non-empty list of strings, and lists of strings one level down (the optional groups)."""
    return isinstance(value, list) and bool(value) and all(
        isinstance(v, str) or (not nested and is_template(v, nested=True)) for v in value)


LIMITS = ("minLength", "maxLength", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "minItems", "maxItems")


def limits_problem(prop):
    """What is wrong with the limits run.check keeps an argument to: numbers, and a pattern Python can compile."""
    if not isinstance(prop, dict):
        return None
    for key in LIMITS:
        if key in prop and (isinstance(prop[key], bool) or not isinstance(prop[key], (int, float))):
            return f"{key} must be a number"
    if "pattern" in prop:
        try:
            re.compile(prop["pattern"])
        except (re.error, TypeError):
            return "pattern must be a regular expression"
    return None


def problem(spec, plugin, external=False):
    """What is wrong with one tool's definition, in a few words; None when nothing is. external: a plugin from outside
    this repository, whose tools stay in its own area."""
    if not isinstance(spec, dict):
        return "a tool that isn't an object"
    name = spec.get("name")
    if not isinstance(name, str) or not NAME.match(name):
        return f"name {name!r}: a-z, 0-9 and _, at most 64, starting with a letter"
    prefix = plugin.replace("-", "_") + "_" if plugin else ""
    if not name.startswith(prefix):
        return f"{name}: a plugin's tool names start with its id ({prefix}…)"
    if not isinstance(spec.get("description"), str) or not spec["description"].strip():
        return f"{name}: no description"
    schema = spec.get("inputSchema")
    if not isinstance(schema, dict) or schema.get("type") != "object" or not isinstance(schema.get("properties", {}), dict):
        return f"{name}: inputSchema must be an object schema"
    for prop, sub in schema.get("properties", {}).items():
        wrong = limits_problem(sub) or limits_problem(sub.get("items") if isinstance(sub, dict) else None)
        if wrong:
            return f"{name}: {prop}: {wrong}"
    if not is_template(spec.get("command")):
        return f"{name}: command must be a list of strings (and lists of them)"
    if spec.get("class") not in CLASSES:
        return f"{name}: class must be read, change or act"
    area = spec.get("area")
    if area not in access.AREAS and area != plugin:
        return f"{name}: unknown area {area!r} (Access's rows, or the plugin's id)"
    # Not Nightdrive's own row (read even on Strict) nor Mail's: Access would show its tools there, under rules the
    # user set for another's (#1865). Its own id only, and not one that is a row of Access already
    if external and (area != plugin or area in access.AREAS):
        return f"{name}: a plugin from outside Nightdrive keeps its tools in its own area ({plugin!r})"
    options = spec.get("options", {})
    if not isinstance(options, dict):
        return f"{name}: options must be an object"
    known = [o["id"] for o in access.areas.options(area) if not o.get("list")]   # a list takes no values away
    for option, props in options.items():
        if option not in known:
            return f"{name}: its area has no on-or-off option {option!r}" + (f" ({', '.join(known)})" if known else "")
        if not isinstance(props, dict) or not all(
                isinstance(v, list) and isinstance(schema.get("properties", {}).get(p), dict)
                and isinstance(schema["properties"][p].get("enum"), list) for p, v in props.items()):
            return f"{name}: options.{option} must give, per argument with an enum, the values it takes away"
    others = spec.get("options_from", [])
    if not isinstance(others, list) or not all(isinstance(a, str) and access.areas.options(a) for a in others):
        return f"{name}: options_from must list areas that have choices of their own"
    if "card" in spec and not is_template(spec["card"]):
        return f"{name}: card must be a list of strings (and lists of them)"
    unknown = run.placeholders(spec.get("card") or []) - set(schema.get("properties", {}))
    if unknown:
        return f"{name}: {', '.join(sorted(unknown))} in its card isn't in inputSchema"
    if "asks_if" in spec and (spec["class"] != "change" or not is_template(spec["asks_if"])):
        return f"{name}: asks_if is a change tool's, a list of strings (and lists of them); an act tool always asks"
    unknown = run.placeholders(spec.get("asks_if") or []) - set(schema.get("properties", {}))
    if unknown:
        return f"{name}: {', '.join(sorted(unknown))} in its asks_if isn't in inputSchema"
    if not isinstance(spec.get("deletes", False), bool):
        return f"{name}: deletes must be true or false"
    if spec.get("deletes") and spec["class"] == "read":
        return f"{name}: a read tool can't delete"
    stdin = spec.get("stdin")
    if stdin is not None and not isinstance(stdin, str):
        return f"{name}: stdin must be \"json\" or a string"
    unknown = run.placeholders(spec["command"]) | (run.placeholders(stdin) if stdin and stdin != "json" else set())
    unknown -= set(schema.get("properties", {}))
    if unknown:
        return f"{name}: {', '.join(sorted(unknown))} in its command isn't in inputSchema"
    if spec["class"] == "change" and not is_template(spec.get("undo")):
        return f"{name}: a change tool needs undo (the command that undoes it); one that can't be undone is act"
    if not isinstance(spec.get("undo_asks", False), bool):
        return f"{name}: undo_asks must be true or false"
    if "before" in spec and not is_template(spec["before"]):
        return f"{name}: before must be a list of strings (and lists of them)"
    unknown = run.placeholders(spec.get("before") or []) - set(schema.get("properties", {}))
    if unknown:
        return f"{name}: {', '.join(sorted(unknown))} in its before isn't in inputSchema"
    if not isinstance(spec.get("notice", ""), str):
        return f"{name}: notice must be a string"
    paths = spec.get("mask", [])
    if not isinstance(paths, list) or not all(isinstance(p, str) and p.strip(".") for p in paths):
        return f"{name}: mask must be a list of fields of its output (\"messages.text\")"
    if not isinstance(spec.get("image", ""), str):
        return f"{name}: image must be the name of a field in its output"
    timeout = spec.get("timeout", run.TIMEOUT)
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not 0 < timeout <= run.TIMEOUT_MAX:
        return f"{name}: timeout must be 1–{run.TIMEOUT_MAX} seconds"
    if not isinstance(spec.get("annotations", {}), dict):
        return f"{name}: annotations must be an object"
    return None


def read_file(path, folder, plugin):
    """One file's tools, and the problems of those it left out."""
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError) as e:
        return [], [f"{path}: can't be read ({e})"]
    if not isinstance(data, dict) or not isinstance(data.get("tools"), list):
        return [], [f"{path}: must be an object with a list \"tools\""]
    tools, problems = [], []
    for spec in data["tools"]:
        why = problem(spec, plugin, external=plugin is not None and Path(folder).resolve().parent != REPO / "plugins")
        if why:
            problems.append(f"{path}: {why}: left out")
        else:
            tools.append(Tool(spec, folder, path))
    return tools, problems


def plugin_folders(active=ACTIVE):
    """(id, folder) of each plugin that is installed and on. This checkout's folder when it has the plugin, so a
    worktree's server reads the worktree's mcp.json; else the one listed (an external plugin's)."""
    try:
        lines = Path(active).read_text().splitlines()
    except OSError:
        return []  # plugins installed hasn't run: no plugins yet
    out = []
    for line in lines:
        pid, _, listed = line.partition("\t")
        if pid:
            own = REPO / "plugins" / pid
            out.append((pid, own if own.is_dir() else Path(listed)))
    return out


def all_tools(core=CORE, active=ACTIVE):
    """All the tools by name, the core's first (a plugin can't take a core tool's name), and the problems. Also
    claude_rules.py's: which commands Access keeps back."""
    sources = [(p, HERE, None) for p in sorted(Path(core).glob("*.json"))]
    sources += [(d / "mcp.json", d, pid) for pid, d in plugin_folders(active) if (d / "mcp.json").is_file()]
    tools, problems = {}, []
    for path, folder, plugin in sources:
        found, wrong = read_file(path, folder, plugin)
        problems += wrong
        for tool in found:
            if tool.name in tools:
                problems.append(f"{path}: {tool.name} is {tools[tool.name].source}'s already: left out")
            else:
                tools[tool.name] = tool
    return tools, problems


def optional(module):
    """A phase 3 module (confirm, undo) if it is there yet; an error inside one isn't hidden."""
    try:
        return importlib.import_module(module)
    except ModuleNotFoundError as e:
        if e.name != module:
            raise
        return None


def asks(tool, arguments):
    """Whether a call asks on the card though Access allows its tool, by its asks_if command: (ask, key). yes asks,
    no doesn't; `first KEY` asks until the user has allowed this tool for KEY once, and key is what to remember when
    they allow this call (None otherwise). One that fails, or says anything else, stops the call before anything runs,
    with its message."""
    out, err, status = run.execute(tool, run.expand(tool.spec["asks_if"], arguments), None, run.timeout_of(tool))
    if status != 0:
        why = (err.strip() or out.strip() or f"exit status {status}")[-run.MESSAGE_MAX:]
        raise ToolError(f"{tool.name} wasn't run: {why}")
    said = out.strip()
    if said in ("yes", "no"):
        return said == "yes", None
    word, _, key = said.partition(" ")
    if word != "first" or not allowed.KEY.fullmatch(key):
        raise ToolError(f"{tool.name} wasn't run: its asks_if command didn't say yes, no or first KEY.")
    if allowed.has(tool.name, key):
        return False, None
    return True, key


@contextmanager
def first_time(tool, key):
    """The card says that allowing this call allows the next ones for key too (the user must know what Allow does);
    the tool's own note is back after."""
    if key is None:
        yield
        return
    note = tool.spec.get("card_note")
    said = f"Once you allow it, Claude does this for {key} without asking from now on."
    tool.spec["card_note"] = f"{note} {said}" if note else said
    try:
        yield
    finally:
        if note is None:
            tool.spec.pop("card_note", None)
        else:
            tool.spec["card_note"] = note


def allowed_once(tool, key):
    """The user allowed a first-time call: the next ones for key run without the card. A file that can't be written
    only means the card again next time, so the call goes on."""
    if key is not None:
        try:
            allowed.remember(tool.name, key)
        except (OSError, ValueError) as e:
            print(f"nightdrive mcp: {tool.name}: couldn't remember {key!r}: {e}", file=sys.stderr, flush=True)


class Registry:
    def __init__(self, core=CORE, active=ACTIVE, access_file=access.FILE, log=None):
        self.core, self.active, self.access_file = Path(core), Path(active), access_file
        self.log = log or (lambda text: print(f"nightdrive mcp: {text}", file=sys.stderr, flush=True))
        self.logged = set()   # problems already in the log: it's read on every call
        self.confirm = optional("confirm")
        self.undo = optional("undo")
        self.pace = pace.Pace()   # how much Claude changed unasked, and what the user refused on the card (#1882)
        self.rules = None     # the Access that visible() last read: call() decides by the same one it listed by

    def load(self):
        return all_tools(self.core, self.active)

    def visible(self):
        """The tools the user's Access lets Claude see, by name."""
        tools, problems = self.load()
        rules = access.load(self.access_file)
        for text in problems + ([rules.problem] if rules.problem else []):
            if text not in self.logged:
                self.logged.add(text)
                self.log(text)
        self.rules = rules
        shown = {n: t for n, t in tools.items() if rules.decide(t.cls, t.area, t.right) != "no"}
        for t in shown.values():
            t.keep(rules.options(t.area))
            t.options_from = {a: rules.options(a) for a in t.spec.get("options_from", [])}
        return shown

    def list(self):
        return [t.listing() for t in self.visible().values()]

    def call(self, name, arguments):
        tool = self.visible().get(name)
        if tool is None:
            raise UnknownTool(name)
        run.check(tool, arguments)
        tool.said = None   # what a card said is this call's alone (confirm.facts sets it)
        decision, first = self.rules.decide(tool.cls, tool.area, tool.right), None
        if decision == "allow" and tool.spec.get("asks_if"):
            ask, first = asks(tool, arguments)
            decision = "ask" if ask else decision
        paced = self.pace.due(tool, decision)
        if decision == "ask" or paced:
            if self.confirm is None:
                raise ToolError(f"{name} wasn't run: the user's Access asks before it, and this version doesn't "
                                "have Nightdrive's confirmation card.")
            self.pace.check(tool, arguments)
            with self.pace.noted(tool, paced), first_time(tool, first):
                ok = self.confirm.ask(tool, arguments)
            if not ok:
                self.pace.refused(tool, arguments)
                raise ToolError(f"The user didn't allow {name} on screen, so it wasn't run. Don't try it another way.")
            allowed_once(tool, first)
        self.pace.ran(tool)
        undoable = tool.cls == "change" and self.undo is not None
        state = self.undo.before(tool, arguments) if undoable else None  # ToolError: nothing is changed
        answer = run.run(tool, arguments)
        if tool.spec.get("mask") and not tool.options.get("secrets"):
            answer = mask.answer(answer, tool.spec["mask"])
        if undoable:
            try:
                self.undo.offer(tool, arguments, answer, state)
            except Exception as e:  # the change is made: a notice that fails mustn't turn it into an error
                self.log(f"{name}: undo notice failed: {e!r}")
        return answer


def main():
    """What the server would give now: `--json` the tools/list result, else a line per tool and the problems."""
    reg = Registry()
    if "--json" in sys.argv[1:]:
        json.dump({"tools": reg.list()}, sys.stdout, ensure_ascii=False, indent=2)
        print()
        return
    reg.log = lambda text: print(f"left out: {text}")
    shown = reg.visible()
    tools, _ = reg.load()
    rules = access.load(reg.access_file)
    for name, tool in tools.items():
        decision = rules.decide(tool.cls, tool.area, tool.right)
        state = {"allow": "listed", "ask": "listed, asks on screen"}.get(decision, "hidden (Access: No)")
        source = Path(tool.source)
        source = source.relative_to(REPO) if REPO in source.parents else source
        print(f"{name:28} {tool.cls:7} {tool.area:15} {tool.right:7} {state:24} {source}")
    if not tools:
        print("No tools.")


if __name__ == "__main__":
    main()
