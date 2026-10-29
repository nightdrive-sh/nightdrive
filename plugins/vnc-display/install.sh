#!/bin/bash
# VNC Display: wayvnc 0.10 or later from Nightdrive's COPR, and the computer's RSA key, which VNC apps check on each
# connection (RSA-AES: they trust it on the first one, as ssh does). Adds no device: nothing listens until `vnc-display
# add`. Run as a regular user; sudo asks for the password. Safe to run again: an existing key is kept, so the devices
# don't see a new computer.
#   install.sh           installs (and upgrades an older wayvnc)
#   install.sh --check   exit 0 when installed: plugin.conf's installed= (quick, no sudo)
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
conf_dir=${XDG_CONFIG_HOME:-$HOME/.config}/nightdrive/vnc-display

# Fedora 44's wayvnc 0.9.1 exits when Hyprland fails a cursor capture (whenever the cursor grows), dropping every device,
# and macOS's Screen Sharing can't log in to it. Nightdrive's COPR has 0.10 (setup-hyprland-repo.sh, nightdrive-packages)
# until Fedora's own is new enough.
WAYVNC_MIN=0.10
wayvnc_ok() {
  local v
  v=$(rpm -q --qf '%{VERSION}' wayvnc 2>/dev/null) || return 1
  [[ $(printf '%s\n' "$WAYVNC_MIN" "$v" | sort -V | head -1) == "$WAYVNC_MIN" ]]
}

if [[ ${1:-} == --check ]]; then wayvnc_ok && [[ -f $conf_dir/rsa_key.pem ]]; exit; fi

if ! wayvnc_ok; then
  # The COPR with wayvnc in its includepkgs (an install from before it was packaged has the COPR without)
  "$repo/setup-hyprland-repo.sh" >/dev/null
  sudo dnf install -y "wayvnc >= $WAYVNC_MIN"
  wayvnc_ok || { echo "wayvnc $WAYVNC_MIN or later couldn't be installed from Nightdrive's COPR (@nightdrive/nightdrive)" >&2; exit 1; }
fi
# qrencode: the QR code in Settings › Other displays; python3-cryptography: lib/warmup.py's login to wayvnc
command -v ssh-keygen >/dev/null && command -v qrencode >/dev/null && python3 -c "import cryptography" 2>/dev/null ||
  sudo dnf install -y openssh-clients qrencode python3-cryptography
(
  umask 077
  mkdir -p "$conf_dir"
  chmod 700 "$conf_dir"
  [[ -f $conf_dir/rsa_key.pem ]] || ssh-keygen -q -m pem -t rsa -b 3072 -N "" -C "nightdrive vnc-display" -f "$conf_dir/rsa_key.pem"
  rm -f "$conf_dir/rsa_key.pem.pub"   # wayvnc reads only the private key
)
systemctl --user daemon-reload
command -v tailscale >/dev/null || echo "VNC Display listens over Tailscale: install the Tailscale plugin too (nightdrive plugins install tailscale)."
echo "VNC Display installed (wayvnc $(rpm -q --qf '%{VERSION}' wayvnc)). Add a device: vnc-display add ipad (or iphone)"
