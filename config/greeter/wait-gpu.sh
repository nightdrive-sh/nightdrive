# Holds greetd back at boot until every graphics card with a kernel driver has its DRM device (/dev/dri/cardN).
# Installed as /etc/greetd/wait-gpu.sh and run as root by greetd-wait-gpu.conf (ExecStartPre), so it comes before
# anything greetd starts: the login screen, the autologin session and the text login alike. Run with sh: /etc/greetd's
# files are labelled as config for SELinux, read but not executed.
#
# Why: greetd starts once the system is up, but nothing orders it after the graphics driver, which udev loads while
# the boot goes on. NVIDIA's (akmod-nvidia, a large module checked against Secure Boot's key) may come seconds later:
# Hyprland then finds only the firmware's framebuffer (simpledrm), aborts, and the PC ends at the text login (#2525).
# The driver isn't put in the initramfs instead: RPM Fusion leaves it out on purpose (99-nvidia-dracut.conf), as
# akmods builds it for a new kernel only after that kernel's initramfs, and a driver update would leave an older
# module there than the libraries expect.
LIMIT=30          # seconds at most; the login screen falls back to a text login if a card still has no driver then
IDLE=4            # quarter-seconds of an idle udev with a card still missing: no driver is coming for it

# The PCI display controllers (class 0x03…) that have a driver to load but no DRM device yet, by address
missing() {
  for dev in /sys/bus/pci/devices/*; do
    case $(cat "$dev/class" 2>/dev/null) in 0x03*) ;; *) continue ;; esac
    # Handed to a virtual machine: it stays without a card here
    case $(readlink "$dev/driver" 2>/dev/null) in */vfio-pci|*/pci-stub) continue ;; esac
    # No module knows it (an unsupported card): nothing to wait for
    [ -n "$(modprobe -R "$(cat "$dev/modalias" 2>/dev/null)" 2>/dev/null)" ] || continue
    ls -d "$dev"/drm/card* >/dev/null 2>&1 || printf '%s ' "${dev##*/}"
  done
}

# Time since boot in hundredths of a second (/proc/uptime has two decimals): the clock, as sh counts only whole numbers.
# Counting the loop's rounds instead missed the time missing() itself takes (modprobe, sysfs), over half of it
now() { read -r up _ </proc/uptime; echo "${up%.*}${up#*.}"; }
waited() { w=$(($(now) - start)); echo "$((w / 100)).$((w % 100 / 10)) s"; }

start=$(now); idle=0; looped=0
while cards=$(missing); [ -n "$cards" ]; do
  # udev's queue holds the card's event while its driver loads; empty with a card still missing, the driver failed
  # (unsigned under Secure Boot, not built for this kernel): no use waiting the full LIMIT
  if udevadm settle --timeout=0 2>/dev/null; then idle=$((idle + 1)); else idle=0; fi
  if [ "$idle" -ge "$IDLE" ] || [ $(($(now) - start)) -ge $((LIMIT * 100)) ]; then
    echo "nightdrive: no graphics driver for ${cards% } after $(waited), starting anyway"
    exit 0
  fi
  looped=1
  sleep 0.25
done
# In greetd's journal: how long the boot waited, to see it when the login screen comes up slowly
[ "$looped" = 1 ] && echo "nightdrive: waited $(waited) for the graphics driver"
exit 0
