# shellcheck shell=bash
# Part of the nightdrive command (sourced by bin/nightdrive): `nightdrive plugins off|on` (and `apps off|on`), with the
# user units a plugin folder brings. Apart from installing because it only hides and stops, never adds or deletes.

# A plugin folder's user units, by name: its systemd/ ones, and those its installer set up elsewhere (plugin.conf's units=,
# Ferry's ferry.service)
plugin_units() {
  local f
  for f in "$1"/systemd/*; do [[ -f $f ]] && echo "${f##*/}"; done
  sed -n 's/^units=//p' "$1/plugin.conf" 2>/dev/null | tr ' ' '\n' | sed '/^$/d'
}
# The units to stop and start: a template (name@.service, an instance per thing: VNC Display's devices) can't be either,
# so it stands for its instances, the ones loaded now and the ones enabled. Its drop-in (plugin_switch) covers them all.
unit_instances() {
  local u f
  for u; do
    [[ $u == *@.service ]] || { echo "$u"; continue; }
    {
      systemctl --user list-units --all --plain --no-legend "${u%.service}*.service" 2>/dev/null | awk '{ print $1 }'
      for f in "$HOME"/.config/systemd/user/*.wants/"${u%.service}"*.service; do [[ -e $f ]] && echo "${f##*/}"; done
    } | sort -u
  done
}

# plugins off|on NAME. Off: the desktop treats it as not installed (no bar module, menu, launcher rows, keys or shortcut
# lines: plugins_installed leaves it out) and its folder's units are stopped. They stay enabled, so its installed test
# (often `is-enabled`) still holds; a drop-in keeps them from starting at login while it's off. On: the drop-in goes and
# the units that ran when it was turned off (listed in its file in $off) or are enabled start again. A plugins.txt line
# has no units of its own here: only its rows and keys go. Needs nothing from the desktop, so it works from a terminal
# when the bar is stuck.
plugin_switch() {
  local id name dir u units=() run=() was=() stopped=""
  IFS=$'\t' read -r id name dir < <(plugin_find "${2:-}")
  [[ -n ${id:-} ]] || { echo "Unknown plugin: ${2:-} (see: nightdrive plugins)" >&2; return 1; }
  [[ $dir == - ]] || mapfile -t units < <(plugin_units "$dir")
  (( ${#units[@]} )) && mapfile -t run < <(unit_instances "${units[@]}")
  if [[ $1 == off ]]; then
    [[ -e $off/$id ]] && { echo "$name is already off."; return 0; }
    for u in "${run[@]}"; do systemctl --user -q is-active "$u" 2>/dev/null && was+=("$u"); done
    mkdir -p "$off" && printf '%s\n' "${was[@]}" | sed '/^$/d' > "$off/$id"
    for u in "${units[@]}"; do
      mkdir -p "$HOME/.config/systemd/user/$u.d"
      printf '%s\n' "# nightdrive plugins off $id: not started while the plugin is off (nightdrive plugins on $id removes this)" \
        "[Unit]" "ConditionPathExists=!%h/.local/state/nightdrive/plugins-off/$id" > "$HOME/.config/systemd/user/$u.d/nightdrive-off.conf"
    done
    if (( ${#units[@]} )); then
      systemctl --user daemon-reload 2>/dev/null
      if (( ! ${#run[@]} )); then :
      elif systemctl --user stop "${run[@]}" 2>/dev/null; then stopped=", ${run[*]} stopped"
      else stopped=" (couldn't stop ${run[*]}: no user systemd?)"; fi
    fi
  else
    [[ -e $off/$id ]] || { echo "$name is already on."; return 0; }
    mapfile -t was < "$off/$id"
    rm -f "$off/$id"
    for u in "${units[@]}"; do
      rm -f "$HOME/.config/systemd/user/$u.d/nightdrive-off.conf"; rmdir "$HOME/.config/systemd/user/$u.d" 2>/dev/null
    done
    if (( ${#units[@]} )); then
      systemctl --user daemon-reload 2>/dev/null
      for u in "${run[@]}"; do
        [[ " ${was[*]} " == *" $u "* || $(systemctl --user is-enabled "$u" 2>/dev/null) == enabled ]] && systemctl --user start "$u" 2>/dev/null
      done
    fi
  fi
  plugins_installed >/dev/null
  qs ipc call bar refresh >/dev/null 2>&1 || true
  if [[ $1 == off ]]; then
    echo "$name is off: hidden from the desktop$stopped. Still installed: nightdrive plugins on $id brings it back."
  else
    echo "$name is on again."
  fi
}
