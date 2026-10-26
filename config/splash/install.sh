#!/bin/bash
# Boot splash: the Nightdrive Plymouth theme, the GRUB menu hidden, and the splash kept until the login screen draws.
#   install.sh [on]   install and turn on (rebuilds the initramfs, needs sudo)
#   install.sh off    back to Fedora's defaults (bgrt theme, GRUB menu shown, greetd waits for Plymouth to quit)
# The GRUB menu still comes up with Esc or Shift held at boot (or F8), e.g. to pick an older kernel.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
THEME=nightdrive
DROPIN=/etc/systemd/system/greetd.service.d/nightdrive-splash.conf
WAIT_DROPIN=/etc/systemd/system/plymouth-quit-wait.service.d/nightdrive-splash.conf
CONF=/etc/plymouth/plymouthd.conf

case ${1:-on} in
  on)
    pkgs=(plymouth plymouth-plugin-two-step plymouth-theme-spinner ImageMagick jetbrains-mono-fonts)
    sudo dnf install -y "${pkgs[@]}"
    # On Fedora KDE the Plymouth plugin and the spinner theme (its images are copied below) are already there as KDE's
    # dependencies, and install leaves them so: marked as wanted, so removing KDE doesn't take them along
    sudo dnf mark user -y "${pkgs[@]}" >/dev/null
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    "$here/images.sh" "$tmp" >/dev/null
    cp "$here/$THEME.plymouth" /usr/share/plymouth/themes/spinner/{bullet,capslock,entry,keyboard,keymap-render,lock}.png "$tmp/"
    sudo rm -rf /usr/share/plymouth/themes/$THEME   # no files left from an earlier version (the title's watermark.png)
    sudo install -d -m 0755 /usr/share/plymouth/themes/$THEME
    sudo install -m 0644 "$tmp"/* /usr/share/plymouth/themes/$THEME/
    # What it was drawn from (the git trees): `nightdrive update` installs it again when that changes
    git -C "$here" rev-parse HEAD:./ HEAD:../greeter/background.jpg 2>/dev/null \
      | sudo install -m 0644 /dev/stdin /usr/share/plymouth/themes/$THEME/version
    # Device pixels: the images are made for a 2x screen and would be scaled up (blurred) otherwise
    if grep -q '^DeviceScale=' "$CONF" 2>/dev/null; then
      sudo sed -i 's/^DeviceScale=.*/DeviceScale=1/' "$CONF"
    elif grep -q '^\[Daemon\]' "$CONF" 2>/dev/null; then
      sudo sed -i '/^\[Daemon\]/a DeviceScale=1' "$CONF"
    else
      printf '[Daemon]\nDeviceScale=1\n' | sudo tee -a "$CONF" >/dev/null
    fi
    echo "Rebuilding the initramfs for the splash. Please wait, this takes a while (a minute or two)..."
    sudo plymouth-set-default-theme -R $THEME   # -R: rebuilds the initramfs
    # The kernel's own messages stay off the screen (Fedora's defaults, kept in case they were removed)
    # vt.global_cursor_default=0: no blinking cursor on the text console between the splash and the login screen
    sudo grubby --update-kernel=ALL --args="rhgb quiet vt.global_cursor_default=0"
    # Fedora's auto-hide: the menu is skipped after a boot that worked (grub-boot-success.timer marks it)
    sudo grub2-editenv - set menu_auto_hide=1
    if [[ -d /etc/greetd ]]; then
      sudo install -D -m 0644 "$here/greetd-plymouth.conf" "$DROPIN"
      sudo install -D -m 0644 "$here/plymouth-quit-wait.conf" "$WAIT_DROPIN"
      sudo systemctl daemon-reload
    fi
    echo "Done. Reboot to see it (if the boot hangs on the splash: Esc for the GRUB menu, or ctrl+alt+F3 and $0 off)."
    ;;
  off)
    sudo rm -f "$DROPIN" "$WAIT_DROPIN"; sudo systemctl daemon-reload
    sudo grub2-editenv - unset menu_auto_hide
    sudo grubby --update-kernel=ALL --remove-args="vt.global_cursor_default=0"
    sudo sed -i '/^DeviceScale=1$/d' "$CONF" 2>/dev/null || true
    sudo plymouth-set-default-theme -R bgrt
    echo "Done: Fedora's boot splash and GRUB menu are back."
    ;;
  *) echo "usage: $0 [on|off]" >&2; exit 2 ;;
esac
