#!/bin/bash
# Installs Claude Code (~/.local/bin/claude) as Anthropic's installer (https://claude.ai/install.sh) does, but checked:
# that script comes unsigned from the same server as the binary, so instead the release's manifest is verified with
# Anthropic's release signing key, pinned here by fingerprint, and the binary against the manifest's sha256
# (https://code.claude.com/docs/en/setup › Binary integrity and code signing). Then the binary's own `claude install`
# sets it up and keeps it up to date from then on. Used by install.sh and `nightdrive update`; no sudo.
set -euo pipefail

BASE=https://downloads.claude.ai/claude-code-releases
KEY_URL=https://downloads.claude.ai/keys/claude-code.asc
# "Anthropic Claude Code Release Signing <security@anthropic.com>", as the docs print it
KEY_FINGERPRINT=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

case $(uname -m) in
  x86_64) platform=linux-x64 ;;
  aarch64) platform=linux-arm64 ;;
  *) echo "Claude Code: no build for $(uname -m)" >&2; exit 1 ;;
esac
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export GNUPGHOME=$tmp/gnupg; mkdir -m 700 "$GNUPGHOME"   # a keyring of its own: the user's stays as it is

version=$(curl -fsSL "$BASE/latest")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Claude Code: no version from $BASE/latest" >&2; exit 1; }
curl -fsSL -o "$tmp/key.asc" "$KEY_URL"
curl -fsSL -o "$tmp/manifest.json" "$BASE/$version/manifest.json"
curl -fsSL -o "$tmp/manifest.json.sig" "$BASE/$version/manifest.json.sig"
gpg -q --import "$tmp/key.asc" 2>/dev/null
# VALIDSIG's last field is the signing key's primary fingerprint: any other key, even one in the same file, fails here
status=$(gpg --status-fd 1 --verify "$tmp/manifest.json.sig" "$tmp/manifest.json" 2>/dev/null || true)
if ! grep -q "^\[GNUPG:\] VALIDSIG .* $KEY_FINGERPRINT\$" <<<"$status"; then
  echo "Claude Code $version: its manifest isn't signed with key $KEY_FINGERPRINT. Not installed." >&2
  exit 1
fi
# The signed manifest must be the one for the version asked for (it names its own)
sum=$(python3 -I -c 'import json, sys
m = json.load(open(sys.argv[1]))
if m.get("version") == sys.argv[2]: print(m.get("platforms", {}).get(sys.argv[3], {}).get("checksum", ""))' \
  "$tmp/manifest.json" "$version" "$platform")
[[ $sum =~ ^[0-9a-f]{64}$ ]] || { echo "Claude Code $version: no $platform build in its manifest" >&2; exit 1; }

curl -fsSL -o "$tmp/claude" "$BASE/$version/$platform/claude"
echo "$sum  $tmp/claude" | sha256sum -c --quiet - || { echo "Claude Code $version: the download doesn't match its manifest" >&2; exit 1; }
chmod +x "$tmp/claude"
"$tmp/claude" install
