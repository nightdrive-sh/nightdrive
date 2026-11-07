#!/usr/bin/python3 -I
"""results_add (#2243, #2225): a result card in an Ask Claude conversation. Claude adds one for each thing it found
(a sound, a picture, a page, a file), and the panel (#2245) shows them under its answer: a sound to play, a picture to
look at, a page with its address, a file to save. The card only shows: nothing is opened, sent or saved from here.

A card is a record in the conversation's results.json, beside its files folder (~/.local/state/nightdrive/ask/<id>/,
NIGHTDRIVE_ASK_FILES, as web_download's): without one (a terminal session) there is nothing to show cards in.

    {"version": 1, "cards": [{"n": 1, "type": "sound", "title": "Engine sputter", "url": "https://…",
                              "file": "engine.ogg", "mime": "audio/ogg", "size": 52113,
                              "licence": "CC0", "author": "…", "note": "…", "added": "2026-11-07T12:00:00+02:00"}]}

- type: sound, image and file need a `file` this conversation downloaded (web_download's id), whose type is read
  again from its first bytes (sniff.py), never taken from Claude: a sound must be audio, a picture a picture. A page
  has none: it is its address.
- url: where it was found, http(s) only, as the card's Open goes there; for a file, the page about it (its licence).
- licence: free text as the source says it (CC0, CC BY 4.0, Pixabay Content License…), "unknown" when not given, so
  the panel never shows a file as free to use without saying whose word that is.
- Text is cleaned of control and bidi characters (a page's title could reorder what the card says) and cut to
  LIMITS; a conversation has at most CARDS_MAX cards, one per file or page.

    results.py add        the card's arguments as JSON on stdin; prints {card, cards}
"""
import fcntl, json, os, re, sys, tempfile
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "web"))   # -I leaves the script's folder out
import download  # noqa: E402
import sniff     # noqa: E402

NAME = "results.json"
VERSION = 1
CARDS_MAX = 50
TYPES = ("sound", "image", "page", "file")
LIMITS = {"title": 120, "url": 2048, "licence": 80, "author": 120, "note": 400}
UNKNOWN = "unknown"
# What each type's file must be, by its sniffed MIME type's start ("" is any kept type)
FILE_KIND = {"sound": "audio/", "image": "image/", "file": ""}
# C0/C1 controls, and the bidi and zero-width marks that would let a title change how the card reads
UNSAFE = re.compile(r"[\x00-\x1f\x7f-\x9f​-‏‪-‮⁦-⁩﻿]")


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def clean(value, key):
    """A text argument as the card keeps it: a string, one line, no unsafe characters, at most its limit."""
    if value is None:
        return None
    if not isinstance(value, str):
        die(f"{key} must be text.")
    text = re.sub(r"\s+", " ", UNSAFE.sub(" ", value)).strip()
    limit = LIMITS[key]
    return text if len(text) <= limit else text[:limit - 1].rstrip() + "…"


def check_url(url):
    if not url or not re.match(r"^https?://[^\s/?#]+", url, re.I):
        die("url must be the http:// or https:// address of the page it was found on.")
    if len(url) > LIMITS["url"]:
        die(f"url is longer than {LIMITS['url']} characters.")
    return url


def downloaded(folder, file_id, kind):
    """(mime, size) of a file this conversation downloaded, which must be of kind; else dies. The id is a plain name
    in the folder, no link, not a half-downloaded .part."""
    if not isinstance(file_id, str) or not re.fullmatch(r"[^/\x00]{1,255}", file_id) or file_id.startswith("."):
        die(f"{file_id!r} isn't a downloaded file's id: give the id its download returned.")
    path = folder / file_id
    if path.is_symlink() or not path.is_file():
        die(f"{file_id} isn't one of this conversation's downloads: download it first.")
    with open(path, "rb") as f:
        found = sniff.kind(f.read(sniff.HEAD))
    if not found:
        die(f"{file_id} isn't a file a card can show.")
    mime = found[0]
    if not mime.startswith(kind):
        want = {"audio/": "audio", "image/": "a picture"}[kind]
        die(f"{file_id} is {mime}, not {want}: give it the type file, or the right file.")
    return mime, path.stat().st_size


def card(args, folder):
    """The card's record from the tool's arguments, checked; dies on what can't be shown."""
    if not isinstance(args, dict):
        die("The arguments must be a JSON object.")
    unknown = set(args) - {"type", "title", "url", "file", "licence", "author", "note"}
    if unknown:
        die(f"Unknown argument: {', '.join(sorted(unknown))}.")
    kind = args.get("type")
    if kind not in TYPES:
        die(f"type must be one of {', '.join(TYPES)}.")
    title = clean(args.get("title"), "title")
    if not title:
        die("A card needs a title.")
    rec = {"type": kind, "title": title, "url": check_url(args.get("url"))}
    file_id = args.get("file")
    if kind == "page":
        if file_id:
            die("A page card has no file: its url is the page. For a downloaded file, use type file, sound or image.")
    else:
        if not file_id:
            die(f"A {kind} card needs the id of the file its download returned.")
        mime, size = downloaded(folder, file_id, FILE_KIND[kind])
        rec.update(file=file_id, mime=mime, size=size)
    rec["licence"] = clean(args.get("licence"), "licence") or UNKNOWN
    for key in ("author", "note"):
        if value := clean(args.get(key), key):
            rec[key] = value
    rec["added"] = datetime.now().astimezone().isoformat(timespec="seconds")
    return rec


def load(path):
    """The conversation's cards; a missing or broken file is none (the panel shows what it can read the same way)."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        cards = data.get("cards") if isinstance(data, dict) else None
        return [c for c in cards if isinstance(c, dict)] if isinstance(cards, list) else []
    except (OSError, ValueError):
        return []


def save(path, cards):
    """Writes the cards whole and swaps the file in, so the panel never reads half of it."""
    fd, tmp = tempfile.mkstemp(prefix=".results-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"version": VERSION, "cards": cards}, f, ensure_ascii=False, indent=1)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def cmd_add(raw):
    try:
        args = json.loads(raw)
    except ValueError:
        die("The arguments aren't JSON.")
    if not os.environ.get(download.ENV):
        die("results_add works only in Ask Claude (the launcher's ⌘⌥Enter), whose panel shows the cards: here, "
            "say what you found in your answer.")
    folder = download.folder_from_env()   # the files folder, checked to be a conversation's own
    rec = card(args, folder)
    path = folder.parent / NAME
    # Claude may add cards side by side: one at a time, so none is lost between a read and a write
    with open(folder.parent / ".results.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        cards = load(path)
        if len(cards) >= CARDS_MAX:
            die(f"This conversation has {CARDS_MAX} cards already: no more are shown.")
        same = "file" if "file" in rec else "url"
        if any(c.get(same) == rec[same] and ("file" in c) == ("file" in rec) for c in cards):
            die(f"There is a card for this {'file' if same == 'file' else 'page'} already.")
        rec = {"n": max((c.get("n", 0) for c in cards if isinstance(c.get("n"), int)), default=0) + 1, **rec}
        cards.append(rec)
        save(path, cards)
    print(json.dumps({"card": rec["n"], "cards": len(cards)}))


def main(argv):
    if argv == ["add"]:
        cmd_add(sys.stdin.read())
    else:
        die(__doc__.rsplit("\n\n", 1)[-1], 2)


if __name__ == "__main__":
    main(sys.argv[1:])
