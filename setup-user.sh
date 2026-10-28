#!/bin/bash
# This user's own setup, outside the linked configs: fonts, ble.sh, GTK settings, default apps.
# Run by install.sh and by `nightdrive update`, so an older install gets what was added since (e.g. Six Caps and ble.sh,
# 14.10.2026). Add new per-user steps here, not to install.sh. Safe to re-run; no sudo.
set -euo pipefail
repo=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT   # downloads (the fonts)

# What is fetched, pinned to what was tested: a commit, or a file's sha256. A file that changed upstream (or on the way)
# stops this script instead of being installed. A new version: its URL or commit and new sum here.
NERD_FONTS_URL=https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/NerdFontsSymbolsOnly.zip
NERD_FONTS_SHA256=8e617904b980fe3648a4b116808788fe50c99d2d495376cb7c0badbd8a564c47
SIX_CAPS_URL=https://raw.githubusercontent.com/google/fonts/90abd17b4f97671435798b6147b698aa9087612f/ofl/sixcaps/SixCaps.ttf
SIX_CAPS_SHA256=7b54a46671722fb670647c9c3951e6e618b6a9d876fc5d9ae34dfd311628ae5a
BLESH_REF=d81fd54feb0d996fdff20dca27eaf0201f7015cc   # master of 8.9.2026, in use since 14.10.2026; contrib is pinned by it

fetch() {   # URL SHA256 FILE
  curl -fsSL -o "$3" "$1" && sha256sum -c --quiet - <<<"$2  $3" || { echo "    $1: not downloaded, or not the file expected (sha256 $2)" >&2; return 1; }
}

echo "==> Nerd Fonts symbols (icons for the top bar and menus)"
fonts=$HOME/.local/share/fonts; mkdir -p "$fonts"
if ! ls "$fonts"/SymbolsNerdFont-Regular.ttf >/dev/null 2>&1; then
  fetch "$NERD_FONTS_URL" "$NERD_FONTS_SHA256" "$tmp/nf.zip"
  unzip -o -q "$tmp/nf.zip" -d "$tmp/nf" && cp "$tmp"/nf/*.ttf "$fonts"/ && fc-cache -f "$fonts"
fi
echo "==> Six Caps (the clock screensaver's font, Google Fonts)"
if ! ls "$fonts"/SixCaps.ttf >/dev/null 2>&1; then
  fetch "$SIX_CAPS_URL" "$SIX_CAPS_SHA256" "$tmp/SixCaps.ttf"
  cp "$tmp/SixCaps.ttf" "$fonts"/ && fc-cache -f "$fonts"
fi

echo "==> ble.sh (bash: history suggestions while typing, syntax colours; config/bash/00-blesh.sh loads it)"
blesh_src=$HOME/.local/src/ble.sh
# Built again when the commit above changes (an install from before 28.10.2026 has master of its day: it moves to it)
if [[ $(git -C "$blesh_src" rev-parse HEAD 2>/dev/null) != "$BLESH_REF" || ! -e $HOME/.local/share/blesh/ble.sh ]]; then
  [[ -d $blesh_src/.git ]] || { git init -q "$blesh_src" && git -C "$blesh_src" remote add origin https://github.com/akinomyoga/ble.sh.git; }
  git -C "$blesh_src" fetch -q --depth 1 origin "$BLESH_REF"
  git -C "$blesh_src" checkout -q "$BLESH_REF"
  git -C "$blesh_src" submodule update -q --init --recursive --depth 1
  make -C "$blesh_src" -s install PREFIX="$HOME/.local"
fi

echo "==> GTK: no KDE 1.7x text scaling, Papirus icons, the freedesktop sounds (Plasma's ocean is gone with it)"
for v in 3.0 4.0; do
  f=$HOME/.config/gtk-$v/settings.ini
  [[ -f $f ]] || { mkdir -p "$(dirname "$f")"; printf '[Settings]\n' > "$f"; }
  for kv in 'gtk-xft-dpi=98304' 'gtk-icon-theme-name=Papirus-Dark' 'gtk-decoration-layout=:' 'gtk-cursor-theme-name=breeze_cursors' 'gtk-application-prefer-dark-theme=1' \
            'gtk-sound-theme-name=freedesktop'; do
    k=${kv%%=*}
    if grep -q "^$k=" "$f"; then sed -i "s|^$k=.*|$kv|" "$f"; else echo "$kv" >> "$f"; fi
  done
done
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.wm.preferences button-layout ':' 2>/dev/null || true
gsettings set org.gnome.desktop.sound theme-name 'freedesktop' 2>/dev/null || true
# No "Connection established" from nm-applet each time Wi-Fi connects (a Mac doesn't say either); losing it still shows
gsettings set org.gnome.nm-applet disable-connected-notifications true 2>/dev/null || true

echo "==> Default apps: images open in Loupe (instead of the browser); Markdown in Apostrophe, if chosen (its installer)"
# Only while images are unchosen: this runs at every update, and would undo a choice in Settings › Apps › Default apps (the same
# script, which writes ~/.config/mimeapps.list itself: no xdg-mime, which from Plasma (install.sh) went to Qt5's qtpaths)
"$repo/config/hypr/scripts/default-apps" set images org.gnome.Loupe.desktop --if-unset
# The terminal: kitty (Nightdrive's settings and colours) until another is chosen; unset, xdg-terminal-exec would pick any
"$repo/config/hypr/scripts/default-apps" set terminal kitty.desktop --if-unset

echo "==> Webapps: the window class Chromium gives them (their notifications, the launcher and Share find the window)"
"$repo/config/hypr/scripts/webapp-add" --fix-classes
# and their links to other sites to the default browser
"$repo/config/hypr/scripts/webapp-links" setup
