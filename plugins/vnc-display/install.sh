#!/bin/bash
# VNC Display: wayvnc from Fedora, and the computer's RSA key, which VNC apps check on each connection (RSA-AES: they
# trust it on the first one, as ssh does). Adds no device: nothing listens until `vnc-display add`. Run as a regular
# user; sudo asks for the password. Safe to run again: an existing key is kept, so the devices don't see a new computer.
set -euo pipefail

conf_dir=${XDG_CONFIG_HOME:-$HOME/.config}/nightdrive/vnc-display

command -v wayvnc >/dev/null && command -v ssh-keygen >/dev/null || sudo dnf install -y wayvnc openssh-clients
(
  umask 077
  mkdir -p "$conf_dir"
  chmod 700 "$conf_dir"
  [[ -f $conf_dir/rsa_key.pem ]] || ssh-keygen -q -m pem -t rsa -b 3072 -N "" -C "nightdrive vnc-display" -f "$conf_dir/rsa_key.pem"
  rm -f "$conf_dir/rsa_key.pem.pub"   # wayvnc reads only the private key
)
systemctl --user daemon-reload
command -v tailscale >/dev/null || echo "VNC Display listens over Tailscale: install the Tailscale plugin too (nightdrive plugins install tailscale)."
echo "VNC Display installed. Add a device: vnc-display add ipad (or iphone)"
