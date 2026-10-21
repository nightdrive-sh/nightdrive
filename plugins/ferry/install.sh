#!/bin/bash
# Installs Ferry (https://github.com/nightdrive-sh/ferry) from its latest release with Ferry's own install script: its
# server and `ferry` command, its window and Files' "Open With → Ferry", but not its tray icon, whose place the top bar's
# module and menu take. Then the hook through which Ferry tells that menu something changed. Running it again updates
# Ferry; `nightdrive update` runs it with --update, which does nothing while the installed Ferry is the latest release.
# A Ferry from before, this plugin's own server, is replaced, and its phones and box come along (Ferry moves its state).
#
# FERRY_FROM=<a Ferry checkout's linux/ folder, or a folder with a release's install.sh and ferry-linux.tar.gz> installs
# that instead of the release (to try a Ferry that isn't released yet).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=nightdrive-sh/ferry
from=${FERRY_FROM:-}

# The latest release's version (its tag without the v), or nothing when GitHub can't be asked
latest() {
  curl -fsSI -o /dev/null -w '%{redirect_url}' "https://github.com/$repo/releases/latest" 2>/dev/null | sed -nE 's|.*/tag/v?||p'
}

if [[ ${1:-} == --update && -z $from ]]; then
  have=$(readlink -f "$HOME/.local/bin/ferry" 2>/dev/null) || have=""
  # Ferry's own install is in ~/.local/lib/ferry; anything else there is this plugin's old server
  if [[ $have == "$HOME/.local/lib/ferry/"* ]]; then
    want=$(latest)
    [[ -n $want ]] || { echo "    couldn't ask GitHub for Ferry's latest release" >&2; exit 1; }
    [[ $("$have" version 2>/dev/null) == "$want" ]] && { echo "    up to date"; exit 0; }
  fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
args=()
if [[ -z $from ]]; then
  curl -fsSL -o "$tmp/install.sh" "https://github.com/$repo/releases/latest/download/install.sh" \
    || { echo "Couldn't download Ferry's install script from github.com/$repo" >&2; exit 1; }
  script=$tmp/install.sh
elif [[ -f $from/ferry-linux.tar.gz ]]; then
  script=$from/install.sh; args=(--from "$from/ferry-linux.tar.gz")
else
  script=$from/install.sh; args=(--from "$from")
fi
[[ -f $script ]] || { echo "No Ferry install script in $from" >&2; exit 1; }
# The tray icon stays off on Nightdrive: an install script from before Ferry had one has no such option, and needs none
grep -q -- '--no-tray' "$script" && args+=(--no-tray)
# The plugin's old server holds Ferry's port. Ferry turns it off for good itself, but after an update its unit file is gone
# (link.sh removed the dead link), and then `systemctl disable --now` fails before it stops it.
systemctl --user stop nightdrive-ferry.service 2>/dev/null || true
bash "$script" "${args[@]}"

# The hook: Ferry runs ~/.config/ferry/hook when the box changes or files were picked, and Nightdrive's is this folder's
hook=${XDG_CONFIG_HOME:-$HOME/.config}/ferry/hook
if [[ -e $hook && ! -L $hook ]]; then
  echo "$hook is your own: not replaced (Nightdrive's top bar refreshes Ferry's icon on its own, every 5 s)" >&2
else
  mkdir -p "${hook%/*}" && ln -sfn "$here/hook" "$hook"
fi
qs ipc call bar refreshModule ferry >/dev/null 2>&1 || true
