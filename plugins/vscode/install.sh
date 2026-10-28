#!/bin/bash
# VS Code (Microsoft's RPM repo, aarch64) + Wayland flags. Run as a regular user; sudo asks for the password.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)

# Verify the Microsoft key fingerprint before importing it
key=$(mktemp); trap 'rm -f "$key"' EXIT
curl -fsSL -o "$key" https://packages.microsoft.com/keys/microsoft.asc
gpg --show-keys --with-colons "$key" | grep -q '^fpr:::::::::BC528686B50D79E339D3721CEB3E94ADBE1229CF:' \
  || { echo "Microsoft key fingerprint does not match, aborting"; exit 1; }
sudo rpm --import "$key"

sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
sudo dnf install -y code

# Wayland: sharp text and correct scaling (2.0). link.sh keeps the link while VS Code is installed.
mkdir -p "$HOME/.config"
ln -sfn "$here/code-flags.conf" "$HOME/.config/code-flags.conf"
"$HOME/.config/fuzzel/sync-apps"
echo "Done: run 'code' or find it in the Launcher (⌘Space)."
