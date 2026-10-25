# Trying Nightdrive in a virtual machine

You can try the whole setup in an aarch64 **Fedora 44** VM on any Apple Silicon Mac. Tested in Parallels Desktop 27:

1. Download Fedora 44's **Everything netinstall** ISO for **aarch64** from [fedoraproject.org/misc](https://fedoraproject.org/misc/)
   (a minimal Fedora, like Asahi Remix's Minimal image; Parallels' own Fedora download may be another release). The KDE
   Plasma Desktop live ISO works too, KDE staying as a fallback.
2. In Parallels: File › New › *Install from an image file*, tick *Customize settings before installation*, give it 8 GB of RAM
   (Deck's Rust build needs it) and under Graphics pick **Best for Retina display**. 3D acceleration (VirGL) is on by default
   for Linux on ARM; Parallels Tools aren't needed.
3. Install Fedora to the disk: in the installer's Software Selection pick *Fedora Custom Operating System*, and create
   your user with *Make this user administrator* ticked. Reboot, log in on the text console and check
   `sudo dmesg | grep virgl` shows `+virgl`.
4. Optional: to work in the Mac's Terminal (copy and paste) instead of the VM window, `ssh` to the address
   `ip -4 -br a` prints: the minimal install has SSH on. Nightdrive's installer turns it off, unless it runs over ssh
   (then Remote login trusts that network).
5. Install as in the [README](../README.md#install) and reboot. The installer detects the VM (`systemd-detect-virt`);
   `./install.sh --vm` forces it.
6. To use ⌘ as Super inside the VM, set Parallels' VM settings › Hardware › Mouse & Keyboard › *Send macOS system shortcuts*
   to *Always*.
7. After restoring a snapshot, run `sudo systemctl restart chronyd` and check `date` a few seconds later: the VM's clock
   goes back with the snapshot (without Parallels Tools nothing syncs it with the Mac), chrony only slews a big gap
   slowly, and dnf rejects new packages whose signatures look made in the future.

On a VM the installer skips the notch step and writes `config/hypr/local.lua` with scale 2.0 (for *Best for Retina display*; pick 1.0 in the
launcher's Settings › Display for *Scaled*), a software cursor and, unless it's Finnish, the keyboard layout Fedora's installer set. It must be Fedora 44,
because the Hyprland COPR builds only for that release. Containers won't work, since Hyprland needs a GPU. Parallels passes
the Mac's battery to the VM; without a display or keyboard backlight their sliders are left out.

## On an Asahi Mac, with qemu

Experimental: Fedora 44 runs under KVM on Fedora Asahi Remix itself, in qemu's own window with a virgl GPU (tested on an
M2 Max: Nightdrive's dev install, Hyprland on the virgl GPU). The 16k-page kernel is no obstacle: the
guest runs Fedora's ordinary 4k one. No libvirt or virt-manager is needed:

```bash
sudo dnf install qemu-system-aarch64-core qemu-img qemu-ui-sdl qemu-ui-opengl qemu-device-display-virtio-gpu-pci-gl
mkdir -p ~/vm && cd ~/vm      # the netinstall ISO in it, as above
cp /usr/share/edk2/aarch64/vars-template-pflash.raw vars.raw
qemu-img create -f qcow2 disk.qcow2 64G
# the performance cores (cpu_capacity 1024): a vCPU must not move to an efficiency core, which reports another CPU
pcores=$(grep -lx 1024 /sys/devices/system/cpu/cpu*/cpu_capacity | sed 's|.*/cpu\([0-9]*\)/.*|\1|' | sort -n | paste -sd,)
taskset -c "$pcores" qemu-system-aarch64 -machine virt,gic-version=3 -accel kvm -cpu host -smp 6 -m 8G \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/edk2/aarch64/QEMU_EFI-silent-pflash.raw \
  -drive if=pflash,format=raw,unit=1,file=vars.raw \
  -drive if=virtio,format=qcow2,file=disk.qcow2,discard=unmap \
  -device virtio-gpu-gl-pci,xres=1600,yres=1000 -display sdl,gl=on \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -device virtio-scsi-pci -device scsi-cd,drive=cd -drive if=none,id=cd,media=cdrom,file=Fedora-Everything-netinst-aarch64-44-1.7.iso \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22
```

Once Fedora is installed, leave out the `scsi-cd` line to boot from the disk; `sudo dnf remove` the packages (and
`edk2-aarch64`) takes it all away again.
- The display is SDL, not GTK: GTK's GL window stays black on Wayland and, under XWayland, qemu aborts when the guest's
  kernel resets the GPU.
- The window holds the keyboard, so the desktop inside gets ⌘ too. ⌘1–⌘0, ⌘⇧1–⌘⇧0, ⌘⌥1–⌘⌥0 and ⌘⇧F stay the Mac's, to
  move the window or leave it.
- Keys arrive by their place on the keyboard: pick the guest's layout to match the Mac's in Fedora's installer. Nothing
  is shared with the clipboard: copy commands in over `ssh -p 2222 localhost` (the minimal install has `sshd` on).
- The window gives the guest its size in real pixels, so the installer's scale 2.0 is right on a Mac's Retina display;
  on a 1× external display, pick 1.0 in the launcher's Settings › Display. Nightdrive's screen in it follows the window:
  tiled smaller or dragged to a new size, the guest takes the window's size, as in UTM and Parallels.
