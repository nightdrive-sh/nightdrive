#!/usr/bin/python3 -I
"""Files' helper: the window (Ops.qml, Places.qml, Preview.qml) runs these and reads the JSON they print, one object a
line. A copy, move, compress or extract prints {"progress": bytes, "total": bytes, "name": …} as it goes; the last
line is the result.
A change's result carries "undo": the command that takes it back, as the window runs it for Undo and ⌘Z. What can't be
done exits 1 with the reason on stderr, in words for the toast.

  copy --into FOLDER PATH…     copies, " (2)" when a name is taken           undo: trash the copies
  move --into FOLDER PATH…     moves (a rename on the same disk)             undo: move-back
  rename PATH NAME             a new name in the same folder                 undo: move-back
  new FOLDER NAME [--dir]      an empty file, or a folder                    undo: trash it
  compress --into FOLDER --name NAME --format zip|tar.gz|tar.xz|tar PATH…   an archive   undo: trash it
  extract ARCHIVE [--into FOLDER]   unpacked beside it (pack.py, unpack.py)          undo: trash what it made
  archive-list ARCHIVE         its members, without unpacking (members.py; progress as it reads a big tar)
  member-peek ARCHIVE NAME --slot SLOT [--long]   peek of one member, taken out into the window's slot
  member-clean --slot SLOT     the slot's members gone
  extract-members ARCHIVE --into FOLDER NAME…   only those members (a folder with all in it)   undo: trash them
  trash PATH…                  to the trash                                  undo: restore
  move-back NEW OLD …          each NEW back to OLD
  restore ID…                  back from the trash (ID: its info file, as trash and trash-list give it)
  trash-list | trash-empty | delete ID…
  peek PATH [--long]           what the preview shows (--long: more of a text, for the big preview)
  places                       the sidebar's rows
  bookmark PATH | unbookmark PATH
  unpin PATH                   out of the sidebar's first group (pinned.py)
  place-move PATH --to places|bookmarks [--before PATH]   a folder to a group, before another of it or at its end
  mount DEVICE | unmount PATH
"""
import argparse, json, os, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))   # -I leaves the script's folder out
import fsops, members, pack, peek, pinned, places, trash, unpack         # noqa: E402
from fsops import Refused                                  # noqa: E402


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def progress(done, total, name):
    emit({"progress": done, "total": total, "name": name})


def with_undo(result):
    """The undo command for a change's result, which the window keeps as it is"""
    if result.get("made"):
        result["undo"] = ["trash", "--"] + result["made"]
    elif result.get("moved"):
        result["undo"] = ["move-back", "--"] + [p for pair in result["moved"] for p in pair]
    elif result.get("trashed"):
        result["undo"] = ["restore", "--"] + result["trashed"]
    return result


def pairs(flat):
    if len(flat) % 2:
        raise Refused("move-back takes NEW OLD pairs.")
    return [flat[i:i + 2] for i in range(0, len(flat), 2)]


def run(a):
    v = a.verb
    if v == "copy":
        fsops.watch_stop()
        return with_undo(fsops.copy(a.paths, a.into, progress))
    if v == "move":
        fsops.watch_stop()
        return with_undo(fsops.move(a.paths, a.into, progress))
    if v == "compress":
        fsops.watch_stop()
        return with_undo(pack.compress(a.paths, a.into, a.name, a.format, progress))
    if v == "extract":
        fsops.watch_stop()
        return with_undo(unpack.extract(a.archive, a.into, progress))
    if v == "extract-members":
        fsops.watch_stop()
        return with_undo(members.extract(a.archive, a.names, a.into, progress))
    if v == "archive-list":
        fsops.watch_stop()
        try:
            return members.listing(a.archive, progress)
        except fsops.Stopped:
            return {"stopped": True}
    if v == "member-peek":
        return members.peek_member(a.archive, a.name, a.slot, a.long)
    if v == "member-clean":
        return members.clean(a.slot)
    if v == "rename":
        return with_undo(fsops.rename(a.path, a.name))
    if v == "new":
        return with_undo(fsops.new(a.folder, a.name, a.dir))
    if v == "trash":
        return with_undo(trash.trash(a.paths))
    if v == "move-back":
        return fsops.move_back(pairs(a.paths))
    if v == "restore":
        return trash.restore(a.ids)
    if v == "trash-list":
        return {"items": trash.listing()}
    if v == "trash-empty":
        return trash.empty()
    if v == "delete":
        return trash.delete(a.ids)
    if v == "peek":
        return peek.peek(a.path, a.long)
    if v == "places":
        return {"pinned": pinned.rows(), **places.all_places()}
    if v == "unpin":
        return pinned.remove(a.path)
    if v == "place-move":
        return pinned.move(a.path, a.to, a.before)
    if v in ("bookmark", "unbookmark"):
        return places.bookmark(a.path, v == "bookmark")
    if v == "mount":
        return places.mount(a.device)
    if v == "unmount":
        return places.unmount(a.path)
    raise Refused(f"No command {v}.")


def parser():
    p = argparse.ArgumentParser(prog="cli.py", description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="verb", required=True)
    for verb in ("copy", "move"):
        s = sub.add_parser(verb)
        s.add_argument("--into", required=True)
        s.add_argument("paths", nargs="+")
    s = sub.add_parser("compress"); s.add_argument("--into", required=True); s.add_argument("--name", required=True)
    s.add_argument("--format", choices=tuple(pack.FORMATS), default="zip"); s.add_argument("paths", nargs="+")
    s = sub.add_parser("extract"); s.add_argument("archive"); s.add_argument("--into", default="")
    s = sub.add_parser("extract-members"); s.add_argument("archive"); s.add_argument("--into", required=True)
    s.add_argument("names", nargs="+")
    sub.add_parser("archive-list").add_argument("archive")
    s = sub.add_parser("member-peek"); s.add_argument("archive"); s.add_argument("name"); s.add_argument("--slot", required=True)
    s.add_argument("--long", action="store_true")
    sub.add_parser("member-clean").add_argument("--slot", required=True)
    s = sub.add_parser("rename"); s.add_argument("path"); s.add_argument("name")
    s = sub.add_parser("new"); s.add_argument("folder"); s.add_argument("name"); s.add_argument("--dir", action="store_true")
    for verb in ("trash", "move-back"):
        sub.add_parser(verb).add_argument("paths", nargs="+")
    for verb in ("restore", "delete"):
        sub.add_parser(verb).add_argument("ids", nargs="+")
    for verb in ("trash-list", "trash-empty", "places"):
        sub.add_parser(verb)
    for verb in ("bookmark", "unbookmark", "unmount"):
        sub.add_parser(verb).add_argument("path")
    sub.add_parser("unpin").add_argument("path")
    s = sub.add_parser("place-move"); s.add_argument("path"); s.add_argument("--to", choices=("places", "bookmarks"), required=True)
    s.add_argument("--before", default="")
    s = sub.add_parser("peek"); s.add_argument("path"); s.add_argument("--long", action="store_true")
    sub.add_parser("mount").add_argument("device")
    return p


def main(argv=None):
    a = parser().parse_args(argv)
    try:
        emit(run(a))
    except Refused as e:
        print(str(e), file=sys.stderr)
        return 1
    except OSError as e:
        name = os.path.basename(e.filename) if e.filename else ""
        print(f"{name}: {e.strerror}" if name else str(e.strerror or e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
