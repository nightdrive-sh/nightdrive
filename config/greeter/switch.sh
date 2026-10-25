#!/bin/bash
# switch.sh on        → greetd with the Nightdrive login screen, from the next boot
# switch.sh autologin → greetd logs in at boot by itself, and the same login screen locks the session (lock.qml); one
#                       handover of the screen at boot instead of two. After logging out, the login screen is greetd's.
# switch.sh text      → greetd's text login (agreety), which starts the desktop after the password: the way in when the
#                       Nightdrive login screen doesn't work. "!bash" typed at its login prompt logs in to a text console.
# switch.sh off       → the distribution's own login screen (Fedora KDE's plasmalogin), or the text login where there's
#                       none (Fedora Minimal)
# Doesn't stop the running session. If Hyprland doesn't start, the login screen puts a text login in its place
# (greeter.sh); if nothing comes up: ctrl+alt+F3, log in and run `switch.sh text`, then `sudo reboot`.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
CONF=/etc/greetd/config.toml
PAM=/etc/pam.d/nightdrive-lock
# The login screens a distribution brings, the one of them that's installed is enabled by `off` (install.sh: other_dm)
OTHER_DMS=(plasmalogin sddm gdm lightdm)

greetd_on() {
  local dm
  for dm in "${OTHER_DMS[@]}"; do sudo systemctl disable "$dm.service" 2>/dev/null || true; done
  sudo systemctl enable --force greetd.service
}
# The login screen's own files: missing after `install.sh --no-greeter` (greetd alone, for the text login)
greeter_files() {
  [[ -f /etc/greetd/greeter.sh && -f /etc/greetd/greeter/shell.qml ]] || "$here/install.sh" >/dev/null
}
text_login() {
  command -v agreety >/dev/null || { echo "greetd isn't installed: sudo dnf install greetd greetd-selinux" >&2; exit 1; }
  # The first comment line is how config/greeter/install.sh tells this config apart, and leaves it as it is.
  # Hyprland's output off the text console, as in greeter.sh; the cursor the boot splash's greetd drop-in hid shown again
  printf '%s\n' '[terminal]' 'vt = 1' '' '[default_session]' \
    '# Text login (switch.sh text): agreety, then the desktop. "!bash" at the login prompt gives a text console instead' \
    'command = "sh -c '\''printf \"\\033[?25h\"; exec agreety --cmd \"start-hyprland >/dev/null 2>&1\"'\''"' \
    'user = "greetd"' | sudo install -m 0644 /dev/stdin "$CONF"
  sudo restorecon "$CONF" 2>/dev/null || true
  greetd_on
}

case "${1:-}" in
  on)  greeter_files
       greetd_on
       sudo install -m 0644 "$here/config.toml" "$CONF"
       sudo restorecon "$CONF" 2>/dev/null || true
       echo "greetd enabled from the next boot." ;;
  autologin)
       # The lock at startup is started from ~/.config/greeter (link.sh) by hyprland.lua
       [[ -f $HOME/.config/greeter/lock.qml ]] || { echo "~/.config/greeter/lock.qml is missing: run link.sh first" >&2; exit 1; }
       greeter_files
       greetd_on
       user=${SUDO_USER:-$USER}
       sudo install -m 0644 "$here/nightdrive-lock.pam" "$PAM"
       { cat "$here/config.toml"
         printf '\n# Autologin at boot (switch.sh autologin): the session starts locked (hypr/hyprland.lua, greeter/lock.qml)\n'
         # Output off the text console, as in greeter.sh
         printf '[initial_session]\ncommand = "sh -c '\''exec env NIGHTDRIVE_LOCKED_START=1 start-hyprland >/dev/null 2>&1'\''"\nuser = "%s"\n' "$user"
       } | sudo install -m 0644 /dev/stdin "$CONF"
       sudo restorecon "$CONF" "$PAM" 2>/dev/null || true
       echo "greetd enabled from the next boot, logging in $user by itself; the session starts locked." ;;
  text) text_login
       echo "greetd's text login enabled from the next boot: log in, and the desktop starts." ;;
  off) other=""
       for dm in "${OTHER_DMS[@]}"; do
         [[ -n $(systemctl list-unit-files --no-legend "$dm.service" 2>/dev/null) ]] && { other=$dm; break; }
       done
       if [[ -n $other ]]; then
         sudo systemctl disable greetd.service 2>/dev/null || true
         sudo systemctl enable --force "$other.service"
         echo "$other re-enabled from the next boot."
       else
         # Fedora Minimal has no login screen of its own
         text_login
         echo "No other login screen here: greetd's text login enabled from the next boot (log in, and the desktop starts)."
       fi ;;
  *)   echo "Usage: $0 on|autologin|text|off" >&2; exit 1 ;;
esac
systemctl status display-manager.service --no-pager 2>/dev/null | head -2 || true
readlink /etc/systemd/system/display-manager.service
