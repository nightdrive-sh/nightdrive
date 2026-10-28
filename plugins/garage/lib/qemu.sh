# A VM's qemu, for bin/garage-ctl (sourced after its helpers: die, dir, need, running, and lib/arch.sh): the command
# line that starts it, its monitor (QMP) and the guest agent inside it (QGA), both through monitor.py. The command line
# is the one #1527 got Fedora booting with on Asahi (an M2 Max); what differs on a PC (#1572) comes from lib/arch.sh.

MONITOR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/monitor.py
# "Resizing…" over a VM's window while its screen catches up (overlay/shell.qml): one for all VMs, it quits after the last
OVERLAY=$(cd "$(dirname "${BASH_SOURCE[0]}")/../overlay" && pwd)

# One command to its QMP or guest agent socket: monitor.py's exit codes (1 failed, 3 no guest agent). From the VM's
# folder, as a socket's path is short (108)
qmp() { (cd "$(dir "$1")" && python3 -I "$MONITOR" qmp qmp.sock "$2" "$1" ${3:+"$3"}); }
qga() { (cd "$(dir "$1")" && python3 -I "$MONITOR" qga qga.sock "$2" "$1" ${3:+"$3"}); }

# A path as one value in qemu's option syntax, where a comma separates options: doubled, it is a comma of the path's
# (an ISO named "a,b.iso" mustn't add an option b to its drive)
qv() { echo "${1//,/,,}"; }

# The guest's screen, all of it here: the GPU (lib/arch.sh's, virgl) and qemu's window for it. Each time the window
# changes size (tiled, dragged), SDL tells the GPU (a second after its last change: qemu waits for a drag to settle,
# and the picture is stretched till then), and with edid=on (qemu's default, written out as this rests on it) the
# guest gets a new preferred mode, the window's size in real pixels: a Nightdrive guest takes it at once
# (config/hypr/vm-display.lua). SDL draws the picture over the whole window, aspect or not, so a guest that keeps its
# old mode looks stretched. SCREEN is the size it boots with, until the window opens.
# SDL, not GTK: GTK's GL window is black on Wayland (eglMakeCurrent failed), and under XWayland qemu aborts when the
# guest resets the GPU at boot (virgl_renderer_reset: EGL_BAD_ACCESS, the context is GTK's). Needs qemu-ui-sdl.
# GARAGE_HEADLESS=1: no window at all, for a test VM that mustn't come up on the desktop
SCREEN=1600x1000
screen_args() {
  if [[ -n ${GARAGE_HEADLESS:-} ]]; then
    echo -device; echo virtio-gpu-pci; echo -display; echo none
  else
    echo -device; echo "$GPU,xres=${SCREEN%x*},yres=${SCREEN#*x},edid=on"; echo -display; echo sdl,gl=on
  fi
}

# qemu_cmd NAME: its command line, into QEMU_CMD (start runs it, garage-ctl cmdline prints it). Run from the VM's
# folder: the sockets go there by a short path (qmp, qga)
qemu_cmd() {
  local name=$1 d MEM CPUS ISO SSH_PORT SSH_USER; d=$(dir "$1")
  read_conf "$name"
  # The disk boots first and the ISO second: an empty disk falls through to the installer, and once it is installed
  # the VM boots from its disk, ISO or not (#1552: with the ISO first, an installed VM went back into the installer)
  # format=raw, as qemu would otherwise go by what the file says it is: a "downloaded ISO" that is a qcow2 with a
  # backing file could hand the guest any file of the host's (~/.ssh/id_ed25519)
  local cd=()
  [[ -n $ISO ]] && cd=(-device virtio-scsi-pci -device scsi-cd,drive=cd,bootindex=1
                       -drive "if=none,id=cd,media=cdrom,readonly=on,format=raw,file=$(qv "$ISO")")
  local screen=(); mapfile -t screen < <(screen_args)
  # A disk image's first boot: its user and the rest, until they have run (lib/firstboot.sh)
  local firstboot=(); mapfile -t firstboot < <(firstboot_args "$name")
  local pin=(); [[ -n $PIN ]] && pin=(taskset -c "$PIN")
  QEMU_CMD=("${pin[@]}" "$QEMU"
    -name "$name"
    -machine "$MACHINE" -accel kvm -cpu host -smp "$CPUS" -m "${MEM}M"
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$(qv "$FW_CODE")"
    -drive "if=pflash,format=raw,unit=1,file=$(qv "$d/vars.raw")"
    -drive "if=none,id=disk,format=qcow2,file=$(qv "$d/disk.qcow2"),discard=unmap,cache=writeback"
    -device virtio-blk-pci,drive=disk,bootindex=0
    "${screen[@]}"
    -device qemu-xhci -device usb-kbd -device usb-tablet
    "${cd[@]}"
    # The guest's sshd on the host's loopback, at its own port (lib/ssh.sh: `ssh NAME`), as SDL shares no clipboard
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22"
    -device virtio-serial-pci
    -chardev socket,id=qga,path=qga.sock,server=on,wait=off
    -device virtserialport,chardev=qga,name=org.qemu.guest_agent.0
    "${firstboot[@]}"
    -qmp unix:qmp.sock,server,nowait
    -pidfile "$d/pid"
    -serial "file:$d/serial.log")
}

