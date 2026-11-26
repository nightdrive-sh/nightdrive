# The host's architecture, for bin/garage-ctl (sourced first, after its helpers): the one place that looks at it. What
# differs between an Asahi Mac and a PC is set here, and lib/qemu.sh, lib/images.sh and lib/firstboot.sh only read it.
# GARAGE_ARCH pretends another one: `GARAGE_ARCH=x86_64 garage-ctl cmdline NAME` shows a PC's command line on the Mac.
#   QEMU, MACHINE   qemu's binary and its machine
#   FW_CODE, FW_VARS  the UEFI firmware (read-only) and the template each new VM's vars.raw is copied from
#   GPU             the virgl GPU behind SDL's GL window (the rest of the screen: lib/qemu.sh, screen_args)
#   SOUND           the guest's sound card, output only (lib/qemu.sh, sound_args: PipeWire's on the host)
#   PIN             the host CPUs a VM runs on (taskset), empty for any
#   TTY             the guest's serial console (lib/firstboot.sh: its user is made before the login prompt there)
#   OTHER_ISO       a regex for ISO names that are another architecture's (garage-ctl isos leaves them out)
#   HOST, ISO_HINT  what the host is called and what to look for instead, for iso_check's error
#   PACKAGES        what Fedora needs for it, for the error when something is missing

ARCH=${GARAGE_ARCH:-$(uname -m)}

# shellcheck disable=SC2034  # each variable is read by the files sourced after this one (above)
case $ARCH in
  aarch64)
    QEMU=qemu-system-aarch64
    MACHINE=virt,gic-version=3
    FW_CODE=/usr/share/edk2/aarch64/QEMU_EFI-silent-pflash.raw
    FW_VARS=/usr/share/edk2/aarch64/vars-template-pflash.raw
    GPU=virtio-gpu-gl-pci
    # virtio-snd: Fedora's and Arch Linux ARM's kernels have its driver (CONFIG_SND_VIRTIO). Stream 0 is the output,
    # 1 the input: one stream, so no microphone
    # shellcheck disable=SC2054  # the commas are qemu's, inside one argument
    SOUND=(-device virtio-sound-pci,audiodev=snd0,streams=1)
    # The M2 Max's performance cluster: a vCPU must not move to an E-core (another MIDR, and KVM stops it)
    PIN=4-11
    TTY=ttyAMA0
    OTHER_ISO='x86_64|amd64|i[3-6]86'
    HOST="this Mac runs ARM (aarch64) VMs"; ISO_HINT="an aarch64 or ARM64 download"
    PACKAGES="qemu-system-aarch64-core edk2-aarch64 qemu-img qemu-ui-sdl qemu-ui-opengl qemu-device-display-virtio-gpu-pci-gl qemu-audio-pipewire"
    ;;
  x86_64)
    QEMU=qemu-system-x86_64
    MACHINE=q35
    # Fedora's edk2-ovmf: the 2 MB raw pair without Secure Boot, so no SMM either (qemu's firmware descriptor
    # 51-edk2-ovmf-2m-raw-x64-nosb.json); the 4 MB ones come only as qcow2
    FW_CODE=/usr/share/edk2/ovmf/OVMF_CODE.fd
    FW_VARS=/usr/share/edk2/ovmf/OVMF_VARS.fd
    # virtio-vga rather than -gpu: the same virgl GPU, with a VGA side for the firmware and an early boot
    GPU=virtio-vga-gl
    # Intel HD Audio: every PC's guest has its driver, Windows' too (virtio-snd needs one added there). Output only,
    # so no microphone
    # shellcheck disable=SC2054  # the commas are qemu's, inside one argument
    SOUND=(-device ich9-intel-hda -device hda-output,audiodev=snd0)
    # A hybrid Intel's P- and E-cores are the same architecture to KVM: a vCPU may run on any
    PIN=""
    TTY=ttyS0
    OTHER_ISO='aarch64|arm64'
    HOST="this PC runs x86_64 VMs"; ISO_HINT="an x86_64 or amd64 download"
    PACKAGES="qemu-system-x86-core edk2-ovmf qemu-img qemu-ui-sdl qemu-ui-opengl qemu-device-display-virtio-vga-gl qemu-audio-pipewire"
    ;;
  *) die "Garage runs VMs on aarch64 and x86_64, not on $ARCH" ;;
esac

# Before a VM is made or started: qemu and its firmware are there (they come in packages of their own)
need_qemu() {
  command -v "$QEMU" >/dev/null && [[ -f $FW_CODE && -f $FW_VARS ]] \
    || die "Garage needs qemu for $ARCH: sudo dnf install $PACKAGES"
}

# Before an ISO goes in a VM's drive: one for another architecture only gets "No bootable option or device was found"
# from the firmware, so it is refused with why (lib/isoarch.py reads its EFI loaders; nothing said when it can't tell).
# Running another architecture's ISO would mean qemu emulating its CPU (TCG), much too slow on a Mac to be of use
ISOARCH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/isoarch.py
iso_check() {
  local a; a=$(python3 -I "$ISOARCH" "$1" 2>/dev/null) || a=""
  [[ -z $a || $a == "$ARCH" ]] && return 0
  local what; [[ $a == x86_64 ]] && what="PCs (x86_64)" || what="ARM (aarch64)"
  die "This ISO is for $what; $HOST. Look for $ISO_HINT."
}
