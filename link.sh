#!/bin/bash
# Symlinks the config/ directories into ~/.config and copies the fonts.
# An existing directory is moved to <name>.bak-<timestamp>. Safe to re-run.
set -euo pipefail
repo=$(cd "$(dirname "$0")" && pwd)

link() {
  local src=$1 dst=$2
  if [[ -L $dst && $(readlink -f "$dst") == $(readlink -f "$src") ]]; then echo "ok          $dst"; return; fi
  if [[ -e $dst || -L $dst ]]; then mv "$dst" "$dst.bak-$(date +%s)"; fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  echo "linked      $dst -> $src"
}

# Links into the repo whose file is gone (it moved, e.g. into the plugin folders on 18.10.2026 or with a branch switch,
# or was removed) go before anything is linked again: link() would move a dead one aside as a .bak file, which in
# ~/.local/bin is a command and in ~/.config/systemd/user a unit. Only where link.sh (and plugins installed) links, and
# only dead links into the repo (or an external plugin's folder, also a removed one's): a link of your own to somewhere
# else stays. A Nightdrive unit's dead .wants link goes too (enable points it at the unit's file in the repo, not at the
# link), and the unit is enabled again once its new link is in place (below): otherwise it wouldn't start at the next
# login.
external=$HOME/.local/share/nightdrive/plugins   # plugins from elsewhere (nightdrive plugins add)
reenable=()
for l in "$HOME"/.config/* "$HOME"/.config/{systemd/user,keyd,alsa,voxtype,gtk-3.0,gtk-4.0}/* \
  "$HOME"/.config/systemd/user/*.wants/* "$HOME"/.config/fontconfig/conf.d/* "$HOME"/.config/wireplumber/wireplumber.conf.d/* \
  "$HOME"/.local/bin/* "$HOME"/.local/share/* "$HOME"/.local/share/{applications,nightdrive,easyeffects/output,voxtype/quickshell}/* \
  "$HOME"/.local/share/nautilus-python/extensions/* "$HOME"/.bashrc.d/* "$HOME"/.cache/nightdrive/plugins.d/icons/*; do
  [[ -L $l && ! -e $l ]] || continue
  t=$(readlink "$l")
  if [[ $l == *.wants/* && ${l##*/} == nightdrive-* ]] || [[ $t == "$repo/"* || $t == "$external/"* ]]; then
    [[ $l == *.wants/* ]] && reenable+=("${l##*/}")
    rm "$l" && echo "removed     $l (its file is gone)"
  fi
done

for d in hypr hyprpolkitagent topbar fuzzel kitty ghostty alacritty foot quickshell screensaver greeter welcome; do   # hyprpolkitagent: the polkit password prompt's size; greeter: the lock at startup (greeter/lock.qml) and the preview; welcome: Welcome to Nightdrive
  link "$repo/config/$d" "$HOME/.config/$d"
done
# foot's config includes your local.ini and won't start without one
[[ -e $repo/config/foot/local.ini ]] || : > "$repo/config/foot/local.ini"
# Waybar drew the top bar until 13.10.2026; its config is gone from the repo (a leftover config/waybar only holds
# the old generated bar.css and your local.css), so the link goes
[[ -L $HOME/.config/waybar && $(readlink "$HOME/.config/waybar") == "$repo/config/waybar" ]] && rm "$HOME/.config/waybar" && echo "removed     $HOME/.config/waybar"
# The top bar used to be Waybar (config/waybar): drop its old link
[[ -L $HOME/.config/waybar && ! -e $HOME/.config/waybar ]] && rm "$HOME/.config/waybar" && echo "removed     $HOME/.config/waybar (old link)"
# Mako showed the notifications until 14.10.2026; Quickshell does now (quickshell/Notifs.qml). Its old link goes, and the
# unit is masked: D-Bus activation would start mako for the first notification and take the name from Quickshell.
[[ -L $HOME/.config/mako && ! -e $HOME/.config/mako ]] && rm "$HOME/.config/mako" && echo "removed     $HOME/.config/mako (old link)"
systemctl --user mask --now mako.service >/dev/null 2>&1 || true
# The share window (Screen Mirroring, Cast, video calls): xdg-desktop-portal-hyprland runs our picker (hypr/scripts/share-picker,
# quickshell/SharePicker.qml). Written here: the path must be absolute, and the file is git-ignored. Read when xdph starts.
xdph="$repo/config/hypr/xdph.conf"
want="screencopy {
    custom_picker_binary = $HOME/.config/hypr/scripts/share-picker
}"
if [[ $(cat "$xdph" 2>/dev/null) != "$want" ]]; then
  printf '%s\n' "$want" > "$xdph"; echo "wrote       $xdph"
  systemctl --user try-restart xdg-desktop-portal-hyprland >/dev/null 2>&1 || true
