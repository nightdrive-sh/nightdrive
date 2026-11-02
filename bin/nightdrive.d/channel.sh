# shellcheck shell=bash
# Part of the nightdrive command (sourced by bin/nightdrive): `nightdrive channel`, the switch between stable (main) and
# dev. On its own because it guards the user's work in many small steps that read best together.

# The update channel is the branch the Nightdrive checkout is on: main is stable, dev gets the bigger changes before they
# are merged into main (AGENTS.md › Branches). No setting of its own, so the two can't disagree. --update (the launcher's
# Update channel) runs the update after the switch without asking.
channel() {
  local cur want name ahead rc a upd=0
  [[ ${2:-} == --update ]] && upd=1
  cur=$(git -C "$repo" branch --show-current)
  if [[ -z ${1:-} ]]; then
    case $cur in
      main) echo "stable (branch main)" ;;
      dev) echo "dev (branch dev)" ;;
      *) echo "custom (${cur:+branch }${cur:-no branch})" ;;
    esac
    return
  fi
  case $1 in
    stable|main) want=main name=stable ;;
    dev|development) want=dev name=dev ;;
    *) echo "Unknown channel: $1 (stable or dev)" >&2; return 1 ;;
  esac
  [[ $cur == "$want" ]] && { echo "Already on the $name channel (branch $want)."; return 0; }
  # Asked from origin itself: a leftover origin/dev from before the branch was removed doesn't count
  git -C "$repo" ls-remote -q --exit-code --heads origin "$want" >/dev/null 2>&1; rc=$?
  if (( rc == 2 )); then
    echo "The $name channel's branch ($want) isn't on origin yet: nothing changed." >&2; return 1
  elif (( rc != 0 )); then
    echo "Couldn't reach origin: nothing changed." >&2; return 1
  fi
  # Never switched over the user's own work: uncommitted changes, or commits that aren't on origin (they'd stay behind
  # on the old branch, out of sight)
  if [[ -n $(git -C "$repo" status --porcelain --untracked-files=no) ]]; then
    echo "Nightdrive has uncommitted changes: nothing changed (commit or stash them, then run this again)." >&2; return 1
  fi
  ahead=$(git -C "$repo" rev-list --count HEAD --not --remotes=origin)
  if (( ahead > 0 )); then
    echo "${cur:-This checkout} has $ahead commit(s) that aren't on origin: nothing changed (push or move them first)." >&2; return 1
  fi
  git -C "$repo" fetch -q origin "$want" || { echo "Couldn't fetch $want: nothing changed." >&2; return 1; }
  # A local branch from an earlier switch can be behind origin: it is moved to origin's tip below, before its link.sh runs
  # (an old one would link the old files). One with commits of its own can't be moved without losing them: not switched.
  if git -C "$repo" rev-parse -q --verify "refs/heads/$want" >/dev/null; then
    ahead=$(git -C "$repo" rev-list --count "origin/$want..refs/heads/$want")
    if (( ahead > 0 )); then
      echo "The local $want branch has $ahead commit(s) that aren't on origin/$want: nothing changed. Push them, or keep" \
        "them on a branch of their own and move $want to origin's (git -C $repo branch my-$want $want &&" \
        "git -C $repo branch -f $want origin/$want), then run this again." >&2
      return 1
    fi
    git -C "$repo" switch -q "$want" && git -C "$repo" branch -q -u "origin/$want" "$want"
  else
    git -C "$repo" switch -q -c "$want" --track "origin/$want"
  fi || { echo "Couldn't switch to $want: nothing changed." >&2; return 1; }
  if ! git -C "$repo" merge -q --ff-only "origin/$want"; then
    echo "Switched to $want, but couldn't move it to origin/$want: the links weren't updated. Run" \
      "git -C $repo merge --ff-only origin/$want, then nightdrive update." >&2
    return 1
  fi
  echo "Now on the $name channel (branch $want)."
  # The new branch's links at once, not at the next update (which relinks first thing): the old ones can point at files
  # this branch moved or removed (a plugin's units, the Files extensions). Its own link.sh and update, as this function
  # is still the old branch's.
  if (( !upd )); then
    echo "==> Links"; "$repo/link.sh" | grep -v '^ok '
    (( PIPESTATUS[0] == 0 )) || echo "    failed: run $repo/link.sh to see why"
    if [[ -t 0 ]]; then
      read -rp "Run nightdrive update now? [Y/n] " a || a=n
      [[ $a =~ ^[Nn] ]] || upd=1
    fi
  fi
  (( upd )) && exec "$repo/bin/nightdrive" update
  echo "Run nightdrive update to finish: packages, apps, a desktop reload."
}
