# Sourced by ask-claude --run: one turn, inside the unit unit.sh started. Claude's events go to the conversation's
# events.jsonl as they come (stream-json), then a nightdrive_end line says how it ended, and notify.sh tells the user
# when nobody is looking (Dashboard #2244).
# shellcheck shell=bash
# The parts share their globals with ask-claude, which sources them all (shellcheck can't follow its loop)
# shellcheck disable=SC2034,SC2154

run_turn() {   # id mode name resumed prompt
  local id=$1 mode=$2 name=$3 resumed=$4 prompt=$5
  local dir ev run start pid rc cancelled=0 status message answer
  dir=$(conv_dir "$id"); ev="$dir/events.jsonl"
  run="${XDG_RUNTIME_DIR:-/run/user/$UID}/nightdrive/ask-claude/$id"   # mcp.json and stderr, gone after the turn
  # shellcheck disable=SC2174   # the run's own folder is what holds mcp.json; $XDG_RUNTIME_DIR is 700 already
  mkdir -p -m 700 "$run" || { seal "$id" error "No runtime folder"; return 1; }
  # Expanded now: the trap runs at the script's exit, when this function's locals are gone
  # shellcheck disable=SC2064
  trap "rm -rf $(printf '%q %q' "$run" "$dir/pid")" EXIT
  printf '%s\n' "$$" >"$dir/pid"
  start=$(wc -l 2>/dev/null <"$ev" || echo 0)   # this turn's events come after these

  if [[ ! -x $claude_bin ]] || ! claude_flags "$id" "$mode" "$run/mcp.json"; then
    end_line error notools >>"$ev"; return 3
  fi
  # A child session's variables would make claude think it runs inside another one
  local v; for v in $(compgen -e | grep '^CLAUDE'); do unset "$v"; done
  local sess
  if (( resumed )); then sess=(--resume "$id"); else sess=(--session-id "$id" ${name:+-n "$name"}); fi

  local notify=0; [[ $mode == notify ]] && notify=1
  (( notify )) && working_notice "$id" "$prompt"

  # --include-partial-messages streams the answer's text as it is written, for the toast
  (cd "$work_dir" && exec timeout "$LIMIT" "$claude_bin" -p --output-format stream-json --verbose \
     --include-partial-messages "${sess[@]}" "${flags[@]}" -- "$prompt") >>"$ev" 2>"$run/err" </dev/null &
  pid=$!
  # systemctl stop (KillMode=mixed) or --cancel without systemd: stop Claude, then say so
  trap 'cancelled=1; kill -TERM "$pid" 2>/dev/null' TERM INT
  while :; do
    wait "$pid"; rc=$?
    kill -0 "$pid" 2>/dev/null || break   # wait returns early when the trap runs; Claude is still stopping
  done
  (( notify )) && working_done
  # A sign-in about to end says so on stderr: one notification a day, with a button to sign in again (#3664)
  grep -qs "sign-in" "$run/err" && "$HOME/.config/hypr/scripts/claude-signin" warn "$run/err" </dev/null >/dev/null 2>&1

  # How it ended: this turn's result (a result after `start`, not an earlier turn's)
  local last failed
  last=$(tail -n +"$(( start + 1 ))" "$ev" | jq -c 'select(.type? == "result") | { e: (.is_error == true), r: (.result // "" | tostring) }' \
           2>/dev/null | tail -n1)
  [[ -n $last ]] || last='{"e":true,"r":""}'   # no result at all: stopped or broken
  failed=$(jq -r '.e' <<<"$last"); answer=$(jq -r '.r' <<<"$last")
  if (( cancelled )); then status=cancelled
  elif (( rc == 124 )); then status=timeout; message="Stopped after $(( LIMIT / 60 )) minutes"
  elif [[ $failed != false || -z ${answer//[[:space:]]/} ]] || (( rc )); then
    status=error; [[ $failed == true ]] && message=$answer; answer=
    [[ -n ${message//[[:space:]]/} ]] || message=$(grep -v '^[[:space:]]*$' "$run/err" | tail -n1)
    [[ -z $message ]] && (( rc )) && message="Claude stopped ($rc)"
  else status="done"
  fi
  end_line "$status" "$message" >>"$ev"
  touch "$dir"   # kept KEEP_DAYS from its last turn
  end_notice "$id" "$mode" "$status" "$message" "$answer" "$prompt"
  return 0
}
