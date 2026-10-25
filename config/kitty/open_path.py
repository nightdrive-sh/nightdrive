"""Ctrl+click on a file or folder path in kitty's output opens it (kitty.conf › Links).

Claude Code and most programs print paths as plain text, not OSC 8 links, so kitty's own link handling can't see
them: this kitten reads the word under the mouse from the screen instead. A folder opens in the file manager
(xdg-open), a text file in the code editor at its line (`file.py:42`, `file.py:42:7`), anything else in its default
app. A relative path is taken from the program's working directory (Claude Code's: its project). Not a path that
exists → kitty's link click as before (URLs, OSC 8 links).
"""
import os
import re
import shutil
import subprocess

from kittens.tui.handler import result_handler

# The code editor kind of Settings › Apps › Default apps (hypr/scripts/default-apps): its first type answers for it
CODE_TYPE = "text/x-python"
# Editors that can open a file at a line: desktop id -> (command, how the argv is built)
EDITORS = {
    "code.desktop": ("code", lambda p, l, c: ["--goto", f"{p}:{l}:{c}"]),
    "com.visualstudio.code.desktop": ("code", lambda p, l, c: ["--goto", f"{p}:{l}:{c}"]),
    "code-oss.desktop": ("code-oss", lambda p, l, c: ["--goto", f"{p}:{l}:{c}"]),
    "codium.desktop": ("codium", lambda p, l, c: ["--goto", f"{p}:{l}:{c}"]),
    "dev.zed.Zed.desktop": ("zed", lambda p, l, c: [f"{p}:{l}:{c}"]),
    "org.gnome.TextEditor.desktop": ("gnome-text-editor", lambda p, l, c: [f"+{l}:{c}", p]),
}
# Characters that end a path in running text (quotes, brackets, separators of a list)
STOP = set(" \t'\"`()[]{}<>,;|│")
LOCATION = re.compile(r"^(.*?)(?::(\d+))?(?::(\d+))?$")


def main(args):
    pass


def column_index(line, x):
    """The index in line of the character in cell x: a wide character (CJK, some symbols) takes two cells."""
    from kitty.fast_data_types import wcswidth
    cells = 0
    for i, ch in enumerate(line):
        cells += max(wcswidth(ch), 1)
        if cells > x:
            return i
    return len(line)


def word_at(line, x):
    """The run of path characters around column x, without trailing punctuation."""
    x = column_index(line, x)
    if x >= len(line) or line[x] in STOP:
        return ""
    start, end = x, x
    while start > 0 and line[start - 1] not in STOP:
        start -= 1
    while end < len(line) and line[end] not in STOP:
        end += 1
    return line[start:end].rstrip(".:")


def resolve(word, cwd):
    """(path, line, column) of an existing file or folder, or None."""
    m = LOCATION.match(word.removeprefix("file://"))
    path, line, col = m.group(1), m.group(2) or "1", m.group(3) or "1"
    path = os.path.expanduser(path)
    if not os.path.isabs(path):
        path = os.path.join(cwd or os.path.expanduser("~"), path)
    return (os.path.normpath(path), line, col) if path and os.path.exists(path) else None


def is_text(path):
    try:
        with open(path, "rb") as f:
            return b"\0" not in f.read(8192)
    except OSError:
        return False


def editor():
    """The code editor: the chosen default if it can go to a line, else the first such one installed."""
    try:
        chosen = subprocess.run(["xdg-mime", "query", "default", CODE_TYPE],
                                capture_output=True, text=True, timeout=2).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        chosen = ""
    for desktop in [chosen] + list(EDITORS):
        if desktop in EDITORS and shutil.which(EDITORS[desktop][0]):
            return EDITORS[desktop]
    return None


def start(argv):
    subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def open_target(path, line, col):
    if os.path.isfile(path) and is_text(path):
        ed = editor()
        if ed:
            start([ed[0]] + ed[1](path, line, col))
            return
    start(["xdg-open", path])


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        return
    pos = w.current_mouse_position()
    target = None
    if pos:
        line = str(w.screen.visual_line(pos["cell_y"]) or "")
        word = word_at(line, pos["cell_x"])
        if word:
            target = resolve(word, w.child.foreground_cwd or w.child.current_cwd)
    if target:
        open_target(*target)
    else:
        w.mouse_handle_click("link")
