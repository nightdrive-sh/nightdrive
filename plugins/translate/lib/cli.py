#!/usr/bin/env python3
"""translate: text from one language of your pair to the other (plugins/translate, README.md).

  translate [--from LANG] [--to LANG] [--engine NAME] [--json] [--] TEXT…   (or the text on stdin)
  translate engines [--json]              the engines: which are installed, which is in use
  translate engine use NAME               translate with NAME from now on
  translate engine install NAME           download its model, or install its package
  translate engine remove NAME            delete its model
  translate langs [A B]                   the pair, e.g. fi en: text in one is translated to the other
  translate setup                         the plugin's installer: the default engine

Without --from the language is guessed (lib/detect.py); --to alone translates into it from the pair's other one.
A word that is also a command (`engines`) goes after `--`.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import config      # noqa: E402
import detect      # noqa: E402
import engines     # noqa: E402
import setup       # noqa: E402
from config import Problem  # noqa: E402

MAX_TEXT = 20000   # characters: more than a page or two isn't what this is for


def direction(text, src, tgt, langs):
    """(from, to, guessed): what was asked for, the rest filled in from the pair."""
    first, second = langs
    other = lambda code: second if code == first else first
    if src and tgt:
        return src, tgt, False
    if tgt:
        return other(tgt), tgt, False
    if src:
        return src, other(src), False
    found = detect.detect(text, first, second)
    return (found, other(found), True) if found else (first, second, True)


def translate(args):
    opts = {"from": None, "to": None, "engine": None}
    as_json, words = False, []
    while args:
        arg = args.pop(0)
        if arg == "--":
            words += args
            break
        if arg == "--json":
            as_json = True
        elif arg in ("--from", "--to", "--engine"):
            if not args:
                raise Problem(f"{arg} needs a value")
            opts[arg[2:]] = args.pop(0)
        elif arg.startswith("--"):
            raise Problem(f"Unknown option {arg}: translate --help")
        else:
            words.append(arg)
    text = " ".join(words) if words else sys.stdin.read()
    text = text.strip()
    try:
        if not text:
            raise Problem("Nothing to translate")
        if len(text) > MAX_TEXT:
            raise Problem(f"That is over {MAX_TEXT} characters: translate it in parts")
        name, spec = config.engine(opts["engine"])
        src, tgt, guessed = direction(text, opts["from"], opts["to"], config.settings()["langs"])
        if src == tgt:
            raise Problem("The two languages are the same")
        result = engines.translate(name, spec, text, src, tgt)
    except Problem as problem:
        if as_json:      # the launcher reads the reason from here; a terminal and Claude from stderr
            print(json.dumps({"error": str(problem)}, ensure_ascii=False))
        raise
    if as_json:
        print(json.dumps({"text": text, "from": src, "to": tgt, "from_name": config.language(src),
                          "to_name": config.language(tgt), "guessed": guessed, "engine": name,
                          "engine_name": spec.get("name", name), "translation": result["translation"],
                          "alternatives": result["alternatives"]}, ensure_ascii=False))
    else:
        print(result["translation"])
        for other in result["alternatives"]:
            print("  " + other)


def engine_rows():
    current = config.settings()["engine"]
    return [{"id": name, "name": spec.get("name", name), "summary": spec.get("summary", ""),
             "size": spec.get("size", ""), "online": bool(spec.get("online")), "license": spec.get("license", ""),
             # live: quick and free enough to translate while typing; Claude waits for Enter
             "live": spec.get("live", True) is not False, "own": bool(spec.get("own")),
             "installed": setup.installed(name, spec), "current": name == current,
             "removable": spec["type"] in ("ct2", "nllb")}
            for name, spec in config.engines().items()]


def list_engines(args):
    rows = engine_rows()
    if "--json" in args:
        data = config.settings()
        print(json.dumps({"engine": data["engine"], "langs": data["langs"],
                          "lang_names": [config.language(c) for c in data["langs"]], "engines": rows},
                         ensure_ascii=False))
        return
    for row in rows:
        mark = "*" if row["current"] else " "
        state = "installed" if row["installed"] else "not installed"
        detail = ", ".join(x for x in (row["summary"], row["size"]) if x)
        print(f"{mark} {row['id']:<10} {row['name']:<18} {state:<14} {detail}")


def engine(args):
    if len(args) != 2 or args[0] not in ("use", "install", "remove"):
        raise Problem("translate engine use|install|remove NAME")
    action, name = args
    if action == "install":
        name, spec = setup.install(name)
        # The first one installed is the one to use: nothing else could translate yet
        current = config.engines().get(config.settings()["engine"])
        if current is None or not setup.installed(config.settings()["engine"], current):
            config.save(engine=name)
    elif action == "remove":
        setup.remove(name)
    else:
        name, spec = config.engine(name)
        if not setup.installed(name, spec):
            raise Problem(f"{spec.get('name', name)} isn't installed: translate engine install {name}")
        config.save(engine=name)
        print(f"Translating with {spec.get('name', name)}")


def langs(args):
    if not args:
        print(" ".join(config.settings()["langs"]))
        return
    if len(args) != 2 or args[0] == args[1] or not all(a.replace("_", "").isalnum() for a in args):
        raise Problem("translate langs A B: two different language codes, e.g. fi en")
    config.save(langs=[a for a in args])
    print(f"{config.language(args[0])} ↔ {config.language(args[1])}")


def plugin_setup(args):
    """The plugin's installer (plugin.conf): the default engine, then the mark `installed` tests."""
    current, spec = config.engine(config.settings()["engine"] if config.settings()["engine"] in config.engines()
                                  else config.DEFAULT_ENGINE)
    if not setup.installed(current, spec):
        setup.install(current)
    config.save(engine=current)
    config.STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    config.STATE_FILE.touch()
    print("Translate is ready: Launcher › Tools › Translate, or `translate kolinaa`. Other engines: translate engines")


COMMANDS = {"engines": list_engines, "engine": engine, "langs": langs, "setup": plugin_setup}


def main():
    args = sys.argv[1:]
    if args and args[0] in ("-h", "--help", "help"):
        print(__doc__.strip())
        return 0
    try:
        if args and args[0] in COMMANDS:
            COMMANDS[args[0]](args[1:])
        else:
            translate(args)
    except Problem as problem:
        print(f"translate: {problem}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