# cmdline NAME: the command start would run, for a test (GARAGE_ARCH=x86_64 shows a PC's): one option a line, those
# before qemu's binary (taskset's) on its first
cmdline() {
  need "$1"; qemu_cmd "$1"
  local a out="" seen=0
  for a in "${QEMU_CMD[@]}"; do
    ((seen)) && [[ $a == -* ]] && out+=$' \\\n '
    [[ $a == "$QEMU" ]] && seen=1
    # Quoted only where the shell needs it (printf %q would escape every comma)
    if [[ $a =~ ^[][A-Za-z0-9_./:,=@+-]+$ ]]; then out+=" $a"; else out+=" $(printf %q "$a")"; fi
  done
  echo "${out# }"
}

start() {
  need "$1"; running "$1" && return 0
  need_qemu
  ensure_port "$1"
  local name=$1 d; d=$(dir "$1")
  qemu_cmd "$name"
  rm -f "$d/qmp.sock" "$d/qga.sock"
  cd "$d"     # the sockets by a short path (qmp, qga)
  setsid -f "${QEMU_CMD[@]}" > "$d/qemu.log" 2>&1
  for _ in $(seq 50); do
    if running "$name"; then
      boot_watch "$name"
      [[ -n ${GARAGE_HEADLESS:-} ]] || setsid -f flock -n "${XDG_RUNTIME_DIR:-/tmp}/nightdrive-garage-resizing.lock" \
        qs -p "$OVERLAY" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.1
  done
  # The one failure with a known cause: its ssh port, which something else on the host listens on now
  local SSH_PORT MEM CPUS ISO SSH_USER; read_conf "$name"
  grep -q "host forwarding" "$d/qemu.log" \
    && die "Port $SSH_PORT, $name's ssh, is taken: \`garage set $name port N\` gives it another"
  die "qemu didn't start: $(tail -3 "$d/qemu.log" | sed 's/^qemu-system-[a-z0-9_]*: //')"
}

# Shut down: the guest agent's, which works whatever the desktop in it does with the power button, else ACPI's power
# button (with KDE logged in nothing happens, and Nightdrive shows its power menu). Its state says which (lib/state.sh:
# stopping, acpi), and "acpi" is printed then, so the window can say why, if it doesn't go down
stop() {
  need "$1"; running "$1" || return 0
  # Paused, the guest agent can't answer and the power button does nothing: it goes on first
  [[ $(vm_state "$1") == paused* ]] && qmp "$1" cont >/dev/null
  # The agent answering means the first boot's scripts have run (lib/firstboot.sh): their credentials can go
  if qga "$1" guest-shutdown '{"mode": "powerdown"}' >/dev/null 2>&1; then
    state_set "$1" stopping; rm -rf "$(dir "$1")/firstboot"; return 0
  fi
  qmp "$1" system_powerdown >/dev/null
  state_set "$1" stopping acpi
  echo acpi
}

# Pulling the plug works without QMP too: qemu's own process, if its socket doesn't answer
force_off() {
  need "$1"; running "$1" || return 0
  qmp "$1" quit >/dev/null 2>&1 || kill "$(cat "$(dir "$1")/pid")"
  state_set "$1" ""
}

