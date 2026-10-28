# A VM's state, for bin/garage-ctl (sourced after its helpers: dir, running) and lib/qemu.sh: one state machine that
# the window, the top bar's menu and its icon all read (garage-ctl list, garage-ctl states), so each says the same.
#
#   stopped   no qemu (its pid file's process is gone)
#   booting   qemu runs, the guest isn't up yet: from start until its guest agent or its sshd answers (lib/bootwait.py),
#             or BOOT_WAIT has passed (a guest with neither, an installer: it counts as up then)
#   running   qemu runs and nothing else is going on
#   stopping  a shutdown was asked for (garage-ctl stop), until qemu has gone; "slow" past STOP_WAIT, when the window
#             offers Force off. A shutdown from inside the guest isn't seen: it is running until qemu has gone
#   paused    its CPUs stopped (garage-ctl pause, QMP's stop), its memory still taken, until resume (lib/qemu.sh)
#
# What isn't simply qemu running or not is kept in the VM's folder, in its file "state": one line, the state and since
# when (epoch seconds), and for stopping "acpi" when it went to the power button (the guest has no agent), for paused
# "booting" when it was paused before its guest was up (resume watches its boot again then). It is written under
# state.lock, as bootwait.py clears "booting" while garage-ctl may write "stopping" or "paused". Without qemu the file
# means nothing: start writes it anew, and list's reading of it ignores it.

BOOT_WAIT=120    # seconds a guest has to answer before it counts as up anyway
STOP_WAIT=60     # seconds before a shutdown that hasn't happened is "slow" (Force off then)
BOOTWAIT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bootwait.py

# state_set NAME WHAT [EXTRA]: its state file says WHAT from now ("" removes it: plain running or stopped)
state_set() {
  local d; d=$(dir "$1")
  (
    flock 9
    if [[ -z $2 ]]; then rm -f "$d/state"; else printf '%s %s%s\n' "$2" "$(date +%s)" "${3:+ $3}" > "$d/state"; fi
  ) 9>"$d/state.lock"
}

# vm_state NAME: "STATE SLOW ACPI", e.g. "stopping true false": what list and states make of the pid and the file
vm_state() {
  running "$1" || { echo "stopped false false"; return; }
  local what="" since=0 extra="" age
  read -r what since extra 2>/dev/null < "$(dir "$1")/state" || true
  [[ $since =~ ^[0-9]+$ ]] || since=0
  age=$(( $(date +%s) - since ))
  case $what in
    # A boot past its wait is up, if bootwait.py has gone (killed) without saying so
    booting)  ((age < BOOT_WAIT)) && echo "booting false false" || echo "running false false" ;;
    stopping) echo "stopping $( ((age >= STOP_WAIT)) && echo true || echo false) $([[ $extra == acpi ]] && echo true || echo false)" ;;
    paused)   echo "paused false false" ;;
    *)        echo "running false false" ;;
  esac
}

# A started VM is booting until its guest answers: bootwait.py watches in the background and clears it then
boot_watch() {
  local d SSH_PORT MEM CPUS ISO SSH_USER; d=$(dir "$1")
  read_conf "$1"
  state_set "$1" booting
  setsid -f python3 -I "$BOOTWAIT" "$d" "${SSH_PORT:-0}" "$BOOT_WAIT" >/dev/null 2>&1 < /dev/null
}

# garage-ctl states: NAME STATE a line, for the top bar's icon (./status), which runs every few seconds: no qemu-img
states() {
  local d name st
  for d in "$ROOT"/*/; do
    [[ -f $d/vm.conf ]] || continue
    name=$(basename "$d"); good_name "$name" || continue
    read -r st _ < <(vm_state "$name")
    echo "$name $st"
  done
}
