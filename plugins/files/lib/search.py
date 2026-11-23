#!/usr/bin/python3 -I
"""Files' search below a folder (Search.qml runs it): the names under FOLDER, at every depth, that have WORDS in them,
found with fd and printed as they come, one JSON object a line:

  search.py FOLDER WORDS [--hidden]

  {"rows": [{"name", "path", "dir", "size", "modified", "folder"}, …]}   a batch of what was found ("folder": where it
                                                                       is, relative to FOLDER, "" for FOLDER itself)
  {"done": true, "count": N, "capped": bool}                           the last line
  {"missing": "fd"}                                                    fd isn't installed (exit 1)

fd is always up to date (no index to build) and fast. Its own rules decide what is left out: hidden files (shown with
--hidden, as the list's . does, but .git never), what .gitignore, .ignore and .fdignore exclude, and other disks under
FOLDER (--one-file-system: a search from / doesn't walk a USB stick or a network share). WORDS is plain text, case
left aside, in the name only. At most LIMIT are found: more than that is a sign to type more.
"""
import json, os, shutil, subprocess, sys

LIMIT = 2000        # rows at most; the list stays quick and the window's sort with it
BATCH = 50          # rows a line: the window adds each line at once, so fewer lines are fewer rebuilds


def command(fd, folder, words, hidden):
    cmd = [fd, "--fixed-strings", "--ignore-case", "--one-file-system", "--color", "never", "--print0",
           "--absolute-path", "--max-results", str(LIMIT)]
    if hidden:
        cmd += ["--hidden", "--exclude", ".git"]
    # "--" so that words starting with "-" stay words; the folder is fd's search path
    return cmd + ["--", words, folder]


def row(path, root):
    """One found path as the list's row: lstat, so a link to a folder isn't counted as one (fd doesn't follow them)"""
    path = path.rstrip("/") or "/"
    try:
        st = os.lstat(path)
    except OSError:
        return None                      # gone between fd and here
    is_dir = os.path.isdir(path) and not os.path.islink(path)
    parent = os.path.dirname(path)
    folder = os.path.relpath(parent, root) if parent != root else ""
    return {"name": os.path.basename(path), "path": path, "dir": is_dir,
            "size": 0 if is_dir else st.st_size, "modified": int(st.st_mtime * 1000), "folder": folder}


def search(folder, words, hidden=False, emit=print, fd=None):
    """Runs fd and emits the batches and the last line; returns the number found, or None when fd is missing"""
    fd = fd or shutil.which("fd") or shutil.which("fdfind")     # Debian and Ubuntu name it fdfind
    if not fd:
        emit(json.dumps({"missing": "fd"}))
        return None
    root = os.path.realpath(folder)
    proc = subprocess.Popen(command(fd, root, words, hidden), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    count, batch, rest = 0, [], b""
    try:
        for chunk in iter(lambda: proc.stdout.read1(65536), b""):
            *paths, rest = (rest + chunk).split(b"\0")
            for p in paths:
                r = row(os.fsdecode(p), root)
                if r is None:
                    continue
                batch.append(r)
                count += 1
                if len(batch) >= BATCH:
                    emit(json.dumps({"rows": batch}, ensure_ascii=False))
                    batch = []
    finally:
        proc.stdout.close()
        proc.wait()
    if batch:
        emit(json.dumps({"rows": batch}, ensure_ascii=False))
    emit(json.dumps({"done": True, "count": count, "capped": count >= LIMIT}))
    return count


def main(argv):
    args = [a for a in argv if a != "--hidden"]
    if len(args) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    found = search(args[0], args[1], hidden="--hidden" in argv, emit=lambda s: print(s, flush=True))
    return 1 if found is None else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (BrokenPipeError, KeyboardInterrupt):
        # The window stops a search that a new letter replaced: no traceback for that
        sys.exit(0)
