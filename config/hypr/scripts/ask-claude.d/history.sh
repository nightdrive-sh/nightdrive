# Sourced by ask-claude list: the conversations kept (KEEP_DAYS after their last turn), newest first, from each one's
# events.jsonl and results.json (Dashboard #2244; the launcher's history row is #2246).
#   [{id, title, started, last, turns, status: running|done|error|timeout|cancelled, results}]   times in ms
# shellcheck shell=bash

list_turns() {   # json: 1 for JSON, else one tab-separated line each
  local json=$1 running ev dir out=()
  running=$(active && current_id)
  for ev in "$ask_state"/*/events.jsonl; do
    [[ -s $ev ]] || continue
    dir=${ev%/events.jsonl}
    # Only Nightdrive's own lines: Claude's partial messages make up most of the file
    out+=("$(grep -F '"type":"nightdrive_' "$ev" | jq -cs --arg id "${dir##*/}" --arg run "$running" \
      --argjson results "$(jq '.cards | length' "$dir/results.json" 2>/dev/null || echo 0)" '
        (map(select(.type == "nightdrive_turn"))) as $t | select($t | length > 0)
        | { id: $id, title: ($t[0].prompt | split("\n")[0] | .[0:120]), started: $t[0].at, last: (last.at),
            turns: ($t | length),
            status: (if $id == $run then "running" elif last.type == "nightdrive_end" then last.status else "error" end),
            results: $results }' 2>/dev/null)")
  done
  printf '%s\n' "${out[@]}" | jq -cs 'map(select(. != null)) | sort_by(-.last)' | {
    if (( json )); then cat
    else jq -r '.[] | [.id, (.last / 1000 | floor | strflocaltime("%Y-%m-%d %H:%M")), .status, .title] | @tsv'; fi
  }
}
