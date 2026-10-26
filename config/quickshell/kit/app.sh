# The apps' kit for their commands (nightmail, deck-window): each app's window is a Quickshell config of its own, and
# these start it, bring it forward, wait for it and stop it. Sourced, after the app has set
#   QS_DIR      its Quickshell config (the plugin's app/)
#   APP_TITLE   its window's title ("Mail"), which is also how it is named in messages
#   APP_IPC     its IpcHandler's target ("mail")
# app_command handles what every app's command does (open, restart, quit, log, settings); the app's own case comes first.

running() { qs list -p "$QS_DIR" 2>/dev/null | grep -q 'Process ID'; }
pid() { qs list -p "$QS_DIR" 2>/dev/null | awk '/Process ID/ { print $3; exit }'; }
# </dev/null: started from a terminal (an installer's), Quickshell would keep its stdin and the terminal would stay open
start() { setsid -f qs -p "$QS_DIR" </dev/null >/dev/null 2>&1; }

stop() {
  running || return 0
  qs kill -p "$QS_DIR" >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do running || return 0; sleep 0.1; done
}

# A window just started answers over IPC once it has loaded: wait for that (3 s at most).
ready() {
  for _ in $(seq 30); do
    qs ipc -p "$QS_DIR" show 2>/dev/null | grep -q "target $APP_IPC" && return 0
    sleep 0.1
  done
  return 1
}

# On Hyprland, a second start brings the open window forward instead of starting another one. Without a window to bring
# forward (closed while Quickshell stayed), it starts again.
focus() {
  command -v hyprctl >/dev/null || return 0
  local addr
  addr=$(hyprctl -j clients | jq -r --argjson pid "$(pid)" --arg t "$APP_TITLE" \
           '[.[] | select(.pid == $pid and .title == $t)] | first | .address // empty')
  if [[ -n $addr ]]; then
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
  else
    stop; start
  fi
}

open_window() { if running; then focus; else start; fi; }
# Opened and answering, for an IPC call right after: `open_ready && ipc compose`
open_ready() { if running; then focus; else start; ready; fi; }
ipc() { qs ipc -p "$QS_DIR" call "$APP_IPC" "$@" >/dev/null; }

# open, restart, quit, log and settings; 2 for anything else, for the app's usage
app_command() {
  case ${1:-open} in
    open)     open_window ;;
    restart)  stop; start ;;
    quit)     stop ;;
    log)      running || { echo "$APP_TITLE is not running." >&2; return 1; }; qs log -p "$QS_DIR" -f ;;
    settings) open_ready; ipc openSettings ;;
    *)        return 2 ;;
  esac
}
