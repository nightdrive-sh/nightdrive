#!/usr/bin/env python3
"""nightdrive inbox: Nightdrive Inbox, messages for you to look at when you have time (#3132, docs/inbox.md).

A notification says something needs you now; a message here waits until you read or archive it: a "done, have a look"
with screenshots, a summary, a checklist, a build to try. Claude's sessions leave them with the inbox_post tool
(config/mcp/tools/inbox.json, which runs `post --stdin-json`), apps with `post --app NAME`. The store is store.py,
buttons actions.py, attachments attach.py, the sender sender.py.

  post TITLE [--body TEXT|-] [--attach PATH]… [--action KIND LABEL VALUE]… [--task N] [--app NAME] [--dir DIR]
  update ID [--title T] [--body TEXT|-] [--append TEXT|-] [--attach PATH]… [--action …]…   the sender's own only
  revert ID REV            undoes update REV (inbox_update's undo)
  list [--unread|--archived|--all] [--mine] [--from KEY] [--search WORDS] [--limit N]
  show ID [--mark-read]    the whole message, with its files' paths
  press ID N|session|task [--yes]      a button (press.py; run only with --yes)
  read ID…|--all [--unread]     archive ID… [--undo]     delete ID     count
Every command takes --json. post and update take --stdin-json: {title, body, append, attachments, actions, task}.
"""
import argparse
import json
import os
import shlex
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import actions as act      # noqa: E402
import attach              # noqa: E402
import press as button     # noqa: E402
import query               # noqa: E402
import sender as who       # noqa: E402
import store               # noqa: E402
from store import InboxError   # noqa: E402

TITLE_MAX = 200
BODY_MAX = 100_000     # characters of Markdown: a long report, not a log file (attach that)
LIST_LIMIT = 50


def text_arg(value):
    """--body -: the text from stdin."""
    return sys.stdin.read() if value == "-" else value


def clean_title(title):
    title = " ".join(str(title or "").split())
    if not title:
        raise InboxError("a message needs a title")
    if len(title) > TITLE_MAX:
        raise InboxError(f"the title is at most {TITLE_MAX} characters")
    return title


def clean_body(body):
    body = str(body or "").strip("\n")
    if len(body) > BODY_MAX:
        raise InboxError(f"the text is at most {BODY_MAX} characters: attach a longer one as a file")
    return body


def request(a):
    """What post/update were asked, from the flags or (--stdin-json) the tool's JSON."""
    if a.stdin_json:
        try:
            data = json.load(sys.stdin)
        except ValueError as e:
            raise InboxError(f"the request isn't JSON: {e}")
        if not isinstance(data, dict):
            raise InboxError("the request must be a JSON object")
    else:
        data = {"title": getattr(a, "title", None), "body": text_arg(a.body) if a.body is not None else None,
                "append": text_arg(getattr(a, "append", None)) if getattr(a, "append", None) is not None else None,
                "attachments": a.attach or [], "actions": act.from_cli(a.action or []), "task": a.task}
    return data


def base_dir(a):
    """Where relative paths start, and run buttons run by default: --dir, else where it was sent from (a tool's: the
    session's folder, run.py's NIGHTDRIVE_MCP_CWD), not the folder the session started in, which a shell may have left."""
    return str(Path(os.path.expanduser(a.dir)).resolve()) if a.dir else \
        os.environ.get("NIGHTDRIVE_MCP_CWD") or os.getcwd()


def summary(msg):
    """A message as list gives it: no body, the counts of its files and buttons."""
    keys = ("id", "title", "at", "updated", "read", "from", "task", "archived")
    out = {k: msg.get(k) for k in keys}
    out["attachments"] = len(msg.get("attachments") or [])
    out["actions"] = len(msg.get("actions") or [])
    return out


def full(msg):
    """A message as show gives it: everything, its files with their paths."""
    path = store.folder(msg["id"])
    out = query.decorate(dict(msg))
    out["folder"] = str(path) if path else None
    out["attachments"] = [{**f, "path": str(path / f["name"]) if path else None} for f in msg.get("attachments", [])]
    # A run button's command as one line, quoted as a shell would need it: what the window shows under it and on its card
    out["actions"] = [{**b, "line": shlex.join(b["argv"])} if b["kind"] == "run" else b for b in msg.get("actions") or []]
    return out


def emit(a, data, text):
    print(json.dumps(data, ensure_ascii=False) if a.json else text)


