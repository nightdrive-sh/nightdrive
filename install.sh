#!/bin/bash
# Sets up this environment on Fedora 44: Fedora Asahi Remix's Minimal image on an Apple Silicon Mac (aarch64), the
# netinstall's "Fedora Custom Operating System" on a PC (x86_64) or in a virtual machine, or the KDE edition of
# either (installs from before 25.10.2026: KDE stays, as a fallback session). Nightdrive adds what it needs
# (packages.txt and the machine's packages-pc.txt or packages-asahi.txt) instead of removing a desktop's apps. Which
# machine it is comes from `nightdrive platform machine` (asahi | pc | vm): the notch setting, the keyboard question and
# the Mac's removals are for asahi, a PC gets its display and keyboard settings in config/hypr/local.lua and, with an
# NVIDIA card, the driver from RPM Fusion.
#   ./install.sh               asks nothing (sudo's password once at the start; on a Mac still on Asahi Minimal's us
#                              keyboard layout, the layout) and runs unattended: removes what a Mac doesn't use
#                              (packages-remove-asahi.txt), updates the system, installs packages, fonts, the notch
#                              setting, links the configs, gives a Minimal system the desktop's settings (graphical
#                              boot, the firewall as on Fedora KDE, SSH off until Remote login turns it on), installs
#                              Claude Code, Tailscale and Apostrophe (ALWAYS), Nightdrive's apps (Mail, Contacts,
#                              Deck, Ferry), the login screen and boot splash (active from the next boot: the splash, then
#                              the desktop under the login screen as its lock) and the optional parts that are Default
#                              on in plugins.txt.
#   ./install.sh --choose      first lists the optional parts (1Password, web apps…, plugins.txt) and, on a Mac, the
#                              removals to tick or untick. Home Assistant, if chosen, asks for its address at the end.
#   ./install.sh --with 1password,slack   these parts on top of the defaults (ids: --dry-run lists them)
#   ./install.sh --without youtube       the defaults without these (--with and --without combine; with --choose they
#                                        set what starts ticked)
#   ./install.sh --all / --none / --defaults   every optional part / none / the defaults (Default on in plugins.txt);
#                              the ALWAYS parts and the apps are in with each (--without leaves one out)
#   ./install.sh --keyboard "fi mac"   the keyboard layout and variant (xkb names, e.g. "de", "us intl") for the login
#                              screen, the desktop and the text console, without asking
#   ./install.sh --dry-run     shows the optional parts, the packages and system settings it would add, what it would
#                              remove, and stops
#   ./install.sh --no-greeter  no Nightdrive login screen: the distribution's own where there's one (Fedora KDE's; pick
#                              "Hyprland" there), otherwise greetd's text login, which starts the desktop after it
#   ./install.sh --no-autologin  the Nightdrive login screen before the desktop starts, instead of as its lock
#   ./install.sh --no-splash   keeps Fedora's boot splash and the GRUB menu
#   ./install.sh --vm          the virtual machine settings even if it isn't detected as one (docs/vm.md)
#   ./install.sh --no-nvidia   leaves an NVIDIA card's driver alone (e.g. one installed by hand); docs/pc.md
# --choose needs a terminal. What was skipped can be added later: launcher › System › Install (Recommended, Webapp,
# Plugins), or `nightdrive plugins install ID`.
# Run as a regular user; sudo asks for the password once at the start.
set -euo pipefail
repo=$(cd "$(dirname "$0")" && pwd)
# Part of Nightdrive like Claude Code, so not asked: Tailscale is quiet until it's logged in, Apostrophe opens the .md
# files (Welcome's do-it-yourself path shows the apps' READMEs in it). Nightdrive's own apps (group app in plugin.conf:
# Mail, Contacts, Deck, Ferry) are too, Mail and Contacts quiet until their accounts are set up, Ferry until Tailscale
# is (its server listens on 127.0.0.1 only). Folders in plugins/, so their packages and services stay out of the core.
ALWAYS=(tailscale apostrophe)
machine=""; nvidia=1; secureboot=0; greeter=1; autologin=1; splash=1; dry=0; choose=0; remove=1   # machine: "" = detected
base=""; with=""; without=""; keyboard=""   # base: all | none | defaults, "" = the defaults
usage() { sed -n '/^#   \.\/install\.sh /,/^# Run as a regular user/p' "$0" | sed 's/^# \{0,1\}//'; }
while (( $# )); do
  case $1 in
    --vm) machine=vm ;;
    --no-nvidia) nvidia=0 ;;
    --greeter) ;;              # the default now; still accepted
    --no-greeter) greeter=0 ;;
    --no-autologin) autologin=0 ;;
    --no-splash) splash=0 ;;
    --all) base=all ;;
    --none) base=none ;;
    --defaults) base=defaults ;;
    --choose) choose=1 ;;
    --with=*) with+=,${1#*=} ;;
    --without=*) without+=,${1#*=} ;;
    --with|--without) [[ -n ${2:-} ]] || { echo "$1 needs a list of ids, e.g. $1 deck,youtube" >&2; exit 2; }
                      if [[ $1 == --with ]]; then with+=,$2; else without+=,$2; fi; shift ;;
    --keyboard=*) keyboard=${1#*=} ;;
    --keyboard) [[ -n ${2:-} ]] || { echo "--keyboard needs a layout, e.g. --keyboard \"fi mac\"" >&2; exit 2; }
                keyboard=$2; shift ;;
    --dry-run) dry=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1 (see ./install.sh --help)" >&2; exit 2 ;;
  esac
  shift
