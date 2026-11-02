#!/bin/bash
# Mac Keyboard Shortcuts (plugin keyd): ⌥⌫ deletes a word, ⌘⌫ to the start of the line (Files: to the trash,
# Thunderbird: the message), done by keyd as real key presses before Hyprland. Hyprland's own way (send_shortcut) sometimes loses a key's
# release and the app repeats the key (Hyprland #8385, #6407). keyd comes from a COPR (alternateved/keyd): it isn't in
# Fedora's own repos. Config in this folder: default.conf → /etc/keyd, app.conf → ~/.config/keyd for the per-app mapper.
# Files gets Finder's Enter (rename) and ⌘O (open) from a Nautilus extension: nautilus-python/mac-keys.py (link.sh
# links it too).
# Emergency exit: Backspace + Escape + Enter together stops keyd. Off again: sudo systemctl disable --now keyd
set -euo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
repo=$(cd "$here/../.." && pwd)
sudo dnf copr enable -y alternateved/keyd
sudo dnf install -y keyd nautilus-python
sudo install -Dm644 "$here/default.conf" /etc/keyd/default.conf
# keyd's virtual keyboard counts as the internal one: the trackpad's disable-while-typing keeps working. Added after
# install.sh's own libinput tweaks: the file is shared.
cat "$repo/config/system/libinput-apple-mtp.quirks" "$here/local-overrides.quirks" |
  sudo install -Dm644 /dev/stdin /etc/libinput/local-overrides.quirks
sudo usermod -aG keyd "$USER"   # keyd-application-mapper talks to keyd's socket
# Started again, not `keyd reload`: keyd 2.6.0 segfaulted on the next key event after a reload (the Enter that ran this,
# still held) and stayed down (config/system/sync)
sudo systemctl enable keyd
sudo systemctl restart keyd
mkdir -p ~/.config/keyd && ln -sfn "$here/app.conf" ~/.config/keyd/app.conf
mkdir -p ~/.local/share/nautilus-python/extensions
ln -sfn "$here/nautilus-python/mac-keys.py" ~/.local/share/nautilus-python/extensions/mac-keys.py
# Started for this session too (hyprland.lua starts it from the next login, when the keyd group is in effect). Found by
# its command line's start (python3 and its path) and only among this user's: the name anywhere would match a grep.
pgrep -u "$UID" -f '^([^ ]*/)?python3?[0-9.]* ([^ ]*/)?keyd-application-mapper( |$)' >/dev/null || setsid sg keyd -c "keyd-application-mapper -d" </dev/null >/dev/null 2>&1 &
~/.local/bin/nightdrive plugins installed >/dev/null 2>&1 || true   # the desktop picks the plugin up (its keys and shortcut lines)
echo "Mac Keyboard Shortcuts are on. ⌘⌫ follows the app from the next login (keyd group); Enter and ⌘O in Files once Files"
echo "starts again (nautilus -q closes it now)."
