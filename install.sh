#!/bin/bash
# Sets up this environment on a fresh Fedora Asahi Remix 44 install (aarch64, MacBook), or Fedora 44 KDE on a PC (x86_64)
# or in a virtual machine. Which one it is comes from `nightdrive platform machine` (asahi | pc | vm): the notch setting
# and the Mac-only removals are for asahi, a PC gets its display and keyboard settings in config/hypr/local.lua and, with
# an NVIDIA card, the driver from RPM Fusion.
#   ./install.sh               asks nothing (sudo's password once at the start) and runs unattended: removes the apps
#                              Nightdrive doesn't use (packages-remove.txt; only on a fresh system, installed under 3
#                              days ago), updates the system, installs packages, fonts, the notch setting, links the
#                              configs, installs Claude Code, Tailscale and Apostrophe (ALWAYS), Nightdrive's apps (Mail,
#                              Deck), the login screen and boot splash (active from the next boot: the splash, then the
#                              desktop under the login screen as its lock) and the optional parts that are Default on in
#                              plugins.txt.
#   ./install.sh --choose      first lists the optional parts (1Password, web apps…, plugins.txt) and the removals to tick
#                              or untick. Home Assistant, if chosen, asks for its address at the end.
#   ./install.sh --with 1password,slack   these parts on top of the defaults (ids: --dry-run lists them)
#   ./install.sh --without youtube       the defaults without these (--with and --without combine; with --choose they
#                                        set what starts ticked)
#   ./install.sh --all / --none / --defaults   every optional part / none / the defaults (Default on in plugins.txt);
#                              the ALWAYS parts and the apps are in with each (--without leaves one out)
#   ./install.sh --dry-run     shows the optional parts, which would be installed and what would be removed, and stops
#   ./install.sh --no-greeter  keeps the distribution's own login screen (pick "Hyprland" there)
#   ./install.sh --no-autologin  the Nightdrive login screen before the desktop starts, instead of as its lock
#   ./install.sh --no-splash   keeps Fedora's boot splash and the GRUB menu
#   ./install.sh --keep-apps   keeps the KDE apps and system services that are otherwise removed (packages-remove*.txt)
#   ./install.sh --debloat     removes them also on a system that isn't fresh
#   ./install.sh --no-kde      removes Plasma entirely (needs the greeter); experimental, see config/greeter/
#   ./install.sh --vm          the virtual machine settings even if it isn't detected as one (docs/vm.md)
#   ./install.sh --no-nvidia   leaves an NVIDIA card's driver alone (e.g. one installed by hand); docs/pc.md
# --choose needs a terminal. What was skipped can be added later: launcher › System › Install (Recommended, Webapp,
# Plugins), or `nightdrive plugins install ID`.
# Run as a regular user; sudo asks for the password once at the start.
set -euo pipefail
repo=$(cd "$(dirname "$0")" && pwd)
FRESH_DAYS=3                     # a system installed less than this many days ago gets the removals by default
# Part of Nightdrive like Claude Code, so not asked: Tailscale is quiet until it's logged in, Apostrophe opens the .md
# files (Welcome's do-it-yourself path shows the apps' READMEs in it). Nightdrive's own apps (group app in plugin.conf:
# Mail, Deck) are too, Mail until its account is set up. Folders in plugins/, so their packages and services stay out of
# the core.
ALWAYS=(tailscale apostrophe)
debloat=""; machine=""; nvidia=1; secureboot=0; greeter=1; autologin=1; splash=1; nokde=0; dry=0; choose=0   # debloat: 1 | 0, "" = by the system's age; machine: "" = detected
base=""; with=""; without=""     # base: all | none | defaults, "" = the defaults
usage() { sed -n '6,30p' "$0" | sed 's/^# \{0,1\}//'; }
while (( $# )); do
  case $1 in
    --debloat) debloat=1 ;;
    --keep-apps) debloat=0 ;;
    --vm) machine=vm ;;
    --no-nvidia) nvidia=0 ;;
    --greeter) ;;              # the default now; still accepted
    --no-greeter) greeter=0 ;;
    --no-autologin) autologin=0 ;;
    --no-splash) splash=0 ;;
    --no-kde) nokde=1 ;;
    --all) base=all ;;
    --none) base=none ;;
    --defaults) base=defaults ;;
    --choose) choose=1 ;;
    --with=*) with+=,${1#*=} ;;
    --without=*) without+=,${1#*=} ;;
    --with|--without) [[ -n ${2:-} ]] || { echo "$1 needs a list of ids, e.g. $1 deck,youtube" >&2; exit 2; }
                      if [[ $1 == --with ]]; then with+=,$2; else without+=,$2; fi; shift ;;
    --dry-run) dry=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1 (see ./install.sh --help)" >&2; exit 2 ;;
  esac
  shift