done
(( choose )) && [[ ! -t 0 ]] && { echo "--choose needs a terminal to ask in" >&2; exit 2; }
# Fedora Minimal has no login screen of its own to keep (Fedora KDE's is plasmalogin, an older one's sddm): with
# --no-greeter it gets greetd's text login (config/greeter/switch.sh: OTHER_DMS, text)
# (|| true: systemctl fails when there are none, and pipefail with set -e would end the script silently)
other_dm=$(systemctl list-unit-files --no-legend plasmalogin.service sddm.service gdm.service lightdm.service 2>/dev/null | wc -l || true)
pkgs() { grep -vE '^\s*(#|$)' "$1" | tr '\n' ' '; }
# The names of these that are installed (rpm prints "package X is not installed" for the rest)
installed() { (( $# )) && rpm -q --qf '%{NAME}\n' "$@" 2>/dev/null | grep -v ' ' | sort -u | tr '\n' ' ' || true; }

# --- The machine: asahi | pc | vm, its display adapters and the keyboard layout Fedora's installer set ---
platform="$repo/config/hypr/scripts/platform"
[[ -n $machine ]] || machine=$("$platform" machine)
gpus=$("$platform" gpu)
read -r kb_layout kb_variant _ <<<"$("$platform" keyboard)"
# The keyboard layout: Asahi Minimal's first boot doesn't ask for it and leaves it us, and the password is typed with it
# already at the first lock, so a Mac asks here, once (not on a second run: setup.json's welcome is written at the end).
# --keyboard sets it on any machine. Set with localectl after sudo, read again by the login screen's installer.
kb_valid() {  # kb_valid LAYOUT [VARIANT]: names xkb knows
  [[ $1 =~ ^[a-z0-9_-]+$ && ${2:-} =~ ^[a-z0-9_-]*$ ]] || return 1
  localectl list-x11-keymap-layouts 2>/dev/null | grep -qx "$1" || return 1
  [[ -z ${2:-} ]] || localectl list-x11-keymap-variants "$1" 2>/dev/null | grep -qx "$2"
}
kb_set=""; kb_ask=0
if [[ -n $keyboard ]]; then
  read -r kb_a kb_b _ <<<"$keyboard"
  kb_valid "$kb_a" "${kb_b:-}" || { echo "--keyboard: not a layout (and variant) xkb knows: $keyboard (localectl list-x11-keymap-layouts)" >&2; exit 2; }
  kb_set="$kb_a${kb_b:+ $kb_b}"
elif [[ $machine == asahi && $kb_layout == us && -z ${kb_variant:-} && -t 0 ]] \
     && ! grep -qs '"welcome"' "$HOME/.local/state/nightdrive/setup.json"; then
  kb_ask=1
fi
if (( kb_ask && !dry )); then
  echo "Keyboard layout: Fedora Asahi Remix leaves it us, and the login screen's password is typed with it. Type the"
  echo "layout and its variant, e.g. \"fi mac\", \"de mac\", \"gb mac\" (the Mac variants), or press Enter to keep us."
  while true; do
    read -rp "Keyboard layout: " kb_a kb_b _
    [[ -z $kb_a ]] && break
    if kb_valid "$kb_a" "${kb_b:-}"; then kb_set="$kb_a${kb_b:+ $kb_b}"; break; fi
    echo "  not a layout (and variant) xkb knows: localectl list-x11-keymap-layouts, list-x11-keymap-variants LAYOUT"
  done
  echo
fi
[[ -z $kb_set ]] || read -r kb_layout kb_variant _ <<<"$kb_set"
# Only plain xkb names go into the Lua strings (local.lua below)
[[ $kb_layout =~ ^[a-z0-9_,-]+$ ]] || kb_layout=us
[[ ${kb_variant:-} =~ ^[a-z0-9_,-]*$ ]] || kb_variant=""
kb_desc="keyboard: $kb_layout${kb_variant:+ $kb_variant}"
# hyprland.lua's own layout is the Finnish Mac one. A PC always gets the system's layout in local.lua, a Mac or a VM only
# when the system's isn't Finnish: otherwise a US or German Mac would type with the Finnish layout
own_kb=0; [[ $machine == pc || $kb_layout != fi ]] && own_kb=1
kb_lua="hl.config({ input = { kb_layout = \"$kb_layout\", kb_variant = \"$kb_variant\" } })   -- the system's layout (localectl), not the Finnish Mac one"
# NVIDIA: Hyprland needs the proprietary driver (nouveau is too slow and lacks features); a PC only, a VM has its own adapter
[[ $machine == pc && " $gpus " == *" nvidia "* ]] || nvidia=0
case $machine in
  asahi) machine_desc="Apple Silicon Mac (Fedora Asahi Remix, $kb_desc)" ;;
  vm)    machine_desc="virtual machine ($kb_desc)" ;;
  *)     machine_desc="PC ($(uname -m)${gpus:+, graphics: $gpus}, $kb_desc)" ;;
