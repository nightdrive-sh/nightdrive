#!/bin/bash
# RPM Fusion's repos (free, nonfree or both, as arguments), with their signing keys checked by fingerprint first. The
# release RPM comes from a mirror by URL, and dnf doesn't check the signature of a package given as a file or URL
# (localpkg_gpgcheck), so it is checked here: its key, taken out of the RPM, is imported only when it is the one
# rpmfusion.org/keys lists, and the RPM is installed only when that key signed it.
# Used by install.sh (NVIDIA driver) and plugins/airplay-receiver. Run as a regular user; sudo asks for the password.
set -euo pipefail

# The "Fedora 2020" keys, which sign the release RPMs from Fedora 33 on (https://rpmfusion.org/keys). A Fedora with a new
# key stops here with a message: check the new one there and add it.
declare -A FINGERPRINT=(
  [free]=E9A491A3DE247814E7E067EAE06F8ECDD651FF2E
  [nonfree]=79BDB88F9BBF73910FD4095B6A2AF96194843C65
)
fedora=$(rpm -E %fedora)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

for r in "$@"; do
  fpr=${FINGERPRINT[$r]:-}
  [[ -n $fpr ]] || { echo "Usage: $0 free|nonfree..." >&2; exit 2; }
  rpm -q "rpmfusion-$r-release" >/dev/null 2>&1 && continue
  pkg=$tmp/rpmfusion-$r-release.rpm
  curl -fsSL -o "$pkg" "https://mirrors.rpmfusion.org/$r/fedora/rpmfusion-$r-release-$fedora.noarch.rpm"
  # The key the RPM would install for this Fedora (a link to the year's key), unpacked without installing anything
  mkdir "$tmp/$r"; rpm2archive - < "$pkg" | tar -xzf - -C "$tmp/$r"
  key=$tmp/$r/etc/pki/rpm-gpg/RPM-GPG-KEY-rpmfusion-$r-fedora-$fedora
  # Exactly one key, the expected one: a second key in the same file would be imported along with it
  keys=$(gpg --show-keys --with-colons "$key" 2>/dev/null || true)
  got=$(awk -F: '$1=="pub" {n++} $1=="fpr" && !f {f=$10} END {if (n==1) print f}' <<<"$keys")
  if [[ $got != "$fpr" ]]; then
    echo "RPM Fusion $r: its key for Fedora $fedora isn't $fpr (https://rpmfusion.org/keys). Not installed." >&2
    exit 1
  fi
  sudo rpmkeys --import "$key"
  # Signed with that key, not just any key rpm knows (rpm 6 prints the fingerprint)
  if ! grep -qi "signature, key fingerprint: $fpr: OK" <<<"$(rpmkeys -Kv "$pkg" || true)"; then
    echo "RPM Fusion $r: the release RPM isn't signed with key $fpr. Not installed." >&2
    exit 1
  fi
  sudo dnf install -y "$pkg"
done