def cmd_post(a):
    data = request(a)
    sender = who.detect(app=a.app)
    base = base_dir(a)
    title, body = clean_title(data.get("title")), clean_body(data.get("body"))
    task = act.task_number(data.get("task")) or (who.task_of(sender.get("name")) if sender["kind"] == "claude" else None)
    buttons = act.check_all(data.get("actions") or [], base)
    files = attach.checked(data.get("attachments") or [], base)
    msg = store.create(title, body, sender, task, buttons, attach.copier(files))
    emit(a, {**summary(msg), "folder": str(store.folder(msg["id"]))}, f"Left {msg['id']}: {msg['title']}")


def cmd_update(a):
    mid = store.resolve(a.id)
    data = request(a)
    me = who.detect(app=a.app)
    current = store.load(store.folder(mid))
    if not who.same(current.get("from") or {}, me):
        raise InboxError(f"message {mid} is from {who.label(current.get('from') or {})}: only its sender can add to it")
    base = base_dir(a)
    title = clean_title(data["title"]) if data.get("title") else None
    body = clean_body(data["body"]) if data.get("body") is not None else None
    append = clean_body(data["append"]) if data.get("append") else None
    task = act.task_number(data.get("task"))
    buttons = act.check_all(data.get("actions") or [], base, len(current.get("actions") or []))
    files = attach.checked(data.get("attachments") or [], base, len(current.get("attachments") or []))
    if not any((title, body is not None, append, task, buttons, files)):
        raise InboxError("nothing to change: give a title, text, files or buttons")

    def change(msg, path):
        if title:
            msg["title"] = title
        if body is not None:
            msg["body"] = body
        if append:
            msg["body"] = clean_body((msg.get("body") or "") + "\n\n" + append)
        if task:
            msg["task"] = task
        msg["actions"] = (msg.get("actions") or []) + buttons
        msg["attachments"] = attach.copier(files)(path, msg.get("attachments") or [])

    msg, rev = store.update(mid, change)
    emit(a, {**summary(msg), "rev": rev}, f"Updated {mid} (update {rev}): {msg['title']}")


def cmd_revert(a):
    msg = store.revert(store.resolve(a.id), a.rev)
    emit(a, summary(msg), f"Back as it was: {msg['id']} {msg['title']}")


def cmd_list(a):
    archived = None if a.all else a.archived
    msgs = store.messages(archived)
    if a.unread:
        msgs = [m for m in msgs if not m.get("read")]
    if a.mine:
        me = who.detect()
        msgs = [m for m in msgs if who.same(m.get("from") or {}, me)]
    senders = query.groups(msgs)       # before --from and --search: the sidebar shows every sender there is
    wanted = query.words(a.search)
    msgs = [m for m in msgs if query.matches_from(m, a.sender) and query.matches_search(m, wanted)]
    unread = sum(1 for m in store.messages(False) if not m.get("read"))
    shown = msgs[:a.limit] if a.limit > 0 else msgs
    lines = [f"{'●' if not m.get('read') else ' '} {m['id']}  {m['title']}  ({who.label(m.get('from') or {})})"
             + ("  [archived]" if m.get("archived") and a.all else "") for m in shown]
    emit(a, {"messages": [query.decorate(summary(m)) for m in shown], "total": len(msgs), "unread": unread,
             "senders": senders},
         "\n".join(lines) or "No messages.")


def cmd_show(a):
    mid = store.resolve(a.id)
    msg = store.set_read(mid) if a.mark_read else store.load(store.folder(mid))
    out = full(msg)
    lines = [out["title"], f"from {who.label(out.get('from') or {})}, {out['at']}"
             + (f", task #{out['task']}" if out.get("task") else ""), "", out.get("body") or ""]
    lines += [f"  file: {f['path']}" for f in out["attachments"]]
    lines += [f"  {act.describe(b)}" for b in out.get("actions") or []]
    emit(a, out, "\n".join(lines).rstrip())


def cmd_read(a):
    ids = [m["id"] for m in store.messages(False) if bool(m.get("read")) == a.unread] if a.all else \
        [store.resolve(i) for i in a.ids]
    if not ids and not a.all:
        raise InboxError("which messages? Give their ids, or --all")
    done = [summary(store.set_read(i, not a.unread)) for i in ids]
    emit(a, {"messages": done}, f"Marked {len(done)} {'unread' if a.unread else 'read'}.")


