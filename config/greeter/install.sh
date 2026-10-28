#!/bin/bash
# Installs greetd and the login screen files into /etc/greetd. Does NOT switch the login screen (that's done with: switch.sh on).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

# In packages.txt as well (install.sh has installed them by now); here for a run of its own
sudo dnf install -y greetd greetd-selinux
# Wanted for themselves, even if something had pulled them in already: removing KDE mustn't take the login screen along
sudo dnf mark user -y greetd greetd-selinux >/dev/null
[[ -f /etc/greetd/config.toml && ! -f /etc/greetd/config.toml.orig ]] && sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.orig
sudo install -d -m 0755 /etc/greetd /etc/greetd/greeter
# An autologin set up with switch.sh autologin stays on (the fresh config.toml wouldn't have it)
autologin=0
grep -q '^\[initial_session\]' /etc/greetd/config.toml 2>/dev/null && systemctl -q is-enabled greetd.service 2>/dev/null && autologin=1
# So does the text login (switch.sh text): chosen in place of this login screen, which an update mustn't bring back
text=0
grep -q '^# Text login (switch.sh text)' /etc/greetd/config.toml 2>/dev/null && systemctl -q is-enabled greetd.service 2>/dev/null && text=1
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
# The text login it falls back to names switch.sh where this repo is
sed "s|@SWITCH@|${here/#$HOME/\~}/switch.sh|" "$here/greeter.sh" | sudo install -m 0644 /dev/stdin /etc/greetd/greeter.sh
sed "s/@USER@/${SUDO_USER:-$USER}/" "$here/shell.qml" | sudo install -m 0644 /dev/stdin /etc/greetd/greeter/shell.qml
# A VM's screen follows its window at the login screen too (hyprland-greeter.lua)
sudo install -m 0644 "$here/../hypr/vm-display.lua" "$here/../hypr/scripts/vm-display" /etc/greetd/
sudo install -m 0644 "$here/LoginView.qml" "$here/NightdriveLogo.qml" "$here/background.jpg" /etc/greetd/greeter/
sudo install -m 0644 -D -t /etc/greetd/greeter/sounds "$here"/sounds/*.wav
# Last, once greeter.sh it runs is there
(( text )) || sudo install -m 0644 "$here/config.toml" /etc/greetd/config.toml
# What these files were installed from (the git tree of this directory, and the two of hypr's): `nightdrive update`
# installs them again when it changes
git -C "$here" rev-parse HEAD:./ HEAD:../hypr/vm-display.lua HEAD:../hypr/scripts/vm-display 2>/dev/null | sudo install -m 0644 /dev/stdin /etc/greetd/greeter/version
sudo restorecon -R /etc/greetd 2>/dev/null || true
if (( autologin )); then "$here/switch.sh" autologin; exit; fi
if (( text )); then echo "Done. The text login stays the login screen; $here/switch.sh on (or autologin) switches to this one"; exit; fi
echo "Done. The login screen only switches with: $here/switch.sh on (or autologin)"