esac
# The machine's own packages (packages-pc.txt, packages-asahi.txt; a VM has none)
own_pkgs=$repo/packages-$machine.txt; [[ -f $own_pkgs ]] || own_pkgs=""

# --- What Fedora Minimal leaves as a server's (Fedora KDE has the desktop's): done after the packages ---
# It starts to a text console (multi-user.target), where no login screen starts
to_graphical=0; [[ $(systemctl get-default 2>/dev/null) == graphical.target ]] || to_graphical=1
# firewalld picks its settings by the edition when it's installed (its posttrans, by VARIANT_ID): a server's
# FedoraServer zone, which lets in little more than ssh, and polkit's server rule, which asks the password for every
# change. The polkit link tells which, without root
fw_policy=/usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.policy
fw_desktop=0; [[ $(readlink "$fw_policy" 2>/dev/null) == *.server.policy.choice ]] && fw_desktop=1
# sshd on by the preset (Minimal's 90-default; KDE's 81-desktop turns it off), not by the user. Not over ssh: the
# install would cut its own connection (a VM reached over ssh)
ssh_preset=0
[[ -z ${SSH_CONNECTION:-} && $(systemctl list-unit-files --no-legend sshd.service 2>/dev/null | awk '{ print $2, $3 }') == "enabled enabled" ]] && ssh_preset=1

# --- Removals (a Mac only, packages-remove-asahi.txt): what this system has of them ---
# Asahi Minimal's server services and other hardware's firmware. Nothing of a desktop's apps is removed any more: on
# Fedora KDE (an install from before) KDE's apps stay
removable=()
[[ $machine != asahi ]] || read -ra removable <<<"$(installed $(pkgs "$repo/packages-remove-asahi.txt"))"

