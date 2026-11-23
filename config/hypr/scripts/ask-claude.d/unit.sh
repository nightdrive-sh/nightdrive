# Sourced by ask-claude: a turn as a transient systemd user unit (log 4039, Dashboard #2244), so it outlives
# Quickshell's restart and the launcher that started it. The unit runs `ask-claude --run` (run.sh), which appends
# Claude's events to the conversation's events.jsonl; whoever shows the conversation reads that file, not the process.
# One turn at a time: systemd holds the unit's name. Without a user manager (the sandbox) the turn runs under setsid
# instead, and its pid file says whether it still runs.
#   events.jsonl: Claude Code's stream-json, one object a line, and Nightdrive's own around each turn:
#     {"type":"nightdrive_turn","prompt":…,"at":ms[,"dictated":true]}   written here, before the unit starts
#     {"type":"nightdrive_end","status":done|error|timeout|cancelled,"message":…,"at":ms}   run.sh, or seal() here
# shellcheck shell=bash
# The parts share their globals with ask-claude, which sources them all (shellcheck can't follow its loop)
# shellcheck disable=SC2034,SC2154

systemd_here() { [[ -S ${XDG_RUNTIME_DIR:-/run/user/$UID}/systemd/private ]] && command -v systemd-run >/dev/null; }

current_id() { local id; read -r id 2>/dev/null <"$ask_state/current" && [[ $id =~ ^[0-9a-f-]{36}$ ]] && echo "$id"; }

# Whether a turn runs now (any conversation's: they share the unit)
active() {
  if systemd_here; then systemctl --user is-active -q "$UNIT"; return; fi
  local id pid; id=$(current_id) || return 1
  read -r pid 2>/dev/null <"$(conv_dir "$id")/pid" && kill -0 "$pid" 2>/dev/null
}

end_line() {   # status message
  jq -cn --arg s "$1" --arg m "${2:-}" --argjson at "$(now_ms)" '{ type: "nightdrive_end", status: $s, message: $m, at: $at }'
}

# A turn that ended without saying so (killed with the session, the machine off) gets its end, so nothing waits on it
seal() {   # id status message
  local ev; ev="$(conv_dir "$1")/events.jsonl"
  [[ -s $ev ]] || return 0
  [[ $(tail -n1 "$ev" | jq -r '.type? // empty' 2>/dev/null) == nightdrive_end ]] && return 0
  end_line "$2" "$3" >>"$ev"
}

# A command that outlives the unit: a notification's buttons are waited on after the turn has ended, and the unit's
# processes go with it
detach() {
  if systemd_here; then systemd-run --user --collect --quiet -E PATH -- "$@" >/dev/null 2>&1
  else setsid -f "$@" >/dev/null 2>&1 </dev/null; fi
}

# Starts a turn: prints {"id"} or {"error"}. mode: toast | notify (run.sh). resume: an existing conversation's id
start_turn() {   # id mode name resume prompt
  local id=$1 mode=$2 name=$3 resume=$4 prompt=$5 dir
  if active; then jq -cn '{ error: "busy" }'; return 4; fi
  dir=$(conv_dir "$id")
  # shellcheck disable=SC2174   # 700 matters on these two, ask's own; their parents are the usual state folders
  mkdir -p -m 700 "$ask_state" "$dir" && touch "$dir" || { jq -cn '{ error: "Ask Claude has no folder" }'; return 1; }
  # Conversations untouched for KEEP_DAYS go, with their results and downloads (log 4039)
  find "$ask_state" -mindepth 1 -maxdepth 1 -type d -mtime +"$KEEP_DAYS" -exec rm -rf {} + 2>/dev/null
  printf '%s\n' "$id" >"$ask_state/current"
  # dictated (ask-claude's global): the toast strips the unsure mark from this turn's answer, after a restart too
  jq -cn --arg p "$prompt" --argjson at "$(now_ms)" --argjson d "$(( ${dictated:-0} ? 1 : 0 ))" \
    '{ type: "nightdrive_turn", prompt: $p, at: $at } + (if $d == 1 then { dictated: true } else {} end)' >>"$dir/events.jsonl"
  local cmd=("$scripts/ask-claude" --run "$id" "$mode" ${name:+--name "$name"} ${resume:+--resume})
  (( ${dictated:-0} )) && cmd+=(--dictated)
  cmd+=(-- "$prompt")
  if systemd_here; then
    # RuntimeMaxSec only backs up run.sh's own limit, which can say the turn ran out of time. KillMode=mixed: Cancel's
    # SIGTERM goes to run.sh alone, which stops Claude and writes the end before the rest is killed
    if ! systemd-run --user --unit "$UNIT" --collect --quiet -E PATH -p RuntimeMaxSec=$(( LIMIT + 60 )) \
           -p KillMode=mixed --description "Ask Claude" -- "${cmd[@]}" >/dev/null 2>"$dir/start.err"; then
      seal "$id" error "$(tail -n1 "$dir/start.err")"
      jq -cn '{ error: "busy" }'; return 4
    fi
  else
    setsid -f "${cmd[@]}" >/dev/null 2>&1 </dev/null
  fi
  jq -cn --arg id "$id" '{ id: $id }'
}

# Cancel (the toast's ⌃C and its small card, the working notification): run.sh writes "cancelled" as it stops
cancel_turn() {
  local id pid i; id=$(current_id) || return 0
  if systemd_here; then
    systemctl --user stop "$UNIT" 2>/dev/null
  elif read -r pid 2>/dev/null <"$(conv_dir "$id")/pid" && kill -TERM "$pid" 2>/dev/null; then
    for (( i = 0; i < 50; i++ )); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  fi
  seal "$id" cancelled ""
}

# The latest conversation, for the toast after Quickshell's restart: {id, running, last (ms)}, or {} when none
current_turn() {
  local id run=false ev last
  id=$(current_id) && ev="$(conv_dir "$id")/events.jsonl" && [[ -s $ev ]] || { echo '{}'; return; }
  if active; then run=true; else seal "$id" error "Stopped before it answered"; fi
  last=$(( $(stat -c %Y "$ev") * 1000 ))
  jq -cn --arg id "$id" --argjson r "$run" --argjson l "$last" '{ id: $id, running: $r, last: $l }'
}
