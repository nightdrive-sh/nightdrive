# A VM's qemu, for bin/vm-ctl (sourced after its helpers: die, dir, need, running): the command line that starts it,
# its monitor (QMP) and the guest agent inside it (QGA), both through monitor.py. The command line is the one #1527 got
# Fedora booting with on Asahi (an M2 Max); x86_64 comes with task #1572.

FW=/usr/share/edk2/aarch64
# The M2 Max's performance cluster: a vCPU must not move to an E-core (another MIDR, and KVM stops it)
PCORES=4-11
# The guest's sshd on the host's loopback (docs/vm.md: `ssh -p 2222 localhost`), as SDL shares no clipboard. One
# port, so one VM with it at a time: a second one's qemu fails to start. VM_SSH_PORT moves it (a test VM beside yours)
SSH_PORT=${VM_SSH_PORT:-2222}
MONITOR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/monitor.py

# One command to its QMP or guest agent socket: monitor.py's exit codes (1 failed, 3 no guest agent). From the VM's
# folder, as a socket's path is short (108)
qmp() { (cd "$(dir "$1")" && python3 -I "$MONITOR" qmp qmp.sock "$2" "$1" ${3:+"$3"}); }
qga() { (cd "$(dir "$1")" && python3 -I "$MONITOR" qga qga.sock "$2" "$1" ${3:+"$3"}); }

start() {
  need "$1"; running "$1" && return 0
  local name=$1 d MEM CPUS ISO; d=$(dir "$1")
  # shellcheck disable=SC1091
  source "$d/vm.conf"
  # The disk boots first and the ISO second: an empty disk falls through to the installer, and once it is installed
  # the VM boots from its disk, ISO or not (#1552: with the ISO first, an installed VM went back into the installer)
  local cd=()
  [[ -n $ISO ]] && cd=(-device virtio-scsi-pci -device scsi-cd,drive=cd,bootindex=1
                       -drive "if=none,id=cd,media=cdrom,readonly=on,file=$ISO")
  # SDL, not GTK: GTK's GL window is black on Wayland (eglMakeCurrent failed), and under XWayland qemu aborts when the
  # guest resets the GPU at boot (virgl_renderer_reset: EGL_BAD_ACCESS, the context is GTK's). Needs qemu-ui-sdl.
  # VM_HEADLESS=1: no window at all, for a test VM that mustn't come up on the desktop
  local screen=(-device virtio-gpu-gl-pci,xres=1600,yres=1000 -display sdl,gl=on)
  [[ -n ${VM_HEADLESS:-} ]] && screen=(-device virtio-gpu-pci -display none)
  # A disk image's first boot: its user and the rest, until they have run (lib/firstboot.sh)
  local firstboot=(); mapfile -t firstboot < <(firstboot_args "$name")
  rm -f "$d/qmp.sock" "$d/qga.sock"
  cd "$d"     # the sockets by a short path (qmp, qga)
  setsid -f taskset -c $PCORES qemu-system-aarch64 \
    -name "$name" \
    -machine virt,gic-version=3 -accel kvm -cpu host -smp "$CPUS" -m "${MEM}M" \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$FW/QEMU_EFI-silent-pflash.raw" \
    -drive "if=pflash,format=raw,unit=1,file=$d/vars.raw" \
    -drive "if=none,id=disk,format=qcow2,file=$d/disk.qcow2,discard=unmap,cache=writeback" \
    -device virtio-blk-pci,drive=disk,bootindex=0 \
    "${screen[@]}" \
    -device qemu-xhci -device usb-kbd -device usb-tablet \
    "${cd[@]}" \
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" \
    -device virtio-serial-pci \
    -chardev socket,id=qga,path=qga.sock,server=on,wait=off \
    -device virtserialport,chardev=qga,name=org.qemu.guest_agent.0 \
    "${firstboot[@]}" \
    -qmp unix:qmp.sock,server,nowait \
    -pidfile "$d/pid" \
    -serial "file:$d/serial.log" > "$d/qemu.log" 2>&1
  for _ in $(seq 50); do running "$name" && return 0; sleep 0.1; done
  # The one failure with a known cause: the ssh port another VM holds (one VM with it at a time)
  grep -q "host forwarding" "$d/qemu.log" && die "Another VM has the ssh port ($SSH_PORT): shut it down first"
  die "qemu didn't start: $(tail -3 "$d/qemu.log" | sed 's/^qemu-system-[a-z0-9_]*: //')"
}

# Shut down: the guest agent's, which works whatever the desktop in it does with the power button, else ACPI's power
# button (with KDE logged in nothing happens, and Nightdrive shows its power menu). Prints "acpi" then, so the window
# can say why, if it doesn't go down
stop() {
  need "$1"; running "$1" || return 0
  # The agent answering means the first boot's scripts have run (lib/firstboot.sh): their credentials can go
  qga "$1" guest-shutdown '{"mode": "powerdown"}' >/dev/null 2>&1 && { rm -f "$(dir "$1")/firstboot.creds"; return 0; }
  qmp "$1" system_powerdown >/dev/null
  echo acpi
}

# Pulling the plug works without QMP too: qemu's own process, if its socket doesn't answer
force_off() {
  need "$1"; running "$1" || return 0
  qmp "$1" quit >/dev/null 2>&1 || kill "$(cat "$(dir "$1")/pid")"
}

# The guest's clock to the host's, through its agent: after the host has slept, the guest's clock is behind by as
# long. Quiet without an agent (nothing to do then), as the window asks for it on its own
synctime() {
  need "$1"; running "$1" || return 0
  local rc=0
  qga "$1" guest-set-time "{\"time\": $(date +%s%N)}" >/dev/null 2>&1 || rc=$?
  ((rc == 0 || rc == 3)) || [[ ! -S $(dir "$1")/qga.sock ]] || die "$1: its clock wasn't set"
}

# Its SDL window, found by qemu's pid
display() {
  need "$1"; running "$1" || die "$1 isn't running"
  local addr; addr=$(hyprctl -j clients | jq -r --argjson pid "$(cat "$(dir "$1")/pid")" \
                      '[.[] | select(.pid == $pid)] | first | .address // empty')
  [[ -n $addr ]] || die "No window for $1"
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
}
