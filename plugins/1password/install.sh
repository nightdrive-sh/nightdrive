#!/bin/bash
# 1Password: the app (the tarball for this machine's architecture, signature verified) and the op CLI (1Password's RPM
# repo). Starts at login (launcher › Settings › Apps › Startup): the SSH agent, `op` and the launcher's Passwords need it running.
# Run as a regular user; sudo asks for the password.
set -euo pipefail
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# 1Password publishes tarballs for both: aarch64 (the MacBook) and x86_64
case $(uname -m) in
  aarch64) arch=aarch64 ;;
  x86_64) arch=x86_64 ;;
  *) echo "1Password has no Linux build for $(uname -m)" >&2; exit 1 ;;
esac
if [[ ! -x /opt/1Password/1password ]]; then
  url=https://downloads.1password.com/linux/tar/stable/$arch/1password-latest.tar.gz
  curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp/1p.tar.gz" "$url"
  curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp/1p.tar.gz.sig" "$url.sig"
  curl --proto '=https' --tlsv1.2 -fsSL -o "$tmp/key.asc" https://downloads.1password.com/linux/keys/1password.asc
  export GNUPGHOME="$tmp/gnupg"; mkdir -m700 "$GNUPGHOME"
  gpg -q --import "$tmp/key.asc"
  gpg --fingerprint 2>/dev/null | grep -q '3FEF 9748 469A DBE1 5DA7  CA80 AC2D 6274 2012 EA22' \
    || { echo "1Password key fingerprint does not match, aborting"; exit 1; }
  gpg --verify "$tmp/1p.tar.gz.sig" "$tmp/1p.tar.gz"
  mkdir "$tmp/x"; tar xzf "$tmp/1p.tar.gz" -C "$tmp/x"
  sudo rm -rf /opt/1Password
  sudo cp -a "$tmp"/x/1password-* /opt/1Password
  sudo chown -R root:root /opt/1Password
  sudo sh /opt/1Password/after-install.sh
fi
sudo tee /etc/yum.repos.d/1password.repo >/dev/null <<'REPO'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
REPO
sudo dnf install -y 1password-cli

# Start at login. A fresh install seeds this on the first login (hypr/scripts/autostart); an install that already has
# its list (1Password added later from the launcher) gets it here.
"$HOME/.config/hypr/scripts/autostart" add com.onepassword.OnePassword.desktop
"$HOME/.config/fuzzel/sync-apps" >/dev/null 2>&1 || true
echo "1Password installed. Firefox: the 1Password extension from addons.mozilla.org."
