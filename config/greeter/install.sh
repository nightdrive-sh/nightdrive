#!/bin/bash
# Installs greetd and the login screen files into /etc/greetd. Does NOT switch the login screen (that's done with: switch.sh on).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

sudo dnf install -y greetd greetd-selinux
# Wanted for themselves, even if something had pulled them in already: removing KDE mustn't take the login screen along
sudo dnf mark user -y greetd greetd-selinux >/dev/null
[[ -f /etc/greetd/config.toml && ! -f /etc/greetd/config.toml.orig ]] && sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.orig
sudo install -d -m 0755 /etc/greetd /etc/greetd/greeter
# An autologin set up with switch.sh autologin stays on (the fresh config.toml wouldn't have it)
autologin=0
grep -q '^\[initial_session\]' /etc/greetd/config.toml 2>/dev/null && systemctl -q is-enabled greetd.service 2>/dev/null && autologin=1
sudo install -m 0644 "$here/config.toml" /etc/greetd/config.toml
# On a PC the scale is Hyprland's own pick. The keyboard is the layout Fedora's installer set on a PC, and on a Mac or a VM
# too unless it's Finnish, as install.sh writes for the session in hypr/local.lua (the file itself is the MacBook's):
# the password is typed with it
platform="$here/../hypr/scripts/platform"
machine=$("$platform" machine)
read -r kb_layout kb_variant _ <<<"$("$platform" keyboard)"
[[ $kb_layout =~ ^[a-z0-9_,-]+$ ]] || kb_layout=us
[[ ${kb_variant:-} =~ ^[a-z0-9_,-]*$ ]] || kb_variant=""
edits=()
[[ $machine == pc ]] && edits+=(-e 's/scale = 2\.0 })/scale = "auto" })/')
[[ $machine == pc || $kb_layout != fi ]] && \
  edits+=(-e "s/kb_layout = \"fi\", kb_variant = \"mac\"/kb_layout = \"$kb_layout\", kb_variant = \"${kb_variant:-}\"/")
sed "${edits[@]}" -e '' "$here/hyprland-greeter.lua" | sudo install -m 0644 /dev/stdin /etc/greetd/hyprland-greeter.lua
sed "s/@USER@/${SUDO_USER:-$USER}/" "$here/shell.qml" | sudo install -m 0644 /dev/stdin /etc/greetd/greeter/shell.qml
sudo install -m 0644 "$here/LoginView.qml" "$here/NightdriveLogo.qml" "$here/background.jpg" /etc/greetd/greeter/
sudo install -m 0644 -D -t /etc/greetd/greeter/sounds "$here"/sounds/*.wav
# What these files were installed from (the git tree of this directory): `nightdrive update` installs them again when it changes
git -C "$here" rev-parse HEAD:./ 2>/dev/null | sudo install -m 0644 /dev/stdin /etc/greetd/greeter/version
sudo restorecon -R /etc/greetd 2>/dev/null || true
if (( autologin )); then "$here/switch.sh" autologin; exit; fi
echo "Done. The login screen only switches with: $here/switch.sh on (or autologin)"
