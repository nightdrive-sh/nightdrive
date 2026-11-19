"""Which messages a list shows (#3178): the senders they can be narrowed to, and a search. The window (plugins/inbox)
reads these from `list --json` rather than working them out itself, so the command, Claude and the window agree.

A sender key names what a list can be narrowed to:

    session:<id>      one Claude Code session's messages
    project:<name>    every session's in one project folder (its last part: "dotfiles", "coldstart")
    app:<name>        one app's
    other             a terminal's or a script's: nothing says who sent them
    claude            every Claude Code session's (the sessions bar's Inbox button, #3179)
"""
import re

from sender import HOME, label


def session_key(sender):
    kind = sender.get("kind")
    if kind == "claude":
        return "session:" + str(sender.get("session") or "")
    if kind == "app":
        return "app:" + str(sender.get("app") or "")
    return "other"


def group_key(sender):
    """The sidebar's row for a sender: a session's project, an app, or other."""
    if sender.get("kind") == "claude":
        return "project:" + str(sender.get("project") or "?")
    return session_key(sender)


def short_label(sender):
    """The list row's line: the session's name, or what it was in; an app's name."""
    kind = sender.get("kind")
    if kind == "claude":
        name = sender.get("name") or "Claude " + str(sender.get("session") or "")[:8]
        return name if sender.get("name") else f"{name} · {sender.get('project') or '?'}"
    if kind == "app":
        return sender.get("app") or "An app"
    return "A command in " + str(sender.get("dir") or "?").replace(str(HOME), "~", 1)


def decorate(summary):
    """A list row with its sender's keys and lines, for the window."""
    sender = summary.get("from") or {}
    return {**summary, "sender": {"label": label(sender), "short": short_label(sender), "kind": sender.get("kind"),
                                  "session": session_key(sender), "group": group_key(sender)}}


def matches_from(msg, key):
    sender = msg.get("from") or {}
    return not key or key in (session_key(sender), group_key(sender)) or (key == "claude" and sender.get("kind") == "claude")


def words(text):
    return [w for w in re.split(r"\s+", (text or "").lower()) if w]


def matches_search(msg, wanted):
    """Every word somewhere in its title, text, sender or task number, case aside."""
    if not wanted:
        return True
    hay = " ".join([msg.get("title") or "", msg.get("body") or "", label(msg.get("from") or {}),
                    f"#{msg['task']}" if msg.get("task") else ""]).lower()
    return all(w in hay for w in wanted)


def groups(msgs):
    """The sidebar's senders, the most recent first: [{key, kind, label, unread, total}]. A project's label is its
    folder's name; an app's its name."""
    out = {}
    for m in msgs:
        sender = m.get("from") or {}
        key = group_key(sender)
        g = out.setdefault(key, {"key": key, "kind": sender.get("kind"), "unread": 0, "total": 0,
                                 "label": sender.get("project") if sender.get("kind") == "claude"
                                 else short_label(sender) if sender.get("kind") == "app" else "Other"})
        g["total"] += 1
        g["unread"] += 0 if m.get("read") else 1
    return list(out.values())
