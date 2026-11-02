# shellcheck shell=bash
# Part of the nightdrive command (sourced by bin/nightdrive): what adds or takes away a plugin. `plugins install`
# (and `apps install`, offer_apps), `plugins add` for an external one with the links it needs, `plugins remove`.

# Runs a plugin's installer (by id or name) in its folder (the repo for plugins.txt), then refreshes the list. One that
# is off is turned on first: installing it again means it's wanted (and its unit could not start while off).
plugin_install() {
  local id name inst dir rc pk
  IFS=$'\t' read -r id name inst dir < <(plugins | awk -F'\t' -v n="$1" 'tolower($1) == tolower(n) || tolower($2) == tolower(n) { print $1 "\t" $2 "\t" $6 "\t" ($9 == "" ? "-" : $9); exit }')
  [[ -n ${id:-} ]] || { echo "Unknown plugin: ${1:-} (see: nightdrive plugins)" >&2; exit 1; }
  [[ $dir == - ]] && dir=$repo
  [[ -e $off/$id ]] && plugin_switch on "$id" >/dev/null
  echo "==> $name"
  case $inst in
    "flatpak "*)
      flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak install --user -y --noninteractive flathub ${inst#flatpak } && { "$repo/config/fuzzel/sync-apps" >/dev/null 2>&1 || true; } ;;
    "webapp "*)
      "$scripts/webapp-add" "$name" "${inst#webapp }" && { "$repo/config/fuzzel/sync-apps" >/dev/null 2>&1 || true; } ;;
    *)
      [[ -f $dir/${inst%% *} && ${inst%% *} != */* ]] && inst="./$inst"      # a plugin folder's script (install.sh)
      (cd "$dir" && bash -c "$inst") ;;
  esac
  rc=$?
  # Its packages= as wanted: one KDE (or another plugin) had already pulled in stays a dependency otherwise, and removing
  # KDE (nightdrive minimal) would take it along
  if (( rc == 0 )) && [[ $dir != "$repo" ]]; then
    pk=$(installed_names $(conf_value "$dir/plugin.conf" packages))
    [[ -z $pk ]] || sudo dnf mark user -y $pk >/dev/null || true
  fi
  plugins_installed >/dev/null
  qs ipc call bar refresh >/dev/null 2>&1 || true
  return $rc
}

# Links a plugin folder's commands (bin/) and user units (systemd/) as link.sh does. A name that something else already
# has is left alone, with a note.
plugin_link() {
  local f dst
  for f in "$1"/bin/* "$1"/systemd/*; do
    [[ -f $f ]] || continue
    if [[ ${f%/*} == "$1/bin" ]]; then dst=$HOME/.local/bin/${f##*/}; else dst=$HOME/.config/systemd/user/${f##*/}; fi
    if [[ -e $dst || -L $dst ]] && [[ $(readlink -f "$dst") != "$(readlink -f "$f")" ]]; then
      echo "    $dst is already there: not linked" >&2; continue
    fi
    mkdir -p "${dst%/*}" && ln -sfn "$f" "$dst"
  done
  systemctl --user daemon-reload 2>/dev/null || true
}

# plugins add GIT-URL [ID]: clones an external plugin, a repo whose top is a plugin folder (plugin.conf at its root), into
# $external/<id>. The id is the repo's name without .git and a nightdrive-plugin- prefix, unless given. One that the
# repo's plugins or plugins.txt (or another external one) already have is refused: an external plugin can't replace them.
# Not installed here: its installer may ask things, so it runs from the launcher or `plugins install`.
plugin_add() {
  local url=${1:-} id=${2:-} tmp taken name
  [[ -n $url ]] || { echo "Usage: nightdrive plugins add GIT-URL [ID]" >&2; return 1; }
  if [[ -z $id ]]; then id=${url%/}; id=${id##*/}; id=${id##*:}; id=${id%.git}; id=${id#nightdrive-plugin-}; id=${id,,}; fi
  [[ $id =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "Not a usable id: $id (letters, digits, - and _; give one: nightdrive plugins add URL ID)" >&2; return 1; }
  IFS=$'\t' read -r taken name _ < <(plugin_rows | awk -F'\x1f' -v n="$id" '$1 == n { print $1 "\t" $2 "\t" $9; exit }')
  if [[ -n ${taken:-} ]]; then
    echo "The id $id is taken (by $name): give this one another id, nightdrive plugins add URL OTHER-ID" >&2; return 1
  fi
  [[ -e $external/$id ]] && { echo "$external/$id is already there (but has no plugin.conf): move it away first" >&2; return 1; }
  mkdir -p "$external"
  tmp=$(mktemp -d "$external/.add-XXXXXX")      # a dot folder: not read as a plugin while it's cloning
  if ! git clone -q "$url" "$tmp/$id"; then rm -rf "$tmp"; echo "Couldn't clone $url" >&2; return 1; fi
  if [[ ! -f $tmp/$id/plugin.conf ]]; then
    rm -rf "$tmp"; echo "$url has no plugin.conf at its top: not a Nightdrive plugin" >&2; return 1
  fi
  mv "$tmp/$id" "$external/$id" && rmdir "$tmp"
  plugin_link "$external/$id"
  plugins_installed >/dev/null
  qs ipc call bar refresh >/dev/null 2>&1 || true
  name=$(sed -n 's/^name=//p' "$external/$id/plugin.conf" | head -1)
  echo "Added ${name:-$id} ($id) in $external/$id."
  echo "Its code runs as you, like Nightdrive's own: add only plugins whose source you trust."
  echo "Install it: nightdrive plugins install $id (or Launcher › Install). nightdrive update keeps it up to date."
}

# plugins remove NAME: an external plugin only (the repo's own are turned off instead). Turned off, its units disabled
# and its links removed, then the folder deleted. A folder with work of its own (uncommitted changes, commits that
# aren't pushed, or no git at all) needs --force. What its installer put elsewhere (packages, settings) stays.
plugin_remove() {
  local force=0 id name dir u l
  [[ ${1:-} == --force ]] && { force=1; shift; }
  [[ ${2:-} == --force ]] && force=1
  IFS=$'\t' read -r id name dir < <(plugin_find "${1:-}")
  [[ -n ${id:-} ]] || { echo "Unknown plugin: ${1:-} (see: nightdrive plugins)" >&2; return 1; }
  if [[ $dir != "$external/$id" ]]; then
    echo "$name comes with Nightdrive and can't be removed: nightdrive plugins off $id hides it." >&2; return 1
  fi
  if (( !force )); then
    if [[ ! -e $dir/.git ]]; then
      echo "$dir isn't a git clone, so it may be the only copy: nothing removed (--force removes it anyway)" >&2; return 1
    fi
    if [[ -n $(git -C "$dir" status --porcelain 2>/dev/null) || $(git -C "$dir" rev-list --count HEAD --not --remotes 2>/dev/null) != 0 ]]; then
      echo "$dir has changes or commits of its own: nothing removed (--force removes it anyway)" >&2; return 1
    fi
  fi
  plugin_switch off "$id" >/dev/null
  for u in $(plugin_units "$dir"); do
    systemctl --user disable "$u" >/dev/null 2>&1
    rm -f "$HOME/.config/systemd/user/$u.d/nightdrive-off.conf"; rmdir "$HOME/.config/systemd/user/$u.d" 2>/dev/null
  done
  for l in "$HOME"/.local/bin/* "$HOME"/.config/systemd/user/* "$HOME"/.config/systemd/user/*.wants/*; do
    [[ -L $l && $(readlink "$l") == "$dir/"* ]] && rm -f "$l"
  done
  rm -rf "${dir:?}" && rm -f "$off/$id"
  systemctl --user daemon-reload 2>/dev/null
  plugins_installed >/dev/null
  qs ipc call bar refresh >/dev/null 2>&1 || true
  echo "Removed $name ($dir). What its installer set up elsewhere (packages, settings) stays."
}