fi
link "$repo/config/gtk-4.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"   # GTK 4 / libadwaita apps (Nautilus) in the theme's colours
link "$repo/config/gtk-3.0/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
# Apostrophe is a Flatpak: it reads its own config dir (plugins/apostrophe/install.sh lets the sandbox read config/gtk-4.0)
link "$repo/config/gtk-4.0/apostrophe.css" "$HOME/.var/app/org.gnome.gitlab.somas.Apostrophe/config/gtk-4.0/gtk.css"
link "$repo/config/fontconfig/conf.d/10-nerd-font-symbols.conf" "$HOME/.config/fontconfig/conf.d/10-nerd-font-symbols.conf"

# EasyEffects (headphone EQ): presets as links, settings as a copy (KConfig would replace a link with a regular file)
mkdir -p "$HOME/.local/share/easyeffects/output" "$HOME/.config/easyeffects/db"
for f in "$repo"/config/easyeffects/output/*.json; do link "$f" "$HOME/.local/share/easyeffects/output/$(basename "$f")"; done
cp -n "$repo/config/easyeffects/db/easyeffectsrc" "$HOME/.config/easyeffects/db/easyeffectsrc"

link "$repo/config/wireplumber/wireplumber.conf.d/51-bt-no-headset-autoswitch.conf" "$HOME/.config/wireplumber/wireplumber.conf.d/51-bt-no-headset-autoswitch.conf"   # don't make the BT headset mic the default

link "$repo/config/applications/nm-connection-editor.desktop" "$HOME/.local/share/applications/nm-connection-editor.desktop"   # Fedora ships none
# macbook_mic alias for dictation (voxtype): the MacBook's mic on Apple Silicon, the default mic elsewhere
if [[ $("$repo/config/hypr/scripts/platform" name) == asahi ]]; then asound=asoundrc; else asound=asoundrc.generic; fi
link "$repo/config/alsa/$asound" "$HOME/.config/alsa/asoundrc"
# Mac Keyboard Shortcuts plugin (plugins/keyd): keyd-application-mapper's per-app keys (the link from before the folder,
# config/keyd, went with the dead links above). The mapper dies when its app.conf goes for a moment (a branch switch
# moves the file), and the plugin's hyprland.lua starts it only with Hyprland: it starts again here while the plugin is
# on. It reads the windows from Hyprland, so only inside a Hyprland session.
if [[ -f /etc/keyd/default.conf ]]; then
  link "$repo/plugins/keyd/app.conf" "$HOME/.config/keyd/app.conf"
  # The mapper is a Python script: its command line starts with python3 and its path. Matching the name anywhere would
  # count any process that mentions it (a grep, an editor), and another user's mapper doesn't read this app.conf.
  if [[ ! -e $HOME/.local/state/nightdrive/plugins-off/keyd && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \
    && ! pgrep -u "$UID" -f '^([^ ]*/)?python3?[0-9.]* ([^ ]*/)?keyd-application-mapper( |$)' >/dev/null; then
    setsid sg keyd -c "keyd-application-mapper -d" </dev/null >/dev/null 2>&1 &
    echo "started     keyd-application-mapper"
  fi
