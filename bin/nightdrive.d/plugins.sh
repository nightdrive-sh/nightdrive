# shellcheck shell=bash
# Part of the nightdrive command (sourced by bin/nightdrive): reading the plugins, Nightdrive's apps among them. Their
# list (plugin_rows, plugins), the terminal table, the installed ones that are on, their packages, finding one by id or
# name. Everything else that deals with plugins (install, off/on, add, remove) is built on these.

# Plugins: the lines of plugins.txt, and plugin folders with a plugin.conf (the same fields as key=value; both formats
# are explained in plugins.txt): the repo's plugins/<id>/ and the external ones in ~/.local/share/nightdrive/plugins/<id>/.
# Ids are unique: a folder with an id already taken (by plugins.txt, the repo, or an earlier external one) is skipped.
# Sorted by plugin.conf's order (default 50; a plugins.txt line has 50), and within the same order folders first, then
# the lines: install.sh installs them in this order, so Home Assistant (order=90), which asks things, stays last.
# One line each, fields separated by \x1f (none may be empty for read's sake, so a missing folder is "-"): id, name,
# icon, description, default, installer, installed test, group, folder
plugin_rows() {
  local d id k v seen order
  seen=" $(grep -vE '^\s*(#|$)' "$repo/plugins.txt" | cut -d'|' -f1 | tr '\n' ' ')"
  {
    for d in "$repo"/plugins/*/ "$external"/*/; do
      d=${d%/}; id=${d##*/}
      [[ -f $d/plugin.conf && $seen != *" $id "* ]] || continue
      seen+="$id "
      local -A c=()
      while IFS='=' read -r k v; do [[ $k =~ ^[a-z]+$ ]] && c[$k]=$v; done < "$d/plugin.conf"
      order=${c[order]:-50}; [[ $order =~ ^[0-9]+$ ]] || order=50
      printf '%s\x1f' "$order" "$id" "${c[name]:-$id}" "${c[icon]:-puzzle}" "${c[description]:-}" "${c[default]:-off}" \
        "${c[install]:-true}" "${c[installed]:-false}" "${c[group]:-plugin}"
      printf '%s\n' "$d"
    done
    grep -vE '^\s*(#|$)' "$repo/plugins.txt" | awk -F'|' -v OFS=$'\x1f' '{ NF = 8; print 50, $0, "-" }'
  } | sort -s -t $'\x1f' -k1,1n | cut -d $'\x1f' -f2-
}
# One tab-separated line each: id, name, icon, description, default (on/off), installer, installed (1/0), group, folder
# (empty for a plugins.txt line), off (1/0: plugins off), source (repo, or external: plugins add). The tests run side by
# side, in the plugin's folder (the repo for plugins.txt): `flatpak info` takes a moment.
plugins() {
  local tmp rows id name icon desc def inst test group dir i=0
  tmp=$(mktemp -d)
  rows=$(plugin_rows)
  while IFS=$'\x1f' read -r id name icon desc def inst test group dir; do
    [[ $dir == - ]] && dir=$repo
    (cd "$dir" && bash -c "$test" >/dev/null 2>&1 && touch "$tmp/$i") &
    i=$((i + 1))
  done <<<"$rows"
  wait
  i=0
  while IFS=$'\x1f' read -r id name icon desc def inst test group dir; do
    [[ $dir == - ]] && dir=
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "$icon" "$desc" "$def" "$inst" "$([[ -e $tmp/$i ]] && echo 1 || echo 0)" \
      "$group" "$dir" "$([[ -e $off/$id ]] && echo 1 || echo 0)" "$([[ $dir == "$external/"* ]] && echo external || echo repo)"
    i=$((i + 1))
  done <<<"$rows"
  rm -rf "$tmp"
}
# `nightdrive plugins` on a terminal: one line each with its state (the launcher and scripts get the fields above).
# With a group (app), only that group's.
plugins_table() {
  plugins | awk -F'\t' -v g="${1:-}" 'g != "" && $8 != g { next } { st = $7 == 1 ? ($10 == 1 ? "off" : "on") : ($10 == 1 ? "not installed, off" : "not installed")
                          v = ""; if ($9 != "") { f = $9 "/plugin.conf"                # a folder: its version
                            while ((getline line < f) > 0) if (line ~ /^version=/) v = substr(line, 9); close(f) }
                          l = sprintf("%-18s %-26s %-8s %-14s %s", $1, $2, v, st, $11 == "external" ? "external: " $9 : ""); sub(/ +$/, "", l); print l }'
}
# The installed ones that are on: their ids, also to ~/.cache/nightdrive/plugins (Plugins.qml watches it,
# hypr/bindings.lua reads it). One that is off (plugins off) is left out, so the desktop treats it as not installed.
# When the list changes, Hyprland reloads: the keybindings of an added or removed part. The plugin folders' parts (bar
# module, menus, keys, shortcut lines) are gathered in ~/.local/state/nightdrive/plugins.d (hypr/scripts/plugin-parts).
plugins_installed() {
  local list ids old
  list=$(plugins | awk -F'\t' '$7 == 1 && $10 == 0')
  ids=$(cut -f1 <<<"$list")
  awk -F'\t' '$9 != "" { print $1 "\t" $9 }' <<<"$list" | "$scripts/plugin-parts"
  mkdir -p "$cache"
  old=$(cat "$cache/plugins" 2>/dev/null) || old=__none__
  if [[ $ids != "$old" ]]; then
    printf '%s\n' "$ids" > "$cache/plugins.tmp" && mv "$cache/plugins.tmp" "$cache/plugins"
    [[ $old != __none__ && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && hyprctl reload >/dev/null 2>&1
  fi
  printf '%s\n' "$ids" | sed '/^$/d'
}
# `nightdrive apps`: plugins' commands for Nightdrive's own apps (group=app) only; plugins will take others' too
app_only() {
  plugin_rows | awk -F'\x1f' -v n="${1,,}" 'n != "" && (tolower($1) == n || tolower($2) == n) && $8 == "app" { f = 1 } END { exit !f }' ||
    { echo "Unknown app: ${1:-} (see: nightdrive apps)" >&2; exit 1; }
}

# A plugin.conf's value (conf_value FILE KEY), empty when it has none
conf_value() { sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -1; }
# The names of these packages that are installed
installed_names() { (( $# )) && rpm -q --qf '%{NAME}\n' "$@" 2>/dev/null | grep -v ' ' | sort -u | tr '\n' ' ' || true; }
# The installed plugins' packages (plugin.conf's packages=), one a line: also those that are off, which stay installed
plugin_packages() {
  local dir
  plugins | awk -F'\t' '$7 == 1 && $9 != "" { print $9 }' | while read -r dir; do
    conf_value "$dir/plugin.conf" packages | tr ' ' '\n'
  done | sed '/^$/d' | sort -u
}

# A plugin by id or name (any case): its id, name and folder ("-" for a plugins.txt line), tab-separated; nothing if unknown
plugin_find() {
  plugin_rows | awk -F'\x1f' -v n="$1" 'n != "" && (tolower($1) == tolower(n) || tolower($2) == tolower(n)) { print $1 "\t" $2 "\t" $9; exit }'
}
