#!/usr/bin/env python3
"""nightdrive_status as an MCP tool (tools/status.json; plan: Dashboard #1761, #1764): what this desktop is and runs,
so Claude needn't guess before it answers or uses another tool.

Every line comes from a command that already answers it (nightdrive version, channel, plugins, theme; hyprctl), so
this file only gathers. One that fails is left out with a note rather than failing the whole status.

Run as a command too: `status.py nightdrive_status` (arguments, none, as JSON on stdin) prints the text.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
NIGHTDRIVE = REPO / "bin/nightdrive"
STATE = Path.home() / ".local/state"
WALLPAPER = STATE / "wallpaper/current"         # a link to the image (scripts/wallpaper)
THEME_NAME = STATE / "nightdrive/theme-name"    # the theme picked in Settings › Theme › Themes (scripts/theme)
TIMEOUT = 10


def run(*argv):
    """A command's stdout, or None when it fails: a missing part shows as a note, not an error."""
    try:
        out = subprocess.run([str(a) for a in argv], capture_output=True, text=True, timeout=TIMEOUT)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def fedora():
    try:
        rows = dict(line.split("=", 1) for line in Path("/etc/os-release").read_text().splitlines() if "=" in line)
    except OSError:
        return None
    return rows.get("PRETTY_NAME", "").strip('"') or None


def plugins():
    """(installed, turned off, not installed) as "Name (id, kind)". nightdrive plugins list's columns: id, name,
    icon, description, default, install, installed 1/0, kind, folder, turned off 1/0, repo/external."""
    out = run(NIGHTDRIVE, "plugins", "list")
    if out is None:
        return None
    on, off, absent, seen = [], [], [], set()
    for line in out.splitlines():
        cols = line.split("\t")
        if len(cols) < 10 or cols[0] in seen:  # the list repeats the apps among the plugins
            continue
        seen.add(cols[0])
        where = absent if cols[6] != "1" else off if cols[9] == "1" else on
        where.append(f"{cols[1]} ({cols[0]}, {cols[7]})")
    return on, off, absent


def displays():
    out = run("hyprctl", "monitors", "-j")
    try:
        monitors = json.loads(out) if out else None
    except json.JSONDecodeError:
        return None
    if not monitors:
        return None
    return [f"{m['name']}: {m['width']}×{m['height']} @ {round(m['refreshRate'])} Hz, scale {m['scale']:g}"
            + (", focused" if m.get("focused") else "") for m in monitors]


def nightdrive_status(args):
    lines, missing = [], []

    def add(label, value):
        if value:
            lines.append(f"{label}:{"" if value.startswith(chr(10)) else " "}{value}")
        else:
            missing.append(label.lower())

    add("Version", run(NIGHTDRIVE, "version"))
    add("Update channel", run(NIGHTDRIVE, "channel"))
    add("System", fedora())
    add("Desktop", "Hyprland" if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") else None)
    theme = run(NIGHTDRIVE, "theme", "color")
    try:
        name = THEME_NAME.read_text().strip()
    except OSError:
        name = ""
    add("Theme", theme and (f"{name}, colour {theme}" if name else f"colour {theme}"))
    add("Wallpaper", WALLPAPER.is_symlink() and os.path.basename(os.readlink(WALLPAPER)))
    shown = displays()
    add("Displays", shown and "\n  " + "\n  ".join(shown))
    parts = plugins()
    if parts:
        on, off, absent = parts
        add("Installed apps and plugins", ", ".join(on) or "none")
        if off:
            add("Installed but turned off", ", ".join(off))
        add("Available, not installed", ", ".join(absent) or "none")
    else:
        missing.append("plugins")
    if missing:
        lines.append(f"(Couldn't read: {', '.join(missing)}.)")
    lines.append("Ask docs_search how any of it works; `nightdrive help` lists the commands.")
    return "\n".join(lines)


TOOLS = {"nightdrive_status": nightdrive_status}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in TOOLS:
        sys.exit(f"usage: status.py {'|'.join(TOOLS)}")
    print(TOOLS[sys.argv[1]]({}))


if __name__ == "__main__":
    main()