fi
# VS Code plugin (plugins/vscode): its Wayland flags. The link from before the folder (config/code-flags.conf, 19.10.2026)
# went with the dead links above.
command -v code >/dev/null && link "$repo/plugins/vscode/code-flags.conf" "$HOME/.config/code-flags.conf"
# Deck's desktop file from before 23.10.2026 runs deck-open (in hypr/scripts before its folder, 18.10.2026), now
# deck-window in plugins/deck/bin (~/.local/bin)
deck_desktop=$HOME/.local/share/applications/deck.desktop
if [[ -f $deck_desktop ]] && grep -q '^Exec=.*deck-open' "$deck_desktop"; then
  sed -i "s#^Exec=.*deck-open#Exec=$HOME/.local/bin/deck-window#" "$deck_desktop" && echo "fixed       $deck_desktop"
fi
# Web apps from before 19.10.2026 lack --no-first-run (webapp-add): each has a Chromium profile of its own, so each was a
# first run, and Fedora's /etc/chromium/master_preferences opened its first_run_tabs page in a window of its own
for f in "$HOME"/.local/share/applications/webapp-*.desktop; do
  [[ -f $f ]] && grep -q '^Exec=chromium-browser .*--app=' "$f" && ! grep -q -- '--no-first-run' "$f" || continue
  sed -i 's#^Exec=chromium-browser #Exec=chromium-browser --no-first-run #' "$f" && echo "fixed       $f"
done

# Session target: brings up graphical-session.target, which xdg-desktop-portal needs (started by hyprland.lua)
link "$repo/config/systemd/user/nightdrive-session.target" "$HOME/.config/systemd/user/nightdrive-session.target"
# Update check: every 6 h a fetch, and a notification when new commits are waiting (nightdrive update check).
# Snippets and crash reports: linked only, started when turned on (nightdrive snippets enable; launcher › Settings ›
# Notifications). The plugin folders' units are linked below.
units=(nightdrive-update-check.service nightdrive-update-check.timer nightdrive-snippets.service
       nightdrive-crash-reports.service)
for u in "${units[@]}"; do link "$repo/config/systemd/user/$u" "$HOME/.config/systemd/user/$u"; done

# ⌘Enter (terminal) and ⌘⌥Enter (Claude Code) open in ~/Projects, and kitty fails to start in a folder that doesn't exist
mkdir -p "$HOME/Projects"

# Claude Code's notifications come from "Claude" with the session's topic, a click goes to its window, and a permission
# request has Allow and Deny (hypr/scripts/claude-notify: Notification and PermissionRequest hooks in
# ~/.claude/settings.json, each added once and kept beside your own hooks). Its own terminal notification (kitty's, the
# same for every session) goes off, unless you picked a channel.
cn='~/.config/hypr/scripts/claude-notify'
cs="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"; [[ -s $cs ]] || echo '{}' > "$cs"
for ev in Notification PermissionRequest; do
  jq -e --arg e "$ev" --arg c "$cn" '[.hooks[$e][]?.hooks[]?.command] | index($c)' "$cs" >/dev/null 2>&1 && continue
  jq --arg e "$ev" --arg c "$cn" '.hooks[$e] += [{matcher: "", hooks: [{type: "command", command: $c}]}]' "$cs" > "$cs.tmp" \
    && mv "$cs.tmp" "$cs" || rm -f "$cs.tmp"
done
cg="$HOME/.claude.json"
if [[ -s $cg ]] && jq -e '.preferredNotifChannel == null or .preferredNotifChannel == "auto"' "$cg" >/dev/null 2>&1; then
  jq '.preferredNotifChannel = "notifications_disabled"' "$cg" > "$cg.tmp" && mv "$cg.tmp" "$cg" || rm -f "$cg.tmp"
