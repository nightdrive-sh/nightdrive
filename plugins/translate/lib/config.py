"""Translate's paths, settings and engine list.

The engines are data: lib/engines.json holds the ones Nightdrive knows, and every *.json in the user's engines.d adds
or replaces one, so a new model or service needs no code (README › Your own engine). Settings are one small JSON file:
the engine in use and the language pair.
"""
import json
import os
from pathlib import Path

HOME = Path(os.environ.get("HOME", str(Path.home())))
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "nightdrive" / "translate"
DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "nightdrive" / "translate"
STATE_FILE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "nightdrive" / "translate"
SETTINGS = CONFIG_DIR / "settings.json"
USER_ENGINES = CONFIG_DIR / "engines.d"
VENV = DATA_DIR / "venv"
MODELS = DATA_DIR / "models"
BUILTIN = Path(__file__).with_name("engines.json")

DEFAULT_ENGINE = "opus-mt"
DEFAULT_LANGS = ["fi", "en"]          # the pair: text in one is translated to the other
TYPES = ("ct2", "nllb", "trans", "claude", "command")
NAMES = {"fi": "Finnish", "en": "English", "sv": "Swedish", "de": "German", "fr": "French", "es": "Spanish",
         "it": "Italian", "et": "Estonian", "no": "Norwegian", "da": "Danish", "nl": "Dutch", "pl": "Polish",
         "ru": "Russian", "uk": "Ukrainian", "ja": "Japanese", "zh": "Chinese", "pt": "Portuguese"}


class Problem(Exception):
    """Something the user can act on: its text is the whole message they read."""


def language(code):
    return NAMES.get(code, code)


def settings():
    try:
        data = json.loads(SETTINGS.read_text())
    except (OSError, ValueError):
        data = {}
    langs = data.get("langs")
    if not (isinstance(langs, list) and len(langs) == 2 and all(isinstance(c, str) and c for c in langs)):
        langs = list(DEFAULT_LANGS)
    engine = data.get("engine")
    return {"engine": engine if isinstance(engine, str) and engine else DEFAULT_ENGINE, "langs": langs}


def save(**changes):
    data = settings()
    data.update(changes)
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = SETTINGS.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    tmp.replace(SETTINGS)          # never a half-written file for the launcher to read
    return data


def _valid(spec):
    return isinstance(spec, dict) and spec.get("type") in TYPES


def engines():
    """id → spec, the user's own after (and over) the built-in ones. A file that doesn't parse is left out."""
    out = {}
    try:
        out.update({k: v for k, v in json.loads(BUILTIN.read_text()).items() if _valid(v)})
    except (OSError, ValueError):
        pass
    for path in sorted(USER_ENGINES.glob("*.json")) if USER_ENGINES.is_dir() else []:
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        # One engine in a file named for it, or several keyed by id
        found = {path.stem: data} if _valid(data) else data if isinstance(data, dict) else {}
        for key, spec in found.items():
            if _valid(spec):
                out[key] = dict(spec, own=True)
    return out


def engine(name=None):
    name = name or settings()["engine"]
    spec = engines().get(name)
    if spec is None:
        raise Problem(f"No engine named {name}: `translate engines` lists them")
    return name, spec


def model_dir(name):
    return MODELS / name