done
(( choose )) && [[ ! -t 0 ]] && { echo "--choose needs a terminal to ask in" >&2; exit 2; }
(( nokde && !greeter )) && { echo "--no-kde removes the KDE login screen, so it can't be combined with --no-greeter" >&2; exit 2; }
pkgs() { grep -vE '^\s*(#|$)' "$1" | tr '\n' ' '; }
# The names of these that are installed (rpm prints "package X is not installed" for the rest)
installed() { (( $# )) && rpm -q --qf '%{NAME}\n' "$@" 2>/dev/null | grep -v ' ' | sort -u | tr '\n' ' ' || true; }

# --- The machine: asahi | pc | vm, its display adapters and the keyboard layout Fedora's installer set ---
platform="$repo/config/hypr/scripts/platform"
[[ -n $machine ]] || machine=$("$platform" machine)
gpus=$("$platform" gpu)
read -r kb_layout kb_variant _ <<<"$("$platform" keyboard)"
# Only plain xkb names go into the Lua strings (local.lua below)
[[ $kb_layout =~ ^[a-z0-9_,-]+$ ]] || kb_layout=us
[[ ${kb_variant:-} =~ ^[a-z0-9_,-]*$ ]] || kb_variant=""
kb_desc="keyboard: $kb_layout${kb_variant:+ $kb_variant}"
# hyprland.lua's own layout is the Finnish Mac one. A PC always gets the system's layout in local.lua, a Mac or a VM only
# when the system's isn't Finnish: otherwise a US or German Mac would type with the Finnish layout
own_kb=0; [[ $machine == pc || $kb_layout != fi ]] && own_kb=1
kb_lua="hl.config({ input = { kb_layout = \"$kb_layout\", kb_variant = \"$kb_variant\" } })   -- the layout Fedora's installer set (localectl), not the Finnish Mac one"
# NVIDIA: Hyprland needs the proprietary driver (nouveau is too slow and lacks features); a PC only, a VM has its own adapter
[[ $machine == pc && " $gpus " == *" nvidia "* ]] || nvidia=0
case $machine in
  asahi) machine_desc="Apple Silicon Mac (Fedora Asahi Remix, $kb_desc)" ;;
  vm)    machine_desc="virtual machine ($kb_desc)" ;;
  *)     machine_desc="PC ($(uname -m)${gpus:+, graphics: $gpus}, $kb_desc)" ;;
esac

# --- Removals (packages-remove*.txt): what this system has of them, and whether it's fresh ---
# Someone trying Nightdrive on the system they already use shouldn't lose KMail or printing without seeing the list, so the
# removals default to on only on a fresh install. /etc/machine-id is written at the first boot (an image's rpm install
# times are the image's build date, so they can't tell).
removable=$(installed $(pkgs "$repo/packages-remove.txt") $(rpm -qa --qf '%{NAME}\n' 'libreoffice-*' 2>/dev/null))
[[ $machine != asahi ]] || removable+=$(installed $(pkgs "$repo/packages-remove-asahi.txt"))
read -ra removable <<<"$removable"
age_days=$(( ( $(date +%s) - $(stat -c %Y /etc/machine-id 2>/dev/null || echo 0) ) / 86400 ))
fresh=$(( age_days < FRESH_DAYS ))
[[ -n $debloat ]] || debloat=$fresh