fi

# The nightdrive command (bin/nightdrive)
mkdir -p "$HOME/.local/bin"
for f in "$repo"/bin/*; do link "$f" "$HOME/.local/bin/$(basename "$f")"; done

# Plugin folders (plugins/<id>/ and the external ones, see plugins/README.md): their commands (bin/), user units
# (systemd/) and Files extensions (nautilus-python/, which show only while the plugin is on), whether installed or not: an
# installer runs its own command and enables its unit. A unit that now comes
# from somewhere else is restarted if it runs, so it runs the new file. An external one whose id the repo already has is
# skipped, as bin/nightdrive skips it, and its files never replace one that is already there (link() would move that
# aside): it can't take over the repo's commands or units.
restart=()
declare -A owner=()   # a plugin folder's unit -> the plugin's id (one that is off isn't started below)
taken=" $(grep -vE '^\s*(#|$)' "$repo/plugins.txt" | cut -d'|' -f1 | tr '\n' ' ')"
held() {   # $2 is there and isn't $1's link, while $1 is an external plugin's file
  [[ $1 == "$external/"* && ( -e $2 || -L $2 ) && $(readlink -f "$2") != "$(readlink -f "$1")" ]] || return 1
  echo "skipped     $2 (already there, not replaced by the external plugin's)"
}
for d in "$repo"/plugins/*/ "$external"/*/; do
  [[ -f $d/plugin.conf && $taken != *" $(basename "$d") "* ]] || continue
  taken+="$(basename "$d") "
  for f in "$d"bin/*; do
    [[ -f $f ]] || continue
    held "$f" "$HOME/.local/bin/$(basename "$f")" || link "$f" "$HOME/.local/bin/$(basename "$f")"
  done
  for f in "$d"nautilus-python/*.py; do
    [[ -f $f ]] || continue
    held "$f" "$HOME/.local/share/nautilus-python/extensions/$(basename "$f")" \
      || link "$f" "$HOME/.local/share/nautilus-python/extensions/$(basename "$f")"
  done
  for f in "$d"systemd/*; do
    [[ -f $f ]] || continue
    u=$HOME/.config/systemd/user/$(basename "$f")
    held "$f" "$u" && continue
    [[ $(readlink "$u") == "$f" ]] || restart+=("$(basename "$f")")
    link "$f" "$u"
    units+=("$(basename "$f")"); owner[$(basename "$f")]=$(basename "$d")
  done
done
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now nightdrive-update-check.timer 2>/dev/null || true
for u in "${reenable[@]}"; do
  [[ -e $HOME/.config/systemd/user/$u ]] && systemctl --user enable "$u" 2>/dev/null && echo "enabled     $u (again)"
done
(( ${#restart[@]} )) && { systemctl --user try-restart "${restart[@]}" 2>/dev/null || true; }
# A unit that failed stays failed, and neither enable nor try-restart starts it: e.g. one that systemd kept restarting on
# its old path until a branch switch removed the file hit the start limit ("Start request repeated too quickly"). An
# enabled one starts again (a static one, like the update check's service, is the timer's to start), unless its plugin
# is off (nightdrive plugins off).
for u in "${units[@]}" "${reenable[@]}"; do
  [[ -n ${owner[$u]:-} && -e $HOME/.local/state/nightdrive/plugins-off/${owner[$u]} ]] && continue
  [[ $(systemctl --user is-enabled "$u" 2>/dev/null) == enabled ]] && systemctl --user -q is-failed "$u" 2>/dev/null || continue
  systemctl --user reset-failed "$u" 2>/dev/null || true
  if systemctl --user start "$u" 2>/dev/null; then echo "started     $u (it had failed)"
  else echo "failed      $u: see systemctl --user status $u"; fi
done

link "$repo/wallpapers" "$HOME/.local/share/wallpapers"   # wallpapers (chosen via: launcher › Settings › Background, hypr/scripts/wallpaper)
link "$repo/sounds" "$HOME/.local/share/nightdrive/sounds"   # notification sounds (launcher › Settings › Notifications, hypr/scripts/sounds)
# Fedora Asahi's steam package installs a steam locomotive as the hicolor "steam" icon (the launcher and the bar fall back
# to hicolor): Papirus's Steam logo goes in front of it in the user's hicolor
papirus_steam=/usr/share/icons/Papirus/32x32/apps/steam.svg
[[ -f $papirus_steam ]] && link "$papirus_steam" "$HOME/.local/share/icons/hicolor/scalable/apps/steam.svg"

# Bash: prompt, history, ble.sh (Fedora's ~/.bashrc sources ~/.bashrc.d/*)
mkdir -p "$HOME/.bashrc.d"
for f in "$repo"/config/bash/*.sh; do link "$f" "$HOME/.bashrc.d/$(basename "$f")"; done

# Voxtype (speech to text, F5): config. The binaries ~/.local/bin/voxtype{,-onnx} and models ~/.local/share/voxtype/models are installed by hand (see docs/dictation.md).
mkdir -p "$HOME/.config/voxtype"
link "$repo/config/voxtype/config.toml" "$HOME/.config/voxtype/config.toml"
mkdir -p "$HOME/.local/share/voxtype/quickshell"
link "$repo/config/voxtype/OsdSurface.qml" "$HOME/.local/share/voxtype/quickshell/OsdSurface.qml"   # modified OSD (top centre, no dimming)
for f in listening.wav done.wav; do link "$repo/config/voxtype/$f" "$HOME/.local/share/voxtype/quickshell/$f"; done   # its sound cues (found next to it)

# Firefox: userChrome.css (tabs below the address bar) into the default profile, and user.js (enables userChrome.css)
# with the choices of launcher › Settings › Apps › Firefox: firefox-prefs writes it, as it isn't a link
for p in "$HOME"/.config/mozilla/firefox/*.default-release; do
  [[ -d $p ]] || continue
  mkdir -p "$p/chrome"
  link "$repo/config/firefox/userChrome.css" "$p/chrome/userChrome.css"
  link "$repo/config/firefox/userContent.css" "$p/chrome/userContent.css"
done
"$repo/config/hypr/scripts/firefox-prefs" apply

# Thunderbird: Nightdrive's userChrome.css (Lucide icons are read straight from the repo's icons/ directory), user.js
# and the folder-pane toggle button add-on. The toolbar button order lives in xulstore.json (see docs/thunderbird.md).
for p in "$HOME"/.config/thunderbird/*.default-release; do
  [[ -d $p ]] || continue
  mkdir -p "$p/chrome" "$p/extensions"
  link "$repo/config/thunderbird/userChrome.css" "$p/chrome/userChrome.css"
  link "$repo/config/thunderbird/userContent.css" "$p/chrome/userContent.css"
  link "$repo/config/thunderbird/user.js" "$p/user.js"
  sed "s|@DIR@|$repo/config/thunderbird|" "$repo/config/thunderbird/icons.css.in" > "$p/chrome/nightdrive-icons.css"
  xpi="$p/extensions/folderpane-toggle@jokela-night.xpi"
  rm -f "$xpi"
  (cd "$repo/config/thunderbird/folderpane-toggle" && zip -qj "$xpi" manifest.json background.js sidebar.svg)
  echo "built       $xpi"
done

# The installed parts' list, and the installed plugin folders' parts gathered where the desktop reads them
"$repo/bin/nightdrive" plugins installed >/dev/null 2>&1 || true

mkdir -p "$HOME/.local/share/fonts"
cp -u "$repo"/fonts/*.ttf "$HOME/.local/share/fonts/"   # -u: an updated font in the repo replaces the old one
fc-cache -f