# Pause: its CPUs stop where they are (QMP's stop), its memory stays taken; resume goes on from there. Not while it
# shuts down, as the guest is past the point where going on later means anything. Saving its state to the disk
# (savevm) would free the memory too, but the virgl GPU doesn't allow it
pause() {
  need "$1"; running "$1" || die "$1 isn't running"
  local st; read -r st _ < <(vm_state "$1")
  case $st in
    paused)   return 0 ;;
    stopping) die "$1 is shutting down" ;;
  esac
  qmp "$1" stop >/dev/null
  # One paused while it boots is booting again on resume ("booting": bootwait.py stops watching meanwhile)
  state_set "$1" paused "$([[ $st == booting ]] && echo booting)"
}

# Resume: its clock stood still meanwhile, so it is set (synctime), once the state says it runs: without a guest agent
# that takes a few seconds, and the window shouldn't show it paused for those
resume() {
  need "$1"; running "$1" || return 0
  local what="" extra=""
  read -r what _ extra 2>/dev/null < "$(dir "$1")/state" || true
  qmp "$1" cont >/dev/null
  if [[ $what == paused && $extra == booting ]]; then boot_watch "$1"; else state_set "$1" ""; fi
  synctime "$1" || true
}

# The guest's clock to the host's, through its agent: after the host has slept, the guest's clock is behind by as
# long. Quiet without an agent (nothing to do then), as the window asks for it on its own; and while it is paused, as
# its agent can't answer then (resume sets it)
synctime() {
  need "$1"; running "$1" || return 0
  [[ $(vm_state "$1") == paused* ]] && return 0
  local rc=0
  qga "$1" guest-set-time "{\"time\": $(date +%s%N)}" >/dev/null 2>&1 || rc=$?
  ((rc == 0 || rc == 3)) || [[ ! -S $(dir "$1")/qga.sock ]] || die "$1: its clock wasn't set"
}

# Its SDL window's address and workspace, found by qemu's pid ("" while it has none)
window_of() {
  hyprctl -j clients | jq -r --argjson pid "$(cat "$(dir "$1")/pid")" \
    '[.[] | select(.pid == $pid)] | first | "\(.address // "") \(.workspace.name // "")"'
}

# Which running VMs' windows show now, for list: { pid: true|false }, a window on a workspace a monitor shows (its own or
# the special one open over it). {} without Hyprland (a container, a tty): the window then says Display, as before
shown_windows() {
  { hyprctl -j monitors && hyprctl -j clients; } 2>/dev/null | jq -sc '
    ([.[0][] | .activeWorkspace.name, .specialWorkspace.name] | map(select(. != ""))) as $seen
    | [.[1][] | select(.class | startswith("qemu-system-")) | { key: (.pid | tostring), value: (.workspace.name | IN($seen[])) }]
    | from_entries' 2>/dev/null || echo '{}'
}

# Its SDL window, found by qemu's pid. On a workspace it is focused where it is, tiled or floating; in a special one
# (special:bg, the drawer) it comes to the current workspace, tiled: focused there it would only float on top of
# everything, with nothing but Open Garage or a move to put it away again
display() {
  need "$1"; running "$1" || die "$1 isn't running"
  local addr ws ws_id
  read -r addr ws < <(window_of "$1")
  [[ -n $addr ]] || die "No window for $1"
  local cmds=()
  if [[ $ws == special:* ]]; then
    ws_id=$(hyprctl -j monitors | jq -r '[.[] | select(.focused)] | first | .activeWorkspace.id')
    cmds+=("dispatch hl.dsp.window.move({ workspace = $ws_id, window = \"address:$addr\" })"
           "dispatch hl.dsp.window.float({ action = \"disable\", window = \"address:$addr\" })")
  fi
  cmds+=("dispatch hl.dsp.focus({ window = \"address:$addr\" })")
  # One batch, so the window doesn't show floating at its old spot before it is tiled
  local IFS=';'
  hyprctl --batch "${cmds[*]}" >/dev/null
}

# Its window out of sight while the VM runs on: qemu's SDL window can't close without qemu quitting, so it goes to
# special:bg, where ⌘W hides the background apps, without showing it (follow = false). display brings it back into the
# current workspace's grid
hide() {
  need "$1"; running "$1" || die "$1 isn't running"
  local addr ws
  read -r addr ws < <(window_of "$1")
  [[ -n $addr ]] || die "No window for $1"
  [[ $ws == special:bg ]] && return 0
  hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:bg\", follow = false, window = \"address:$addr\" })" >/dev/null
}
