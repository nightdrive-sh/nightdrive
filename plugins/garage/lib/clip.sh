# Text onto a running VM's clipboard (#3117), for bin/garage-ctl (sourced after its helpers and lib/qemu.sh: die, dir,
# need, running, conf, vm_state). lib/guestclip.py does it through the guest agent (and has which guests take it how);
# this picks the VM, keeps its setting and is quiet where nobody asked.
#   clip_text NAME [--clipboard]   stdin's text, or the host clipboard's (the window's c, the menu's row, garage clip)
#   clip_auto PID                  the overlay's (overlay/ClipSync.qml), when a VM's window gets the keyboard: the host
#                                  clipboard, if the VM's setting allows it and it has changed since it last went there
#   clip_set NAME on|off           that setting, CLIP in vm.conf: on unless turned off
# What went last to each VM is remembered by its hash, in the session's runtime folder (gone at logout), never the text.

GUESTCLIP=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guestclip.py
CLIP_SENT_DIR=${XDG_RUNTIME_DIR:-/run/user/$UID}/nightdrive-garage-clip

clip_on() { ! grep -qx 'CLIP=off' "$(dir "$1")/vm.conf"; }

clip_set() {
  need "$1"
  [[ ${2:-} == on || ${2:-} == off ]] || die "set NAME clip on|off"
  conf "$1" CLIP "$2"
}

# guestclip NAME ARGS…: guestclip.py on its guest agent's socket, what went remembered by qemu's pid (a VM started again
# has an empty clipboard: the same text goes again)
guestclip() {
  local name=$1 d; d=$(dir "$1"); shift
  (cd "$d" && python3 -I "$GUESTCLIP" qga.sock "$name" "$@" --sent "$CLIP_SENT_DIR/$name" "$(cat "$d/pid")")
}

clip_text() {
  local name=${1:-} from=()
  shift || true
  case ${1:-} in
    --clipboard) from=(--clipboard) ;;
    "") ;;
    *) die "clip NAME [--clipboard]" ;;
  esac
  need "$name"; running "$name" || die "$name isn't running"
  [[ $(vm_state "$name") == paused* ]] && die "$name is paused: resume it first"
  local how rc=0
  how=$(guestclip "$name" "${from[@]}") || rc=$?
  ((rc == 3)) && die "$name's guest agent doesn't answer (is qemu-guest-agent in it?): v types the text into it instead"
  ((rc == 0)) || exit "$rc"
  case $how in
    exec) echo "On $name's clipboard" ;;
    file) echo "Sent to $name: Nightdrive in it puts it on its clipboard" ;;
  esac
}

# Quiet, whatever happens: the window got the keyboard, nobody pressed anything. A VM without a guest agent yet (booting)
# isn't remembered as sent, so its next focus tries again
clip_auto() {
  local pid=${1:-} d name=""
  [[ $pid =~ ^[0-9]+$ ]] || die "clip-auto PID: qemu's pid"
  for d in "$ROOT"/*/; do
    [[ $(cat "$d/pid" 2>/dev/null) == "$pid" ]] && { name=$(basename "$d"); break; }
  done
  [[ -n $name ]] && running "$name" && clip_on "$name" || return 0
  [[ $(vm_state "$name") == paused* ]] && return 0
  guestclip "$name" --clipboard --if-changed >/dev/null 2>&1 || true
}
