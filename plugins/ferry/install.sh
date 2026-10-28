#!/bin/bash
# Installs Ferry (https://github.com/nightdrive-sh/ferry) with Ferry's own install script: its server and `ferry`
# command, its window and Files' "Open With → Ferry", but not its tray icon, whose place the top bar's module and menu
# take. Then the hook through which Ferry tells that menu something changed. The release is the one pinned in
# release.conf (./pin writes it): its install script and tarball are downloaded by that tag and run only when both match
# the sha256 there, so a changed release asset never runs. Running it again updates Ferry to the pinned release;
# `nightdrive update` runs it with --update, which does nothing while the installed Ferry is that release.
# A Ferry from before, this plugin's own server, is replaced, and its phones and box come along (Ferry moves its state).
#
# FERRY_FROM=<a Ferry checkout's linux/ folder, or a folder with a release's install.sh and ferry-linux.tar.gz> installs
# that instead of the release, unchecked (to try a Ferry that isn't released or pinned yet).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=nightdrive-sh/ferry
from=${FERRY_FROM:-}

# The pinned release: release.conf's tag, install_sha256 and tarball_sha256
pinned() { sed -nE "s/^$1=//p" "$here/release.conf" 2>/dev/null || true; }
tag=$(pinned tag)
[[ -n $from || ( -n $tag && -n $(pinned install_sha256) && -n $(pinned tarball_sha256) ) ]] \
  || { echo "No Ferry release pinned in $here/release.conf (./pin writes it)" >&2; exit 1; }

if [[ ${1:-} == --update && -z $from ]]; then
  have=$(readlink -f "$HOME/.local/bin/ferry" 2>/dev/null) || have=""
  # Ferry's own install is in ~/.local/lib/ferry; anything else there is this plugin's old server
  if [[ $have == "$HOME/.local/lib/ferry/"* ]]; then
    [[ $("$have" version 2>/dev/null) == "${tag#v}" ]] && { echo "    up to date"; exit 0; }
  fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
args=()
if [[ -z $from ]]; then
  for f in install.sh ferry-linux.tar.gz; do
    curl -fsSL -o "$tmp/$f" "https://github.com/$repo/releases/download/$tag/$f" \
      || { echo "Couldn't download $f of Ferry $tag from github.com/$repo" >&2; exit 1; }
  done
  # Neither runs unless both are what was pinned: the tarball too, since the script would otherwise fetch its own
  printf '%s  install.sh\n%s  ferry-linux.tar.gz\n' "$(pinned install_sha256)" "$(pinned tarball_sha256)" \
    | (cd "$tmp" && sha256sum --quiet -c) \
    || { echo "Ferry $tag from github.com/$repo doesn't match the sha256 in $here/release.conf: not installed" >&2; exit 1; }
  script=$tmp/install.sh; args=(--from "$tmp/ferry-linux.tar.gz")
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
