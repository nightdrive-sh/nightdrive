"""The file types an app's Open or Save window offers (the portal's filters), as name patterns Files' picker can match.

A portal filter is a name and rules, each a glob ("*.png") or a MIME type ("image/png", "image/*"). The picker reads
only names, so a MIME type becomes the globs the shared MIME database gives it (globs2 in each of $XDG_DATA_DIRS'
mime folders, the same Nautilus and GTK read); "image/*" every image type's. A type with no glob of its own
(application/octet-stream, */*) matches any file, as GTK's chooser shows it.

The picker gets each filter's globs as one regular expression in the syntax JavaScript and Python share (regex()), so
the matching is done and tested here and the QML only runs it.
"""
import mimetypes
import os
import re

ANY = {"*/*", "application/octet-stream", "all/allfiles", "all/all"}


def data_dirs():
    home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return [home] + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")


def load_globs(dirs=None):
    """{mime: [glob, …]} from every globs2 found, the user's own first."""
    out = {}
    for d in dirs or data_dirs():
        try:
            with open(os.path.join(d, "mime", "globs2"), encoding="utf-8") as f:
                for line in f:
                    if line.startswith("#"):
                        continue
                    parts = line.rstrip("\n").split(":")
                    if len(parts) >= 3:
                        out.setdefault(parts[1], [])
                        if parts[2] not in out[parts[1]]:
                            out[parts[1]].append(parts[2])
        except OSError:
            continue
    return out


def globs_of(rules, table):
    """The globs one filter's rules come to: [kind, pattern] pairs, kind 0 a glob and 1 a MIME type."""
    out = []
    for kind, pattern in rules:
        if kind == 0:
            found = [pattern]
        elif pattern in ANY:
            found = ["*"]
        elif pattern.endswith("/*"):
            found = [g for m, gs in table.items() if m.startswith(pattern[:-1]) for g in gs]
        else:
            found = table.get(pattern, [])
        out += [g for g in found if g not in out]
    return out


def glob_regex(glob):
    """One glob as a regular expression body: * any run, ? one character, [abc] and [!abc] as they are."""
    out, i = "", 0
    while i < len(glob):
        ch = glob[i]
        if ch == "*":
            out += ".*"
        elif ch == "?":
            out += "."
        elif ch == "[" and "]" in glob[i + 2:]:
            end = glob.index("]", i + 2)
            body = glob[i + 1:end]
            out += "[" + ("^" + body[1:] if body.startswith("!") else body).replace("\\", "\\\\") + "]"
            i = end
        else:
            out += re.escape(ch)
        i += 1
    return out


def regex(globs):
    """The globs as one anchored expression, matched without regard to case; "" when any name will do."""
    if not globs or "*" in globs:
        return ""
    return "^(?:" + "|".join(glob_regex(g) for g in globs) + ")$"


def ending(rules, globs):
    """The ending a saved file takes in this type: the app's own first glob (*.png), else the one people use for the
    MIME type (mimetypes: .jpg, not the database's first, .jfif), else the first plain one; "" when there is none, or
    the type is many (image/*): the name keeps its own."""
    plain = [g[2:] for g in globs if re.fullmatch(r"\*\.[\w.+-]+", g)]
    if not plain:
        return ""
    for kind, pattern in rules:
        if kind == 0:
            return pattern[2:] if pattern[2:] in plain else plain[0]
        if pattern.endswith("/*") or pattern in ANY:          # many types: no one ending to give the name
            return ""
        ext = mimetypes.guess_extension(pattern, strict=False)
        if ext and ext[1:] in plain:
            return ext[1:]
    return plain[0]


def expand(filters, table=None):
    """Each filter of a request (portal.request_of) with its globs beside its rules, and their regex for the QML."""
    if any(k == 1 for f in filters for k, _ in f["rules"]):
        table = table if table is not None else load_globs()
    for f in filters:
        f["globs"] = globs_of(f["rules"], table or {})
        f["regex"] = regex(f["globs"])
        f["ending"] = ending(f["rules"], f["globs"])
    return filters

