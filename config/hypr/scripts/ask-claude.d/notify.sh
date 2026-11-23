# Sourced by ask-claude --run: the notifications around a turn (Dashboard #1886, #2244).
# - notify mode (`ask-claude PROMPT`, no toast): "Claude is working…" with Cancel while it runs, then the answer, whose
#   click (or Open in terminal) goes on with the session in a terminal.
# - toast mode: the toast shows the turn; when it's closed as the turn ends, a notification says how it ended, with
#   Open (the toast again). Without Quickshell there to answer, Open goes to the terminal instead.
# Every notify-send has -- before its texts: GLib reads options after them too, so an answer (or a request) that
# begins with --app-name= or --icon= would change who the notification says it is from.
# shellcheck shell=bash
# The parts share their globals with ask-claude, which sources them all (shellcheck can't follow its loop)
# shellcheck disable=SC2034,SC2154

readonly SHOWN=1500       # characters of the answer the notification gets; the rest is in the toast or the terminal
readonly OPEN_WAIT=1800   # seconds the answer's buttons are waited on

short_of() { local s=${1%%$'\n'*}; (( ${#s} > 120 )) && s="${s:0:120}…"; printf '%s' "$s"; }

# Critical, so it stays on screen until the answer, without the urgent sound; transient, so it leaves no row in the
# history. Its click (default) only hides it; Cancel stops the turn as systemctl stop would (run.sh's trap)
working_notice() {   # id prompt
  local runner=$$
  ( notify-send -a Claude -i "$icon" -u critical -e -h boolean:suppress-sound:true -A default=Hide -A cancel=Cancel \
      -p -w -- "Claude is working…" "$(short_of "$2")" >"$run/working"
    [[ $(sed -n 2p "$run/working") == cancel ]] && kill -TERM "$runner" ) 2>/dev/null &
  working_pid=$!
}
working_done() {
  local nid; nid=$(sed -n 1p "$run/working" 2>/dev/null)
  [[ $nid =~ ^[0-9]+$ ]] && gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.CloseNotification "$nid" >/dev/null 2>&1
  kill "$working_pid" 2>/dev/null
}

# A click or Open in terminal goes on in a terminal, where Claude Code has its usual tools. In manual mode, whatever the
# user's settings start in: the transcript holds what the tools read (a mail, a note), untrusted text, so every tool
# asks first until the user changes the mode (#1930). A turn cut short by the limit can be continued too.
terminal_notice() {   # id title body
  detach bash -c '
    action=$(timeout "$1" notify-send -a Claude -i "$2" -A default="Open in terminal" -A open="Open in terminal" -w -- "$3" "$4")
    [[ $action == default || $action == open ]] && exec "$5" --dir "$6" -- "$7" --resume "$8" --permission-mode manual
  ' _ "$OPEN_WAIT" "$icon" "$2" "$3" "$HOME/.config/hypr/scripts/terminal" "$work_dir" "$claude_bin" "$1"
}

end_notice() {   # id mode status message answer prompt
  local id=$1 mode=$2 status=$3 message=$4 answer=$5 short title body shown
  short=$(short_of "$6")
  # The notification shows plain text: Markdown's bold and code marks would show as they are
  body=$(sed -e 's/\*\*//g' -e 's/`//g' <<<"$answer")
  (( ${#body} > SHOWN )) && body="${body:0:SHOWN}…"
  case $status in
    cancelled) [[ $mode == notify ]] && notify-send -a Claude -i "$icon" -e -- "Claude stopped" "$short"; return 0 ;;
    timeout) title="Claude ran out of time"; body="$message: $short" ;;
    error) title="Claude couldn't answer"; body=${message:-"No answer to: $short"} ;;
    *) title="Claude: $short" ;;
  esac
  [[ $mode == notify ]] && { terminal_notice "$id" "$title" "$body"; return 0; }

  # The toast: open (it shows the end itself) or closed; nothing back means Quickshell isn't there to show it
  shown=$(timeout 3 qs ipc call askClaude shown 2>/dev/null)
  [[ $shown == open ]] && return 0
  [[ $shown == closed ]] || { terminal_notice "$id" "$title" "$body"; return 0; }
  [[ $status == "done" ]] && title="Claude answered"
  detach bash -c '
    action=$(timeout "$1" notify-send -a Claude -i "$2" -A default=Open -A open=Open -w -- "$3" "$4")
    [[ $action == default || $action == open ]] && exec qs ipc call askClaude open
  ' _ "$OPEN_WAIT" "$icon" "$title" "$body"
}