# --- Optional parts (plugins.txt and the plugin folders, plugins/<id>/): chosen now, installed at the end ---
ids=(); names=(); descs=(); groups=(); on=()
while IFS=$'\t' read -r id name _ desc def _ _ group _; do
  ids+=("$id"); names+=("$name"); descs+=("$desc"); groups+=("$group"); on+=("$([[ $def == on ]] && echo 1 || echo 0)")
done < <("$repo/bin/nightdrive" plugins)
# Shown by group like the launcher's Install menu; installed in the file's order. order: row number - 1 → index
order=()
for g in app recommended webapp plugin; do
  for i in "${!ids[@]}"; do [[ ${groups[i]} == "$g" ]] && order+=("$i"); done
done
declare -A group_title=([app]="Nightdrive apps" [recommended]="Recommended apps" [webapp]="Web apps" [plugin]="Plugins")
case $base in
  all) on=("${on[@]/*/1}") ;;
  none) on=("${on[@]/*/0}") ;;
esac
for i in "${!ids[@]}"; do [[ " ${ALWAYS[*]} " == *" ${ids[i]} "* || ${groups[i]} == app ]] && on[i]=1; done
# --with/--without: ids (or names) separated by commas
toggle_listed() {  # toggle_listed LIST 0|1
  local list w i found
  IFS=, read -ra list <<<"$1"
  for w in "${list[@]}"; do
    [[ -n $w ]] || continue
    found=0
    for i in "${!ids[@]}"; do
      [[ ${ids[i],,} == "${w,,}" || ${names[i],,} == "${w,,}" ]] && { on[i]=$2; found=1; }
    done
    (( found )) || { echo "unknown optional part: $w (available: ${ids[*]})" >&2; exit 2; }
  done
}
toggle_listed "$with" 1
toggle_listed "$without" 0
all_row=$(( ${#ids[@]} + 1 ))        # after the optional parts: "Install all", then the removals
removal_row=$(( ${#ids[@]} + 2 ))
all_on() { [[ " ${on[*]} " != *" 0 "* ]]; }
show_parts() {
  local i r w=$(( $(tput cols 2>/dev/null || echo 100) - 28 )) list prev=""
  for r in "${!order[@]}"; do
    i=${order[r]}
    [[ ${groups[i]} != "$prev" ]] && { [[ -n $prev ]] && echo; echo "  ${group_title[${groups[i]}]:-${groups[i]}}"; prev=${groups[i]}; }
    printf '  %2d [%s] %-17s %s\n' $((r + 1)) "$([[ ${on[i]} == 1 ]] && echo x || echo ' ')" "${names[i]}" "${descs[i]:0:w}"
  done
  echo
  printf '  %2d [%s] %-17s %s\n' $all_row "$(all_on && echo x || echo ' ')" "Install all" "every optional part above"
  (( ${#removable[@]} )) || return 0
  list="${#removable[@]} installed packages Nightdrive doesn't use:"
  for i in "${removable[@]}"; do (( ${#list} + ${#i} + 3 <= w )) || { list+=" …"; break; }; list+=" $i"; done
  echo
  printf '  %2d [%s] %-17s %s\n' $removal_row "$( (( debloat )) && echo x || echo ' ')" "Remove apps" "$list"
  (( fresh )) || printf '         %-17s %s\n' "" "Off by default: this system was installed $age_days days ago, these may be in use."
}
echo "Machine: $machine_desc"
(( nvidia )) && echo "         NVIDIA: installs the driver from RPM Fusion (akmod-nvidia; --no-nvidia leaves it alone)"
echo
if (( choose )); then
  echo "Optional parts. Everything else is the same on every install; these can also be added later (launcher ›"
  echo "System › Install). Type numbers to tick or untick (e.g. 2 5), a = all, n = none, Enter continues."
  while true; do
    echo; show_parts; echo
    read -rp "Toggle (Enter to continue): " ans
    [[ -z $ans ]] && break
    for a in $ans; do
      case $a in
        a) on=("${on[@]/*/1}") ;;
        n) on=("${on[@]/*/0}") ;;
        *) if [[ $a =~ ^[0-9]+$ ]] && (( a >= 1 && a <= ${#ids[@]} )); then on[order[a-1]]=$(( 1 - on[order[a-1]] ))
           elif [[ $a == "$all_row" ]]; then if all_on; then on=("${on[@]/*/0}"); else on=("${on[@]/*/1}"); fi
           elif [[ $a == "$removal_row" ]] && (( ${#removable[@]} )); then debloat=$(( 1 - debloat ))
           else echo "  not a number from the list: $a"; fi ;;
      esac
    done
  done
fi
chosen=(); for i in "${!ids[@]}"; do [[ ${on[i]} == 1 ]] && chosen+=("${ids[i]}"); done
if (( dry )); then
  show_parts; echo; echo "Would install: ${chosen[*]:-(no optional parts)}"
  if (( debloat && ${#removable[@]} )); then echo "Would remove:"; echo "${removable[*]}" | fold -s -w 100 | sed 's/^/  /'
  else echo "Would remove: nothing"; fi
  exit 0
fi
echo "Optional parts: ${chosen[*]:-none}"
(( debloat && ${#removable[@]} )) && echo "Removing: ${#removable[@]} packages (packages-remove*.txt)"

# sudo once: the system update and the compiling take long, and the password asked again halfway would stop the
# install. Kept alive until the script exits.
sudo -v
while sleep 50; do kill -0 $$ 2>/dev/null || exit; sudo -n -v 2>/dev/null; done &
keepalive=$!
trap 'kill $keepalive 2>/dev/null' EXIT

if (( debloat && ${#removable[@]} )); then
  # Before the update, which would otherwise download and install new versions of LibreOffice, KDE PIM and the rest only
  # for them to go minutes later (and fewer KDE packages to update leaves fewer file conflicts on an older image).
  echo "==> Removing unneeded apps and services (packages-remove*.txt; keep them with --keep-apps)"
  # dnf also removes what only they needed: the packages.txt ones already here (ImageMagick…) are marked as wanted first
  keep=$(installed $(pkgs "$repo/packages.txt"))
  [[ -z $keep ]] || sudo dnf mark user -y $keep >/dev/null
  sudo dnf remove -y "${removable[@]}"
fi

echo "==> System update (a fresh install from an older image would otherwise get a half-updated KDE: file conflicts)"
sudo dnf upgrade --refresh -y

echo "==> Hyprland (Nightdrive's COPR @nightdrive/nightdrive, Hyprland's own packages only)"
"$repo/setup-hyprland-repo.sh"
# Before it: Fedora's nwg-panel supplements hyprland, and dnf would install that panel along (config/system/dnf-excludes.conf)
sudo install -Dm644 "$repo/config/system/dnf-excludes.conf" /etc/dnf/libdnf5.conf.d/90-nightdrive.conf
sudo dnf install -y $(pkgs "$repo/packages-hyprland.txt")

echo "==> Fedora packages"
sudo dnf install -y $(pkgs "$repo/packages.txt")
# install leaves a package that KDE already pulled in marked as a dependency, and --no-kde's removal would take it along
sudo dnf mark user -y $(pkgs "$repo/packages.txt") >/dev/null
# One that came with Hyprland before the exclude above (a second run of install.sh); one installed on purpose stays
if [[ $(dnf -q -C repoquery --installed --setopt=disable_excludes='*' --qf '%{reason}' nwg-panel 2>/dev/null) == *Dependency ]]; then
  sudo dnf remove -y --setopt=disable_excludes='*' nwg-panel
fi

if (( nvidia )); then
  # RPM Fusion's driver, built for each kernel by akmods. With Secure Boot the module is signed with a key of this machine's
  # own (kmodgenca), which has to be enrolled at the next boot: listed at the end.
  echo "==> NVIDIA driver (RPM Fusion: akmod-nvidia)"
  fedora=$(rpm -E %fedora)
  sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$fedora.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fedora.noarch.rpm"
  mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled' && secureboot=1
  if (( secureboot )); then
    sudo dnf install -y akmods mokutil openssl
    sudo kmodgenca -a
  fi
  sudo dnf install -y akmod-nvidia
  # Built now for the newest kernel (the one the reboot starts), not at the first boot with a black screen meanwhile
  kernel=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | sort -V | tail -1)
  sudo akmods --force --kernels "$kernel" || true
  modinfo -k "$kernel" nvidia >/dev/null 2>&1 || echo "    The driver didn't build for $kernel yet; akmods tries again at the next boot (sudo journalctl -u akmods)."
fi

if [[ $machine == asahi ]]; then
  echo "==> Notch: the display uses the full top edge (appledrm.show_notch=1, requires a reboot)"
  sudo grubby --update-kernel=ALL --args="appledrm.show_notch=1"
fi
# The MacBook's settings (with the Finnish keyboard) are hyprland.lua's own; another machine or keyboard gets its own in
# local.lua (not in the repo)
if [[ $machine == asahi ]] && (( !own_kb )); then
  :
elif [[ -e $repo/config/hypr/local.lua ]]; then
  echo "==> config/hypr/local.lua already exists, leaving it as is (delete it to regenerate the $machine settings, $kb_desc)"
elif [[ $machine == asahi ]]; then
  echo "==> Keyboard (config/hypr/local.lua): $kb_layout${kb_variant:+ $kb_variant}"
  cat > "$repo/config/hypr/local.lua" <<LUA
-- Generated by: ./install.sh (Apple Silicon Mac). Machine-specific; delete this file and run ./install.sh to regenerate it.
$kb_lua
LUA
elif [[ $machine == vm ]]; then
  echo "==> Virtual machine settings (config/hypr/local.lua)"
  { cat <<'LUA'
-- Generated by: ./install.sh (virtual machine). Machine-specific; delete this file and run ./install.sh to regenerate it.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 2.0 })   -- Parallels "Best for Retina display"; "Scaled": launcher › Settings › Display
hl.config({ cursor = { no_hardware_cursors = true } })                              -- in VMs the hardware cursor is often invisible
LUA
    (( !own_kb )) || echo "$kb_lua"
  } > "$repo/config/hypr/local.lua"
else
  echo "==> PC settings (config/hypr/local.lua): display scale by Hyprland, keyboard $kb_layout${kb_variant:+ $kb_variant}"
  cat > "$repo/config/hypr/local.lua" <<LUA
-- Generated by: ./install.sh (PC). Machine-specific; delete this file and run ./install.sh to regenerate it.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })   -- by the display's size and resolution; launcher › Settings › Display
$kb_lua
LUA
fi

# Firefox makes its profile at its first start, and link.sh themes only a profile that exists. A headless start makes
# the same default-release profile now, so Firefox looks like Nightdrive the first time it opens. Stopped once its
# startup is through (sessionCheckpoints.json), or after 30 s.
ff_dir=$HOME/.config/mozilla/firefox
if command -v firefox >/dev/null && ! compgen -G "$ff_dir/*.default-release" >/dev/null; then
  echo "==> Firefox profile"
  firefox --headless about:blank >/dev/null 2>&1 & ff=$!
  for _ in {1..60}; do compgen -G "$ff_dir/*.default-release/sessionCheckpoints.json" >/dev/null && break; sleep 0.5; done
  # wait returns the killed Firefox's status (143), which set -e would end the whole install on
  kill "$ff" 2>/dev/null; wait "$ff" 2>/dev/null || true
fi
echo "==> Configs (links into ~/.config, fonts)"
"$repo/link.sh"

echo "==> Flatpak apps (flatpaks.txt, from Flathub, per user)"
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
[[ -z $(pkgs "$repo/flatpaks.txt") ]] || flatpak install --user -y --noninteractive flathub $(pkgs "$repo/flatpaks.txt")

# Fonts, ble.sh, GTK settings, default apps: also run by `nightdrive update`
"$repo/setup-user.sh"

# Part of the desktop (⌘⌥Enter, the launcher's questions, the usage limits in the top bar), so not asked. Its own
# installer puts it in ~/.local/bin and keeps it up to date.
echo "==> Claude Code"
if [[ -x $HOME/.local/bin/claude ]]; then echo "    already installed"
else curl -fsSL https://claude.ai/install.sh | bash || failed_claude=1; fi

echo "==> Sleep hook (Wi-Fi and Bluetooth off during sleep, battery drain logging)"
sudo install -m 0755 "$repo/config/system/nightdrive-sleep" /usr/lib/systemd/system-sleep/nightdrive-sleep

echo "==> dnf hook: a part installed or removed with dnf shows up or goes away at once (config/system/nightdrive.actions)"
sudo install -Dm644 "$repo/config/system/nightdrive.actions" /etc/dnf/libdnf5-plugins/actions.d/nightdrive.actions
[[ -e /var/lib/nightdrive/dnf-changed ]] || sudo install -Dm644 /dev/null /var/lib/nightdrive/dnf-changed

echo "==> libinput: trackpad palm rejection (config/system/libinput-apple-mtp.quirks, plus keyd's section if installed)"
{ cat "$repo/config/system/libinput-apple-mtp.quirks"; ! command -v keyd >/dev/null || cat "$repo/plugins/keyd/local-overrides.quirks"; } |
  sudo install -Dm644 /dev/stdin /etc/libinput/local-overrides.quirks

echo "==> logind: F6 (KEY_SLEEP) is do not disturb, the power button opens the power dialog (config/hypr/bindings.lua)"
sudo install -Dm644 "$repo/config/system/logind-ignore-sleep-key.conf" /etc/systemd/logind.conf.d/50-ignore-sleep-key.conf
sudo install -Dm644 "$repo/config/system/logind-power-key.conf" /etc/systemd/logind.conf.d/50-power-key.conf
sudo systemctl kill -s HUP systemd-logind

# sshd already on before the install (as in a VM reached over ssh) would otherwise stay open on every network until
# Remote login is turned off and on, or the next update runs this
echo "==> Remote login: SSH only over Tailscale and on the networks you allow (config/hypr/scripts/remote-login)"
if out=$(sudo "$repo/config/hypr/scripts/remote-login" setup); then echo "    $out"
elif (( $? == 1 )); then echo "    nothing to do"
else echo "    failed: nightdrive update tries it again"; fi

if (( greeter )); then
  # Autologin: the desktop starts under the login screen as its lock, so the screen changes hands once at boot
  echo "==> Login screen (greetd + Quickshell); takes effect from the next boot"
  "$repo/config/greeter/install.sh"
  if (( autologin )); then "$repo/config/greeter/switch.sh" autologin; else "$repo/config/greeter/switch.sh" on; fi
fi
if (( splash )); then
  echo "==> Boot splash (Plymouth, GRUB menu hidden); takes effect from the next boot"
  "$repo/config/splash/install.sh"
fi

# Last of the unattended part. One that fails doesn't stop the rest: it's listed at the end, and can be run again from
# the launcher (System › Install) or with `nightdrive plugins install ID`.
# NIGHTDRIVE_INSTALL: an installer that would open its app for a first setup (Mail) leaves that to the first start.
failed=()
for id in "${chosen[@]}"; do
  NIGHTDRIVE_INSTALL=1 "$repo/bin/nightdrive" plugins install "$id" || failed+=("$id")
done
# The apps were offered now, the ones left out (--without, --choose) too: nightdrive update installs an app only on an
# install that has never had it (bin/nightdrive, offer_apps)
offered=$HOME/.local/state/nightdrive/apps-offered
mkdir -p "${offered%/*}"
{ cat "$offered" 2>/dev/null || true; for i in "${!ids[@]}"; do if [[ ${groups[i]} == app ]]; then echo "${ids[i]}"; fi; done; } \
  | sort -u > "$offered.tmp" && mv "$offered.tmp" "$offered"
"$repo/bin/nightdrive" plugins installed >/dev/null
"$repo/config/fuzzel/sync-apps"
# The first login opens Welcome to Nightdrive (config/welcome), which sets up the rest with Claude. Only an install that
# has never had it: `nightdrive update` never writes this, and a second run of install.sh leaves its state as it is.
setup_state=$HOME/.local/state/nightdrive/setup.json
if ! jq -e 'has("welcome")' "$setup_state" >/dev/null 2>&1; then
  { jq '.welcome = "pending"' "$setup_state" 2>/dev/null || jq -n '{ welcome: "pending" }'; } > "$setup_state.tmp" && mv "$setup_state.tmp" "$setup_state"
fi

if (( nokde )); then
  echo "==> Removing Plasma (experimental). Keeping the cursor theme, GTK fonts and power profiles."
  sudo dnf mark user -y breeze-cursor-theme google-noto-sans-fonts google-noto-sans-mono-fonts google-noto-serif-fonts tuned tuned-ppd vulkan-tools xdg-user-dirs
  sudo rm -f /etc/dnf/protected.d/plasma-desktop.conf
  # dnf shows a summary and asks for confirmation; fedora-asahi-remix-release-kde-desktop stays (it provides system-release)
  sudo dnf remove plasma-desktop plasma-workspace kwin kwin-common kscreen kscreenlocker powerdevil plasma-login-manager kcm-plasmalogin \
    kde-settings-plasmalogin kde-settings-plasma polkit-kde kf6-kwallet pam-kwallet ksshaskpass signon-kwallet-extension plasma-nm plasma-pa \
    plasma-systemsettings bluedevil kde-gtk-config plasma-integration plasma-lookandfeel-fedora \
    plasma-workspace-wallpapers kde-inotify-survey kde-settings-pulseaudio phonon-qt6-backend-vlc pinentry-qt xwaylandvideobridge
fi

# The end: what to do now, numbered (the reboot first; Welcome to Nightdrive asks about the rest), and the way out of a
# broken login screen apart from it, so it doesn't read as one more step
step=0
next() { step=$((step + 1)); echo "  $step. $1"; shift; local l; for l in "$@"; do echo "     $l"; done; }
echo
printf '\e[1m%s\e[0m\n' "Nightdrive is installed."
if (( ${#failed[@]} )) || (( ${failed_claude:-0} )); then
  echo
  echo "Needs a look (an error, see above):"
  (( ${#failed[@]} )) && echo "  • Not installed: ${failed[*]}. Run again: nightdrive plugins install ID"
  (( ${failed_claude:-0} )) && echo "  • Claude Code not installed. Run again: curl -fsSL https://claude.ai/install.sh | bash"
fi
echo
echo "Next:"
if (( nvidia )) && (( secureboot )); then
  next "Before the reboot, as Secure Boot is on: sudo mokutil --import /etc/pki/akmods/certs/public_key.der" \
    "(choose a one-time password). At the reboot the blue MOK screen asks for it: Enroll MOK › Continue › Yes." \
    "Otherwise the NVIDIA driver doesn't load (docs/pc.md)."
fi
if (( greeter )); then
  next "Reboot"
else
  next "Reboot and pick \"Hyprland\" (not \"Hyprland (uwsm-managed)\") at the login screen."
fi
next "Log in"
next "Nightdrive helps you set up your computer with Welcome to Nightdrive."
if (( greeter )); then
  echo
  echo "If the login screen fails: press ctrl+alt+F3, log in and run"
  echo "  ${repo/#$HOME/\~}/config/greeter/switch.sh off"
fi