# --- Optional parts (plugins.txt and the plugin folders, plugins/<id>/): chosen now, installed at the end ---
ids=(); names=(); descs=(); groups=(); bundled=(); on=()
while IFS=$'\t' read -r id name _ desc def _ _ group dir _; do
  ids+=("$id"); names+=("$name"); descs+=("$desc"); groups+=("$group"); on+=("$([[ $def == on ]] && echo 1 || echo 0)")
  # An app with bundled=no (Garage) is listed with the apps but not ticked: one to pick, not one every install gets
  bundled+=("$([[ $group == app ]] && ! grep -qx 'bundled=no' "$dir/plugin.conf" 2>/dev/null && echo 1 || echo 0)")
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
for i in "${!ids[@]}"; do [[ " ${ALWAYS[*]} " == *" ${ids[i]} "* || ${bundled[i]} == 1 ]] && on[i]=1; done
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
  list="${#removable[@]} installed packages a Mac doesn't use:"
  for i in "${removable[@]}"; do (( ${#list} + ${#i} + 3 <= w )) || { list+=" …"; break; }; list+=" $i"; done
  echo
  printf '  %2d [%s] %-17s %s\n' $removal_row "$( (( remove )) && echo x || echo ' ')" "Remove services" "$list"
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
           elif [[ $a == "$removal_row" ]] && (( ${#removable[@]} )); then remove=$(( 1 - remove ))
           else echo "  not a number from the list: $a"; fi ;;
      esac
    done
  done
fi
chosen=(); for i in "${!ids[@]}"; do [[ ${on[i]} == 1 ]] && chosen+=("${ids[i]}"); done
if (( dry )); then
  show_parts; echo; echo "Would install: ${chosen[*]:-(no optional parts)}"
  # The lists' packages not here yet (groups, @…, left out: dnf installs what of them is missing)
  lists=("$repo/packages.txt" "$repo/packages-hyprland.txt" ${own_pkgs:+"$own_pkgs"})
  missing=$(for p in $(cat "${lists[@]}" | grep -vE '^\s*(#|$|@)'); do rpm -q --whatprovides "$p" >/dev/null 2>&1 || echo "$p"; done)
  echo "Packages (${lists[*]##*/}): $(if [[ -n $missing ]]; then echo "$missing" | wc -l; else echo none; fi) to add"
  [[ -z $missing ]] || echo $missing | fold -s -w 100 | sed 's/^/  /'
  if (( remove && ${#removable[@]} )); then echo "Would remove:"; echo "${removable[*]}" | fold -s -w 100 | sed 's/^/  /'
  else echo "Would remove: nothing"; fi
  (( kb_ask )) && echo "Would ask for the keyboard layout (still Asahi Minimal's us)"
  [[ -z $kb_set ]] || echo "Would set the keyboard layout: $kb_set"
  (( to_graphical )) && echo "Would boot to the login screen: systemctl set-default graphical.target"
  (( greeter || other_dm )) || echo "Would make greetd's text login the login screen (--no-greeter, no other login screen here)"
  (( fw_desktop )) && echo "Would give the firewall the desktop's settings: the FedoraWorkstation zone, firewalld's desktop polkit rule"
  (( ssh_preset )) && echo "Would turn SSH off (on by Fedora Minimal's preset) unless Remote login looks after it already"
  exit 0
fi
echo "Optional parts: ${chosen[*]:-none}"
(( remove && ${#removable[@]} )) && echo "Removing: ${#removable[@]} packages (packages-remove-asahi.txt)"

# sudo once: the system update and the compiling take long, and the password asked again halfway would stop the
# install. Kept alive until the script exits.
sudo -v
while sleep 50; do kill -0 $$ 2>/dev/null || exit; sudo -n -v 2>/dev/null; done &
keepalive=$!
trap 'kill $keepalive 2>/dev/null' EXIT

if [[ -n $kb_set ]]; then
  # Before the packages: the login screen's installer and local.lua below read it
  echo "==> Keyboard layout: $kb_set (the login screen, the desktop and the text console)"
  sudo localectl set-x11-keymap "$kb_layout" "" "${kb_variant:-}"
fi

if (( remove && ${#removable[@]} )); then
  # Before the update, which would otherwise download new versions of them only for them to go minutes later
  echo "==> Removing what a Mac doesn't use (packages-remove-asahi.txt; --choose unticks it)"
  # dnf also removes what only they needed: the packages.txt ones already here are marked as wanted first
  keep=$(installed $(pkgs "$repo/packages.txt"))
  [[ -z $keep ]] || sudo dnf mark user -y $keep >/dev/null
  sudo dnf remove -y "${removable[@]}"
fi

echo "==> System update (on Fedora KDE an older image would otherwise get a half-updated KDE: file conflicts)"
sudo dnf upgrade --refresh -y

echo "==> Hyprland (Nightdrive's COPR @nightdrive/nightdrive, Hyprland's own packages only)"
"$repo/setup-hyprland-repo.sh"
# Before it: Fedora's nwg-panel supplements hyprland, and dnf would install that panel along (config/system/dnf-excludes.conf)
sudo install -Dm644 "$repo/config/system/dnf-excludes.conf" /etc/dnf/libdnf5.conf.d/90-nightdrive.conf
sudo dnf install -y $(pkgs "$repo/packages-hyprland.txt")

echo "==> Fedora packages"
sudo dnf install -y $(pkgs "$repo/packages.txt")
# install leaves a package that KDE (or, on Asahi Minimal, initial-setup: the sound) already pulled in marked as a
# dependency, and removing that would take it along
sudo dnf mark user -y $(pkgs "$repo/packages.txt") >/dev/null
if [[ -n $own_pkgs ]]; then
  echo "==> This machine's packages (${own_pkgs##*/})"
  # --skip-unavailable: one this architecture lacks (microcode_ctl is x86 only)
  sudo dnf install -y --skip-unavailable $(pkgs "$own_pkgs")
  keep=$(installed $(pkgs "$own_pkgs" | tr ' ' '\n' | grep -v '^@'))
  [[ -z $keep ]] || sudo dnf mark user -y $keep >/dev/null
fi
# The system locale's languages (localectl: LANG and the LC_ ones, e.g. fi_FI's times with en_US's messages). The
# netinstall installs only the language picked there; Asahi's image has them all (glibc-all-langpacks)
if ! rpm -q glibc-all-langpacks >/dev/null 2>&1; then
  langpacks=$(localectl status 2>/dev/null | grep -oE '(LANG|LC_[A-Z]+)=[a-z]{2,3}_' | sed 's/.*=/glibc-langpack-/; s/_$//' | sort -u || true)
  langpacks=$(for p in $langpacks; do rpm -q "$p" >/dev/null 2>&1 || echo "$p"; done)
  [[ -z $langpacks ]] || sudo dnf install -y --skip-unavailable $langpacks
fi
# One that came with Hyprland before the exclude above (a second run of install.sh); one installed on purpose stays
if [[ $(dnf -q -C repoquery --installed --setopt=disable_excludes='*' --qf '%{reason}' nwg-panel 2>/dev/null) == *Dependency ]]; then
  sudo dnf remove -y --setopt=disable_excludes='*' nwg-panel
fi

if (( nvidia )); then
  # RPM Fusion's driver, built for each kernel by akmods. With Secure Boot the module is signed with a key of this machine's
  # own (kmodgenca), which has to be enrolled at the next boot: listed at the end.
  echo "==> NVIDIA driver (RPM Fusion: akmod-nvidia)"
  "$repo/setup-rpmfusion.sh" free nonfree   # its keys checked by fingerprint before its release RPMs go in
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
  echo "==> Files: macOS's partitions hidden from the sidebar (config/system/apple-partitions.rules; still there, mountable by hand)"
  sudo install -Dm644 "$repo/config/system/apple-partitions.rules" /etc/udev/rules.d/61-nightdrive-apple-partitions.rules
  sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=block --action=change || true
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

# Part of the desktop (⌘⌥Enter, the launcher's questions, the usage limits in the top bar), so not asked. setup-claude.sh
# checks the release's signature and puts it in ~/.local/bin, where it keeps itself up to date.
echo "==> Claude Code"
if [[ -x $HOME/.local/bin/claude ]]; then echo "    already installed"
else "$repo/setup-claude.sh" || failed_claude=1; fi

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

# Fedora Minimal's firewall is a server's (see fw_desktop above). The desktop's, as on Fedora KDE: the FedoraWorkstation
# zone, which lets in ports 1025–65535 (LocalSend, AirPlay, mDNS; Remote login's zone copies it), and polkit's desktop
# rule, so an admin in the session changes it without a password. Linked the way firewalld's own install does it, which
# leaves links that are there alone, so updates keep them. Before Remote login: its zone is a copy of the default one
if (( fw_desktop )); then
  echo "==> Firewall: the desktop's settings, as on Fedora KDE (the FedoraWorkstation zone, firewalld's desktop polkit rule)"
  if sudo test -e /etc/firewalld/firewalld-workstation.conf; then
    sudo ln -sf firewalld-workstation.conf /etc/firewalld/firewalld.conf
    if systemctl -q is-active firewalld.service; then
      sudo firewall-cmd -q --set-default-zone=FedoraWorkstation || echo "    the zone switches at the next boot"
    fi
  fi
  sudo ln -sf org.fedoraproject.FirewallD1.desktop.policy.choice "$fw_policy"
  sudo ln -sf org.fedoraproject.FirewallD1.desktop.rules.choice /usr/share/polkit-1/rules.d/org.fedoraproject.FirewallD1.rules
fi
# sshd on by Fedora Minimal's preset (ssh_preset above) and not yet looked after by Remote login (its zone): its setup
# below would take it for the user's choice and trust the networks it's on now. Off, until Settings › Remote login
if (( ssh_preset )) && ! sudo firewall-cmd --permanent --get-zones 2>/dev/null | tr ' ' '\n' | grep -qx nightdrive-home; then
  echo "==> SSH off (Fedora Minimal turns it on): launcher › Settings › Remote login turns it on"
  sudo systemctl disable --now sshd.service
fi

# sshd already on before the install (as in a VM reached over ssh) would otherwise stay open on every network until
# Remote login is turned off and on, or the next update runs this
echo "==> Remote login: SSH only over Tailscale and on the networks you allow (config/hypr/scripts/remote-login)"
if out=$(sudo "$repo/config/hypr/scripts/remote-login" setup); then echo "    $out"
elif (( $? == 1 )); then echo "    nothing to do"
else echo "    failed: nightdrive update tries it again"; fi

# Fedora Minimal starts to a text console (multi-user.target), where no login screen starts
if (( to_graphical )); then
  echo "==> Boot to the login screen (systemctl set-default graphical.target)"
  sudo systemctl set-default graphical.target
fi
if (( greeter )); then
  # Autologin: the desktop starts under the login screen as its lock, so the screen changes hands once at boot
  echo "==> Login screen (greetd + Quickshell); takes effect from the next boot"
  "$repo/config/greeter/install.sh"
  if (( autologin )); then "$repo/config/greeter/switch.sh" autologin; else "$repo/config/greeter/switch.sh" on; fi
elif (( ! other_dm )); then
  # --no-greeter on Fedora Minimal: no login screen to keep, so greetd's text login (greetd is in packages.txt)
  echo "==> Text login (greetd's agreety); takes effect from the next boot"
  "$repo/config/greeter/switch.sh" text
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
{ cat "$offered" 2>/dev/null || true; for i in "${!ids[@]}"; do if [[ ${bundled[i]} == 1 ]]; then echo "${ids[i]}"; fi; done; } \
  | sort -u > "$offered.tmp" && mv "$offered.tmp" "$offered"
"$repo/bin/nightdrive" plugins installed >/dev/null
"$repo/config/fuzzel/sync-apps"
# The first login opens Welcome to Nightdrive (config/welcome), which sets up the rest with Claude. Only an install that
# has never had it: `nightdrive update` never writes this, and a second run of install.sh leaves its state as it is.
setup_state=$HOME/.local/state/nightdrive/setup.json
if ! jq -e 'has("welcome")' "$setup_state" >/dev/null 2>&1; then
  { jq '.welcome = "pending"' "$setup_state" 2>/dev/null || jq -n '{ welcome: "pending" }'; } > "$setup_state.tmp" && mv "$setup_state.tmp" "$setup_state"
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
  (( ${failed_claude:-0} )) && echo "  • Claude Code not installed. Run again: $repo/setup-claude.sh"
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
  next "Log in"
elif (( other_dm )); then
  next "Reboot and pick \"Hyprland\" (not \"Hyprland (uwsm-managed)\") at the login screen."
  next "Log in"
else
  next "Reboot"
  next "Log in at the text login: the desktop starts after it."
fi
next "Nightdrive helps you set up your computer with Welcome to Nightdrive."
if (( greeter )); then
  # Hyprland not starting is the likely failure (a graphics driver): config/greeter/greeter.sh puts a text login in its place
  echo
  echo "If the login screen doesn't start, a text login comes up in its place (or press ctrl+alt+F3): log in, and"
  if (( other_dm )); then
    echo "start-hyprland starts the desktop. Until it's fixed, KDE's login screen can take its place:"
    echo "  ${repo/#$HOME/\~}/config/greeter/switch.sh off"
  else
    echo "start-hyprland starts the desktop. Until it's fixed, the text login can take its place (the desktop starts after it):"
    echo "  ${repo/#$HOME/\~}/config/greeter/switch.sh text"
  fi
fi
