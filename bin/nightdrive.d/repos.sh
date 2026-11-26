# shellcheck shell=bash
# Part of the nightdrive command (bin/nightdrive sources every bin/nightdrive.d/*.sh): what updates compare against.
# The repos an update pulls, what each follows, how far behind it is, the release notes since a commit, the version, and
# `nightdrive update check`. Kept apart from update.sh so the timer's check and `version` read as small pieces.

# Repos to update: Nightdrive, the repos the git-ignored local slots link into (a private overlay), external plugins,
# Deck's source
repos() {
  echo "$repo"
  local f
  for f in "$repo"/config/hypr/local.d/* "$repo"/config/hypr/*.local* "$repo"/config/quickshell/local \
           "$repo"/config/topbar/local.* "$repo"/config/topbar/status.local; do
    [[ -L $f ]] && git -C "$(dirname "$(readlink -f "$f")")" rev-parse --show-toplevel 2>/dev/null
  done | sort -u
  for f in "$external"/*/; do [[ -e $f.git ]] && echo "${f%/}"; done   # external plugins (plugins add)
  [[ -d ${DECK_SRC:-$HOME/.local/src/deck}/.git ]] && readlink -f "${DECK_SRC:-$HOME/.local/src/deck}"
}
# What a repo updates to: Nightdrive follows its channel's branch on origin (channel below), the others their upstream
upstream() {
  local b
  b=$(git -C "$1" branch --show-current 2>/dev/null)
  if [[ $1 == "$repo" && $b =~ ^(main|dev)$ ]] && git -C "$1" rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
    echo "origin/$b"
  else
    echo "@{upstream}"
  fi
}
behind() { git -C "$1" rev-list --count "HEAD..$(upstream "$1")" 2>/dev/null || echo 0; }
# The same for the Nightdrive repo, leaving out the commits whose every path is in the folder of a plugin that isn't on
# here (plugins/<id>/ of one that isn't installed, or is off): nothing in them reaches this desktop. A merge counts by its
# own changes (against its first parent); the merged commits count one by one.
behind_nightdrive() {
  local on
  [[ -e $HOME/.local/state/nightdrive/plugins.d/active ]] || plugins_installed >/dev/null
  on=$(cut -f1 "$HOME/.local/state/nightdrive/plugins.d/active" 2>/dev/null | tr '\n' ' ')
  git -C "$repo" log --format=tformat:@ --name-only --diff-merges=first-parent "HEAD..$(upstream "$repo")" 2>/dev/null | awk -v on=" $on" '
    function count() { if (started && (keep || !paths)) n++ }
    $0 == "@" { count(); started = 1; keep = 0; paths = 0; next }
    NF { paths++; if (!match($0, /^plugins\/[^\/]+\//) || index(on, " " substr($0, 9, RLENGTH - 9) " ")) keep = 1 }
    END { count(); print n + 0 }'
}

# whats_new COMMIT: the sections of CHANGELOG.md that weren't there at COMMIT (the releases since), newest first
whats_new() {
  SEEN=$(git -C "$repo" show "$1:CHANGELOG.md" 2>/dev/null | grep '^## ' || true) awk '
    BEGIN { n = split(ENVIRON["SEEN"], s, "\n"); for (i = 1; i <= n; i++) old[s[i]] = 1 }
    /^## / { on = !($0 in old) } on' "$repo/CHANGELOG.md"
}

# version: the release this checkout is at (its tag), how many changes past it, and the channel
version() {
  local d ch
  case $(git -C "$repo" branch --show-current) in main) ch=stable ;; dev) ch=dev ;; *) ch=custom ;; esac
  if ! d=$(git -C "$repo" describe --tags --long --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null); then
    echo "Nightdrive, no release yet ($ch channel, $(git -C "$repo" rev-parse --short HEAD))"; return
  fi
  local tag=${d%-*-g*} rest=${d%-g*}; local n=${rest##*-}
  if (( n == 0 )); then echo "Nightdrive ${tag#v} ($ch channel)"
  else echo "Nightdrive ${tag#v}, and $n change$( (( n == 1 )) || echo s) since ($ch channel, ${d##*-g})"; fi
}

# update check: fetch only, count the new commits; notifies once per new count, and the notification's Update button runs
# the update in a terminal (nightdrive-update-check.timer, every 6 h)
check() {
  total=0
  while read -r r; do
    timeout 30 git -C "$r" fetch -q 2>/dev/null || continue
    if [[ $r == "$repo" ]]; then total=$(( total + $(behind_nightdrive) )); else total=$(( total + $(behind "$r") )); fi
  done < <(repos | sort -u)
  # System files that differ from the repo's (config/system/sync): on the machine Nightdrive is developed on, the checkout
  # is never behind origin, so these are what tells it to update (keyd's /etc config after #1731 went unseen, #1917)
  total=$(( total + $("$repo/config/system/sync" --check | wc -l) ))
  mkdir -p "$cache"
  echo "$total" > "$cache/updates"
  last=$(cat "$cache/updates-notified" 2>/dev/null || echo 0)
  if (( total > 0 && total != last )); then
    echo "$total" > "$cache/updates-notified"
    (( total == 1 )) && what="1 new change" || what="$total new changes"
    action=$(notify-send -a Nightdrive -h string:x-dunst-stack-tag:update -A update=Update "Nightdrive update" "$what waiting" 2>/dev/null)
    # systemd-run: its own unit, so the terminal outlives this oneshot service (whose processes systemd ends)
    [[ $action == update ]] && systemd-run --user --collect -q "$repo/config/hypr/scripts/terminal" --class floating-tui -- bash -c \
      '"$1" update; echo; read -rp "Done. Press Enter to close…"' _ "$repo/bin/nightdrive"
  fi
}