def cmd_archive(a):
    done = [summary(store.set_archived(store.resolve(i), not a.undo)) for i in a.ids]
    emit(a, {"messages": done}, f"{'Back in the inbox' if a.undo else 'Archived'}: {len(done)}.")


def cmd_delete(a):
    msg = store.delete(store.resolve(a.id))
    emit(a, summary(msg), f"Deleted {msg['id']}: {msg['title']}")


def cmd_press(a):
    mid = store.resolve(a.id)
    done = button.press(store.load(store.folder(mid)), a.which, a.yes)
    what = done.get("opened") or done.get("copied") or done.get("session") or " ".join(done.get("ran") or [])
    emit(a, done, f"{done['label']}: {what}")


def cmd_count(a):
    """The bars' numbers (#3179): every unread message for the top bar's icon, Claude's sessions' for the sessions
    bar's button."""
    msgs = store.messages(False)
    unread = [m for m in msgs if not m.get("read")]
    claude = sum(1 for m in unread if (m.get("from") or {}).get("kind") == "claude")
    emit(a, {"unread": len(unread), "total": len(msgs), "claude": claude}, str(len(unread)))


def parser():
    ap = argparse.ArgumentParser(prog="nightdrive inbox", description="Nightdrive Inbox: messages to look at later.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add(name, fn, help_):
        p = sub.add_parser(name, help=help_)
        p.add_argument("--json", action="store_true")
        p.set_defaults(fn=fn)
        return p

    def content(p):
        p.add_argument("--body", help="the text, Markdown (- reads stdin)")
        p.add_argument("--attach", action="append", metavar="PATH", help="a file to copy in (again for more)")
        p.add_argument("--action", action="append", nargs=3, metavar=("KIND", "LABEL", "VALUE"),
                       help="a button: open PATH, url URL, run COMMAND, session ID or task N")
        p.add_argument("--task", help="the Dashboard task it is about (a session's: its name's #N)")
        p.add_argument("--app", help="the app that sends it, when it isn't a Claude session")
        p.add_argument("--dir", help="where relative paths start and run buttons run (default: here)")
        p.add_argument("--stdin-json", action="store_true", help="the message as JSON on stdin (Claude's tools)")

    p = add("post", cmd_post, "leave a message")
    p.add_argument("title", nargs="?")
    content(p)
    p = add("update", cmd_update, "add to a message you left")
    p.add_argument("id")
    p.add_argument("--title")
    p.add_argument("--append", help="text added at the end (- reads stdin)")
    content(p)
    p = add("revert", cmd_revert, "undo an update")
    p.add_argument("id")
    p.add_argument("rev", type=int)
    p = add("list", cmd_list, "the messages, newest first")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--archived", action="store_true")
    g.add_argument("--all", action="store_true")
    p.add_argument("--unread", action="store_true")
    p.add_argument("--mine", action="store_true", help="only this session's (or --app's) own")
    p.add_argument("--from", dest="sender", metavar="KEY", help="one sender's: session:ID, project:NAME, app:NAME, other; claude = every session's")
    p.add_argument("--search", metavar="WORDS", help="those with every word in the title, text or sender")
    p.add_argument("--limit", type=int, default=LIST_LIMIT, help=f"at most N (default {LIST_LIMIT}, 0 for all)")
    p = add("show", cmd_show, "one message, whole")
    p.add_argument("id")
    p.add_argument("--mark-read", action="store_true")
    p = add("read", cmd_read, "mark read (or --unread)")
    p.add_argument("ids", nargs="*")
    p.add_argument("--all", action="store_true")
    p.add_argument("--unread", action="store_true")
    p = add("archive", cmd_archive, "move out of the inbox (--undo: back)")
    p.add_argument("ids", nargs="+")
    p.add_argument("--undo", action="store_true")
    p = add("delete", cmd_delete, "remove for good")
    p.add_argument("id")
    p = add("press", cmd_press, "do what a button does: N (0 the first), or the sender's session or task")
    p.add_argument("id")
    p.add_argument("which", metavar="N|session|task")
    p.add_argument("--yes", action="store_true", help="a run button: the command has been seen, run it")
    add("count", cmd_count, "how many are unread")
    return ap


def main(argv=None):
    a = parser().parse_args(argv)
    try:
        a.fn(a)
    except InboxError as e:
        print(f"inbox: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
