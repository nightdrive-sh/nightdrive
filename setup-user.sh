#!/bin/bash
# This user's own setup, outside the linked configs: fonts, ble.sh, GTK settings, default apps.
# Run by install.sh and by `nightdrive update`, so an older install gets what was added since (e.g. Six Caps and ble.sh,
# 14.10.2026). Add new per-user steps here, not to install.sh. Safe to re-run; no sudo.
set -euo pipefail
repo=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT   # downloads (Nerd Fonts)

echo "==> Nerd Fonts symbols (icons for the top bar and menus)"
fonts=$HOME/.local/share/fonts; mkdir -p "$fonts"
if ! ls "$fonts"/SymbolsNerdFont-Regular.ttf >/dev/null 2>&1; then
  curl -fsSL -o "$tmp/nf.zip" https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/NerdFontsSymbolsOnly.zip
  unzip -o -q "$tmp/nf.zip" -d "$tmp/nf" && cp "$tmp"/nf/*.ttf "$fonts"/ && fc-cache -f "$fonts"
fi
echo "==> Six Caps (the clock screensaver's font, Google Fonts)"
if ! ls "$fonts"/SixCaps.ttf >/dev/null 2>&1; then
  curl -fsSL -o "$fonts/SixCaps.ttf" https://raw.githubusercontent.com/google/fonts/main/ofl/sixcaps/SixCaps.ttf && fc-cache -f "$fonts"
fi

echo "==> ble.sh (bash: history suggestions while typing, syntax colours; config/bash/00-blesh.sh loads it)"
blesh_src=$HOME/.local/src/ble.sh
[[ -d $blesh_src/.git ]] || git clone -q --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git "$blesh_src"
[[ -e $HOME/.local/share/blesh/ble.sh ]] || make -C "$blesh_src" -s install PREFIX="$HOME/.local"

echo "==> GTK: no KDE 1.7x text scaling, Papirus icons"
for v in 3.0 4.0; do
  f=$HOME/.config/gtk-$v/settings.ini
  [[ -f $f ]] || { mkdir -p "$(dirname "$f")"; printf '[Settings]\n' > "$f"; }
  for kv in 'gtk-xft-dpi=98304' 'gtk-icon-theme-name=Papirus-Dark' 'gtk-decoration-layout=:' 'gtk-cursor-theme-name=breeze_cursors' 'gtk-application-prefer-dark-theme=1'; do
    k=${kv%%=*}
    if grep -q "^$k=" "$f"; then sed -i "s|^$k=.*|$kv|" "$f"; else echo "$kv" >> "$f"; fi
  done
done
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.wm.preferences button-layout ':' 2>/dev/null || true
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
