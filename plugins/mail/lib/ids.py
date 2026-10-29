#!/usr/bin/env python3
"""The ids Mail's commands take (a message's, a thread's, a draft's), checked before they reach notmuch (Dashboard
#1859).

An id used to be glued into an infix query as text, so one id could be a whole query: `thread:0 or tag:inbox` archived
the entire inbox, and a draft "id" with a quote in it sent one draft and deleted all of them. Now an id given to a
command must have the exact form of one, finds exactly one message or thread, and goes to notmuch as a quoted string
of the s-expression syntax, where nothing in it is syntax. Ids read back from the database go the same way (message):
a stranger's Message-ID may hold a quote.

    thread:0000000000000005     a thread: "thread:" and notmuch's 16 hex digits
    local@domain                a message: its Message-ID without < >; no spaces, quotes, parentheses, backslashes,
                                angle brackets or * (a wildcard elsewhere)
    notmuch-sha1-<40 hex>       a message that had no Message-ID, named by notmuch
"""

import re
import subprocess

THREAD = re.compile(r"thread:([0-9a-f]{16})")
_ATOM = r'[^\s"()\\*<>@\x00-\x1f\x7f]'
MESSAGE = re.compile(rf"{_ATOM}{{1,500}}@{_ATOM}{{1,500}}|notmuch-sha1-[0-9a-f]{{40}}")


def string(text):
    """A string of the s-expression syntax."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def message(mid):
    """The s-expression that finds a message by its id, as the database has it (unchecked: it is quoted)."""
    return f"(id {string(mid.removeprefix('id:'))})"


def messages(mids):
    return f"(or {' '.join(map(message, mids))})"


def term(ident, threads=True):
    """A message's or (with threads) a thread's id as given to a command, as an s-expression; ValueError if it isn't
    one."""
    ident = ident if isinstance(ident, str) else ""
    m = THREAD.fullmatch(ident)
    if m and threads:
        return f"(thread {string(m.group(1))})"
    if not ident.startswith("thread:") and MESSAGE.fullmatch(ident):
        return f"(id {string(ident)})"   # as given: "id:x@y" isn't x@y's id
    kind = "a message's or a thread's id (thread:…)" if threads else "a message's id"
    raise ValueError(f"{ident!r} isn't {kind}: give one id as mail_search or mail_thread gave it, nothing else")


def notmuch(*args):
    return subprocess.run(["notmuch", *args], capture_output=True, text=True, check=True).stdout


def one(ident, threads=True):
    """term(), for an id that finds exactly one message or thread: none is LookupError, more than one ValueError."""
    query = term(ident, threads)
    output = "--output=threads" if query.startswith("(thread ") else "--output=messages"
    found = int(notmuch("count", output, "--exclude=false", "--query=sexp", query).strip() or 0)
    if not found:
        raise LookupError(f"No {'message or thread' if threads else 'message'} {ident} (it may have been deleted, "
                          "or not synced yet)")
    if found > 1:
        raise ValueError(f"{ident} finds {found} {output.removeprefix('--output=')}, not one: nothing done")
    return query
