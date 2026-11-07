#!/bin/bash
# Installs the Deck player (Spotify, https://github.com/nightdrive-sh/deck): the `deck` package from Nightdrive's COPR
# (@nightdrive/nightdrive, built for aarch64 and x86_64 by nightdrive-packages), so no Rust is compiled here and the
# System update keeps it current. Built from source with cargo instead where the package can't be had (another
# architecture, the COPR unreachable): with a warning first, at the release pinned below. And from a clone of one's own:
# DECK_SRC=~/path/to/deck ./install.sh, or ~/.local/src/deck linked to it (trying out changes to Deck), built as it is.
# `nightdrive update` runs this again when that source changes, or the pin.
# Either way the binary is ~/.local/bin/deck (the package's is linked there), the path the rest of the plugin calls.
# Launch: Deck (⌘Space) and Hyper+M (bin/deck-window). Needs Spotify Premium and the Client ID of your own Spotify app
# (~/.config/deck/config.toml), see Deck's README.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
src=${DECK_SRC:-$HOME/.local/src/deck}
bin=$HOME/.local/bin/deck
# The source build's release: a build runs Deck's code (build.rs too) as the user, so it is a tagged release's commit,
# never whatever main is that day. Moved with Deck's releases (git -C ~/Projects/deck rev-parse 'vX.Y.Z^{commit}');
# `nightdrive update` rebuilds a Deck built from it when this changes (update.sh reads the line); `nightdrive release`
# warns when Deck has a newer release (release-pins reads both lines).
DECK_REF=4d17cd4dbef8e8cb3405151b713aa69f473887cc   # v0.1.2 of 29.10.2026
DECK_TAG=v0.1.2
DECK_REPO=https://github.com/nightdrive-sh/deck

# A source of one's own is built, not replaced by the release in the package
own_source() { [[ -n ${DECK_SRC:-} || -L $src ]]; }

from_package() {
  rpm -q deck >/dev/null 2>&1 && return 0
  # The COPR with deck in its includepkgs (an install from before Deck was packaged has it without)
  "$repo/setup-hyprland-repo.sh" >/dev/null && sudo dnf install -y deck
}

# Said where it can't be missed, before anything is compiled: on a terminal with a pause to stop it (an update without
# one goes on, the lines stay in its output)
warn_source() {
  {
    echo
    echo "!! Deck: the deck package couldn't be installed (none for $(uname -m), or Nightdrive's COPR unreachable)."
    echo "!! Building Deck $DECK_TAG from source instead: commit ${DECK_REF:0:12} of $DECK_REPO, compiled"
    echo "!! here as you with Rust (installed with dnf if missing). This takes a few minutes."
    echo
  } >&2
  [[ -t 0 ]] || return 0
  read -r -t 15 -p "Enter builds it now, Ctrl+C stops (going on in 15 s) " || echo >&2
}

# The clone at DECK_REF, detached: an update's pull leaves it there (it follows no branch). An older clone on main moves
# to it. Git checks each object against its hash, so HEAD at the full commit id is the release's source.
pinned_source() {
  [[ -d $src/.git ]] || { mkdir -p "$src" && git init -q "$src" && git -C "$src" remote add origin "$DECK_REPO"; }
  git -C "$src" cat-file -e "$DECK_REF^{commit}" 2>/dev/null || git -C "$src" fetch -q --depth 1 origin "$DECK_REF"
  git -C "$src" checkout -q --detach "$DECK_REF"
  [[ $(git -C "$src" rev-parse HEAD) == "$DECK_REF" ]] \
    || { echo "Deck's source in $src isn't at $DECK_TAG ($DECK_REF): not building it" >&2; return 1; }
}

from_source() {
  command -v cargo >/dev/null 2>&1 || sudo dnf install -y rust cargo gcc openssl-devel alsa-lib-devel
  own_source || pinned_source    # one's own is built as it is: an update pulls it
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
  own_source || warn_source
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
