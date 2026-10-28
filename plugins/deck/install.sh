#!/bin/bash
# Installs the Deck player (Spotify, https://github.com/nightdrive-sh/deck): the `deck` package from Nightdrive's COPR
# (@nightdrive/nightdrive, built for aarch64 and x86_64 by nightdrive-packages), so no Rust is compiled here and the
# System update keeps it current. Built from source with cargo instead where the package can't be had (another
# architecture, the COPR unreachable), and from a clone of one's own: DECK_SRC=~/path/to/deck ./install.sh, or
# ~/.local/src/deck linked to it (trying out changes to Deck). `nightdrive update` runs this again when that source changes.
# Either way the binary is ~/.local/bin/deck (the package's is linked there), the path the rest of the plugin calls.
# Launch: Deck (⌘Space) and Hyper+M (bin/deck-window). Needs Spotify Premium and the Client ID of your own Spotify app
# (~/.config/deck/config.toml), see Deck's README.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
src=${DECK_SRC:-$HOME/.local/src/deck}
bin=$HOME/.local/bin/deck

# A source of one's own is built, not replaced by the release in the package
own_source() { [[ -n ${DECK_SRC:-} || -L $src ]]; }

from_package() {
  rpm -q deck >/dev/null 2>&1 && return 0
  # The COPR with deck in its includepkgs (an install from before Deck was packaged has it without)
  "$repo/setup-hyprland-repo.sh" >/dev/null && sudo dnf install -y deck
}

from_source() {
  command -v cargo >/dev/null 2>&1 || sudo dnf install -y rust cargo gcc openssl-devel alsa-lib-devel
  [[ -d $src/.git ]] || git clone https://github.com/nightdrive-sh/deck "$src"
  { git -C "$src" checkout -q main && git -C "$src" pull -q --ff-only; } 2>/dev/null \
    || echo "Warning: couldn't update Deck's source in $src, building it as it is" >&2
  cargo install --locked --path "$src" --root "$HOME/.local"    # --locked: librespot does not build with the latest dependencies
  mkdir -p "$HOME/.local/share/icons/hicolor/scalable/apps"      # the package has its own in /usr/share
  install -m 644 "$src/assets/deck.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/deck.svg"
}

if ! own_source && from_package; then
  # A Deck built here before goes: ~/.local/bin comes first on PATH and would shadow the package's
  [[ -L $bin ]] || { cargo uninstall -q --root "$HOME/.local" deck 2>/dev/null || rm -f "$bin"; }
  mkdir -p "${bin%/*}"; ln -sfn /usr/bin/deck "$bin"
  how="the deck package (the System update keeps it current)"
else
  own_source || echo "The deck package couldn't be installed: building Deck from source instead (a few minutes)" >&2
  from_source
  how="built from $src"
fi

mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/deck.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Deck
Comment=Spotify player
Exec=$HOME/.local/bin/deck-window
Icon=deck
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=deck
DESK
"$HOME/.config/fuzzel/sync-apps" >/dev/null 2>&1 || true     # visibility in the launcher
echo "Deck installed: ~/.local/bin/deck, $how"
echo "Open it with Hyper+M (Caps Lock + M) or from the Launcher."
