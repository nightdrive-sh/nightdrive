#!/bin/bash
# Garage's installer (plugin.conf): qemu and the UEFI firmware for this machine's architecture, as lib/arch.sh names
# them (an Asahi Mac's aarch64 or a PC's x86_64), then Garage among the desktop's apps (`garage install`: its desktop
# entry and icon, which plugin.conf's installed test looks for). Safe to run again. The VMs are made in the window.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

die() { echo "$*" >&2; exit 1; }     # lib/arch.sh's, on an architecture Garage doesn't run VMs on
. lib/arch.sh
[[ -e /dev/kvm ]] || echo "Warning: no /dev/kvm here, so the VMs would have no hardware virtualization" >&2

# shellcheck disable=SC2086    # PACKAGES is a list
sudo dnf install -y $PACKAGES jq

bin/garage install
"$HOME/.config/fuzzel/sync-apps" >/dev/null 2>&1 || true     # visibility in the launcher
echo "Garage is ready: Hyper+G (Caps Lock + G) or the launcher opens it, and its first VM is ⌘N there."
