# shellcheck shell=bash
# Part of the nightdrive command (sourced by bin/nightdrive): `nightdrive update` and its helpers (offer_apps, as_root).
# The update's steps in order in one place; the repos it pulls and their counts are in repos.sh, the plugins in plugins.sh.

# update: pull Nightdrive (and a private overlay and Deck's source, if any), relink, install new packages, dnf upgrade,
# Flatpak apps, reload the desktop (launcher › Update runs this). Never pulls over local changes: a repo with uncommitted
# work or its own commits is skipped with a note. Whatever was skipped or failed is listed at the end with what to run
# by hand, and the exit status is then 1: "up to date" only when every step ran.
update() {
  local missed=() can_sudo=1
  # sudo asks for the password only on a terminal. Without one (an agent, ssh with a command) it would fail or wait, so
  # the steps that need it are skipped and listed, unless sudo works without asking (a cached password, NOPASSWD).
  [[ -t 0 ]] || sudo -n true 2>/dev/null || can_sudo=0
  deck=${ND_UPDATE_DECK:-0}
  # Where the update started: kept over the restart below, for What's new at the end
  local was=${ND_UPDATE_WAS:-}; [[ -n $was ]] || was=$(git -C "$repo" rev-parse HEAD)
  # Hyprland reloads on every save, and a pull replaces hyprland.lua by deleting and writing it: a reload in between
  # showed "config has errors" (cannot open hyprland.lua) until the end. Off for the update; the reload below turns it
  # back on (a failed update leaves it off until the next reload or login).
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && hyprctl eval 'hl.config({ misc = { disable_autoreload = true } })' >/dev/null 2>&1
  while read -r r; do
    name=$(basename "$r")
    echo "==> $name"
    git -C "$r" fetch -q || { echo "    couldn't fetch, skipping"; missed+=("$name: couldn't fetch, not updated"); continue; }
    n=$(behind "$r")
    if (( n == 0 )); then echo "    up to date"; continue; fi
    if [[ -n $(git -C "$r" status --porcelain --untracked-files=no) ]]; then
      echo "    $n new, but it has uncommitted changes: skipped (commit or stash them, then run this again)"
      missed+=("$name: $n new, not pulled over uncommitted changes (commit or stash them in $r)"); continue
    fi
    u=$(upstream "$r")
    git -C "$r" --no-pager log --format='    %s' "HEAD..$u"
    git -C "$r" merge -q --ff-only "$u" || {
      echo "    has its own commits: skipped (rebase it by hand)"; missed+=("$name: has its own commits, not pulled: git -C $r pull --rebase"); continue
    }
    [[ $r == "$(readlink -f "${DECK_SRC:-$HOME/.local/src/deck}")" ]] && deck=1
  done < <(repos | sort -u)

  # This function was read before the pull: when the pull changed this command, the rest of the update goes on in the
  # new version, or its new steps would run only next time while the files they belong with are new already (the
  # Hyprland repo step and packages-hyprland.txt, 19.10.2026). Once only; whether Deck's source came in goes along.
  # Its parts in bin/nightdrive.d were read before the pull too, so a change there counts as well.
  if [[ -z ${ND_UPDATE_AGAIN:-} ]] && ! git -C "$repo" diff --quiet "$was" HEAD -- bin/nightdrive bin/nightdrive.d; then
    echo "==> nightdrive itself was updated: going on with the new version"
    ND_UPDATE_AGAIN=1 ND_UPDATE_DECK=$deck ND_UPDATE_WAS=$was exec "$repo/bin/nightdrive" update
  fi

  # Relinked even when nothing new came in: after a `git pull` by hand the new links (this command among them) would
  # otherwise never appear. Nightdrive's link.sh first, then the overlay's, as on install.
  while read -r r; do
    [[ -x $r/link.sh ]] || continue
    echo "==> Links ($(basename "$r"))"; "$r/link.sh" | grep -v '^ok '
    (( PIPESTATUS[0] == 0 )) || missed+=("Links ($(basename "$r")): $r/link.sh")
  done < <(echo "$repo"; repos | sort -u | grep -vxF "$repo" | grep -vF "$external/")   # not an external plugin's own script

  # Fonts, ble.sh, GTK settings, default apps (the same steps as install.sh): what was added since this install
  echo "==> Fonts, ble.sh, GTK, default apps"
  "$repo/setup-user.sh" >/dev/null || { echo "    failed: run $repo/setup-user.sh to see why"; missed+=("Fonts, ble.sh, GTK: $repo/setup-user.sh"); }

  # Claude Code, as install.sh puts it in: an install from before that (19.10.2026) gets it here. Not when it's there
  # some other way (npm, a package); once in, its own installer keeps it up to date.
  if [[ ! -x $HOME/.local/bin/claude ]] && ! command -v claude >/dev/null; then
    echo "==> Claude Code"
    "$repo/setup-claude.sh" \
      && echo "    run claude once and log in (⌘⌥Enter and the top bar's usage menu use that sign-in)" \
      || missed+=("Claude Code: $repo/setup-claude.sh")
  fi

  # The Hyprland stack's COPR (setup-hyprland-repo.sh): set up again only when it isn't as the repo wants, e.g. still
  # arcaneon/arcos (until 19.10.2026). Before New packages and the System update, which then take the packages from it.
  if ! "$repo/setup-hyprland-repo.sh" --check; then
    echo "==> Hyprland repo"
    as_root "Hyprland repo" "$repo/setup-hyprland-repo.sh"
  fi

  echo "==> New packages"
  # With the machine's own list (packages-pc.txt, packages-asahi.txt), its groups (@hardware-support) left to install.sh.
  # --skip-unavailable: one this architecture lacks (microcode_ctl is x86 only)
  want=$(cat "$repo/packages.txt" "$repo/packages-hyprland.txt" "$repo/packages-$("$scripts/platform" machine).txt" 2>/dev/null \
    | grep -vE '^\s*(#|$|@)')
  missing=$(for p in $want; do rpm -q --whatprovides "$p" >/dev/null 2>&1 || echo "$p"; done)
  if [[ -n $missing ]]; then echo "    $(echo $missing)"; as_root "New packages" sudo dnf install -y --skip-unavailable $missing; else echo "    none"; fi
  # install.sh marks the list's packages as wanted, so removing KDE doesn't take them along. One added to it since may
  # be here as KDE's dependency (pipewire-utils, 25.10.2026): marked too. -C: the installed ones only, no metadata download
  # The installed plugins' packages likewise (plugin.conf's packages=, marked by plugins install since 25.10.2026)
  deps=$(dnf -q -C repoquery --installed --qf '%{name} %{reason}\n' $want $(plugin_packages) 2>/dev/null | awk '/Dependency$/ { print $1 }' | sort -u)
  [[ -z $deps ]] || as_root "New packages" sudo dnf mark user -y $deps >/dev/null
  # nwg-panel came with Hyprland (Fedora's package supplements it) until config/system/dnf-excludes.conf, put in place
  # under System files below. One installed on purpose stays.
  if [[ $(dnf -q -C repoquery --installed --setopt=disable_excludes='*' --qf '%{reason}' nwg-panel 2>/dev/null) == *Dependency ]]; then
    echo "    removing nwg-panel (came with Hyprland; the top bar is Nightdrive's own)"
    as_root "New packages" sudo dnf remove -y --setopt=disable_excludes='*' nwg-panel
  fi

  # doubletake (Screen Mirroring, plugins/mirroring): built again when the tested commit in its install.sh changes.
  # Not installed when missing: it was left out at install time (or not added in Install › Plugins).
  if [[ -x $HOME/.local/bin/doubletake ]]; then
    echo "==> doubletake (Screen Mirroring)"
    dt_want=$(sed -nE 's/^ref=\$\{DOUBLETAKE_REF:-([0-9a-f]+)\}.*/\1/p' "$repo/plugins/mirroring/install.sh")
    dt_have=$(git -C "$HOME/.local/src/doubletake" rev-parse HEAD 2>/dev/null || true)
    if [[ -z $dt_want || $dt_have != "$dt_want"* ]]; then as_root "doubletake" "$repo/plugins/mirroring/install.sh"; else echo "    up to date"; fi
  fi

  # The system files install.sh puts in place (config/system/sync: its list, and what reloads each): copied again when
  # the repo's version differs or is missing
  echo "==> System files"
  # Checked first without sudo: when nothing differs, an update without a terminal has no step to list as skipped
  if "$repo/config/system/sync" --check >/dev/null; then echo "    up to date"; else as_root "System files" "$repo/config/system/sync"; fi
  # The file the dnf hook touches; Quickshell watches it only if it exists when it starts (restarted below)
  [[ -e /var/lib/nightdrive/dnf-changed ]] || as_root "System files" sudo install -Dm644 /dev/null /var/lib/nightdrive/dnf-changed

  # Remote login: SSH only over Tailscale and on the networks trusted, once (config/hypr/scripts/remote-login, 23.10.2026).
  # In the session firewalld lets a wheel user do it (on Fedora KDE without a password); over ssh only root may read its
  # config, so setup exits 2 and runs again with sudo. Its 1 is "nothing to do" either way, not a failure for as_root,
  # and the first try's "Not authorized" is left out, the sudo one following
  echo "==> Remote login"
  setup_remote_login() {   # $@: what runs it (sudo, or nothing)
    "$@" "$scripts/remote-login" setup | sed 's/^/    /'
    case ${PIPESTATUS[0]} in 0) ;; 1) echo "    up to date" ;; *) return 2 ;; esac
  }
  setup_remote_login 2>/dev/null || as_root "Remote login" setup_remote_login sudo

  # The login screen's and the boot splash's copies in /etc/greetd and /usr/share/plymouth: installed again when the repo's
  # differ (their version file: the git tree they came from). An install from before both were the default (18.10.2026)
  # is asked once whether to turn them on.
  echo "==> Login screen and boot splash"
  local asked=$HOME/.local/state/nightdrive/boot-asked did=0 a
  if systemctl -q is-enabled greetd.service 2>/dev/null; then
    # Not asked with the text login (switch.sh text), chosen in place of the login screen
    if ! grep -q -e '^\[initial_session\]' -e '^# Text login (switch.sh text)' /etc/greetd/config.toml 2>/dev/null &&
       [[ ! -e $asked && -t 0 ]]; then
      echo "    New: the boot splash goes straight over to the login screen, with the desktop starting behind it as its lock"
      echo "    (no black flashes at boot). Turning it on rebuilds the initramfs, which takes a minute or two."
      read -rp "    Turn it on? [Y/n] " a
      mkdir -p "${asked%/*}"; echo "${a:-y}" > "$asked"
      if [[ ! $a =~ ^[Nn] ]]; then
        "$repo/config/splash/install.sh" | grep -v '^Done'
        (( PIPESTATUS[0] == 0 )) || missed+=("Boot splash: $repo/config/splash/install.sh")
        as_root "Login screen" "$repo/config/greeter/switch.sh" autologin >/dev/null
        did=1
      fi
    fi
    if [[ $(cat /etc/greetd/greeter/version 2>/dev/null) != "$(git -C "$repo/config/greeter" rev-parse HEAD:./ HEAD:../hypr/vm-display.lua HEAD:../hypr/scripts/vm-display 2>/dev/null)" ]]; then
      echo "    login screen"; as_root "Login screen" "$repo/config/greeter/install.sh" >/dev/null && did=1
    fi
  fi
  if [[ $(plymouth-set-default-theme 2>/dev/null) == nightdrive ]] &&
     [[ $(cat /usr/share/plymouth/themes/nightdrive/version 2>/dev/null) != "$(git -C "$repo/config/splash" rev-parse HEAD:./ HEAD:../greeter/background.jpg 2>/dev/null)" ]]; then
    echo "    boot splash (rebuilds the initramfs, a minute or two)"; as_root "Boot splash" "$repo/config/splash/install.sh" >/dev/null && did=1
  fi
  (( did )) && echo "    takes effect from the next boot" || echo "    up to date"

  echo "==> System update"
  as_root "System update" sudo dnf upgrade --refresh -y

  echo "==> Flatpak apps"
  flatpaks=$(grep -vE '^\s*(#|$)' "$repo/flatpaks.txt" 2>/dev/null)   # the core ones; optional apps are plugins
  # Added by install.sh; an install from before Flatpak support (13.10.2026) doesn't have it yet
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  [[ -n $flatpaks ]] && { flatpak install --user -y --noninteractive flathub $flatpaks \
    || missed+=("Flatpak apps: flatpak install --user flathub $(echo $flatpaks)"); }   # already installed ones are skipped
  flatpak update --user -y --noninteractive || missed+=("Flatpak apps: flatpak update --user")

  offer_apps     # before the Deck rebuild: a Deck installed there was just built

  # Only while Deck is installed: its source stays when the app is removed, and a rebuild would bring it back
  # No DECK_SRC of its own: install.sh builds a DECK_SRC as one's own source, which would turn a packaged Deck into a build
  (( deck )) && [[ -x $HOME/.local/bin/deck ]] && { echo "==> Deck (rebuild)"; "$repo/plugins/deck/install.sh" \
    || missed+=("Deck (rebuild): $repo/plugins/deck/install.sh"); }

  # Ferry (plugins/ferry): its own app from its own repo, which the plugin installs, and Nightdrive's update brings the
  # release pinned there along. A Ferry from before (the plugin's own server, until 10.2026; its state is still in
  # Nightdrive's folder) is replaced by it here, with its phones and box: its old command and unit are gone from the plugin.
  if systemctl --user -q is-enabled ferry.service 2>/dev/null || [[ -d $HOME/.local/share/nightdrive/ferry ]]; then
    echo "==> Ferry"
    # Not through as_root: Ferry's installer comes from another repo, so the sudo timestamp the steps above cached is
    # dropped first, and it gets root only by asking for the password itself (a package it lacks). What it runs is the
    # release pinned in plugins/ferry/release.conf, checked by its sha256. Nothing after this step needs sudo.
    sudo -k
    "$repo/plugins/ferry/install.sh" --update \
      || { echo "    failed" >&2; missed+=("Ferry: $repo/plugins/ferry/install.sh --update"); }
  fi

  plugins_installed >/dev/null     # the optional parts' list, before the reload reads it (hypr/bindings.lua)
  "$repo/config/fuzzel/sync-apps" >/dev/null 2>&1 || true   # the launcher's app list, as at the end of install.sh
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    echo "==> Reloading the desktop"
    hyprctl reload >/dev/null
    "$repo/config/hypr/scripts/theme" apply >/dev/null 2>&1
    # Restarted: Quickshell doesn't watch a file that was missing when it started (e.g. the top bar's files before
    # this update linked them), and new QML types need a fresh start. Through its supervisor (an older session's
    # plain qs gets one), which stops it on any display: over SSH a plain `qs kill` missed the bar and left two
    "$repo/config/hypr/scripts/desktop-shell" restart
    # hypridle reads its config only at start: restarted through hypr/scripts/idle, which writes it from the current
    # template (before 14.10.2026 Hyprland ran plain hypridle, whose screensaver closed right away)
    pkill -x hypridle || true; hyprctl dispatch "hl.dsp.exec_cmd(\"$HOME/.config/hypr/scripts/idle start\")" >/dev/null
  fi
  # The old top bar (before Quickshell drew it, 13.10.2026), also when updating over SSH. Quickshell reloads its own files.
  pkill -x waybar || true

  # Nothing waits now, except system files a skipped sudo step left behind: they stay counted (update check)
  mkdir -p "$cache"; "$repo/config/system/sync" --check | wc -l > "$cache/updates"; echo 0 > "$cache/updates-notified"
  # The notes of the releases this update brought in (CHANGELOG.md): last, where they're seen when the update ends
  if ! git -C "$repo" diff --quiet "$was" HEAD -- CHANGELOG.md 2>/dev/null; then
    # A picture in the notes (![…](docs/releases/…)) is for the website and GitHub: not shown in a terminal
    echo; echo "==> What's new"; whats_new "$was" | sed -E '/^!\[[^]]*\]\([^)]*\)$/d' | cat -s | sed 's/^/    /'
  fi
  echo
  if (( ${#missed[@]} )); then
    echo "Nightdrive is updated, but these steps were skipped or failed:"
    printf '  - %s\n' "${missed[@]}"
    (( can_sudo )) || echo "Run nightdrive update in a terminal (sudo asks for the password there), or the commands above."
    return 1
  fi
  echo "Nightdrive is up to date."
}

# Nightdrive's own apps (group app in plugin.conf: Mail, Deck, Contacts, Ferry) come with every install. An install that has
# never had one (from before it was an app, or before it existed) gets it here, once: each is then marked in $offered
# (install.sh marks the ones it offered, left out or not), and one marked is never installed again, so an app the user
# removed stays away. One installed already (or off) is only marked. An install from before the list (23.10.2026) has no
# record of an app removed earlier: what the app leaves behind tells (Mail's settings after `nightmail disable`, Deck's
# source, Contacts' accounts after `contacts disable`, Ferry's box), and it is marked without installing. Without sudo (can_sudo, update) it waits, unmarked, for a run in a terminal. A
# failed install is marked too, so a build that fails doesn't run again on every update: missed has the command.
# Only the repo's plugins: an external one can't install itself by naming the group. An app with bundled=no in its
# plugin.conf (Garage) isn't offered at all: it waits in Install › Recommended for the user to pick it.
offer_apps() {
  local a id name inst dir trace apps did=0
  mkdir -p "${offered%/*}"; touch "$offered"
  mapfile -t apps < <(plugins | awk -F'\t' '$8 == "app" && $11 == "repo" { print $1 "\t" $2 "\t" $7 "\t" $9 }')
  echo "==> Nightdrive apps"
  for a in "${apps[@]}"; do
    IFS=$'\t' read -r id name inst dir <<<"$a"
    grep -qxF "$id" "$offered" && continue
    [[ $(conf_value "$dir/plugin.conf" bundled) == no ]] && continue
    case $id in
      mail) trace=$HOME/.config/nightmail ;;
      deck) trace=${DECK_SRC:-$HOME/.local/src/deck} ;;
      contacts) trace=${XDG_CONFIG_HOME:-$HOME/.config}/contacts ;;   # its accounts, kept by contacts disable
      ferry) trace=${XDG_DATA_HOME:-$HOME/.local/share}/ferry ;;      # its box and phones, kept when Ferry is removed
      *) trace="" ;;
    esac
    if (( inst )) || [[ -n $trace && -e $trace ]]; then echo "$id" >> "$offered"; continue; fi
    if (( ! can_sudo )); then
      echo "    $name is new: skipped, its installer needs sudo and there's no terminal to ask for the password" >&2
      missed+=("$name (new): run nightdrive update in a terminal"); did=1; continue
    fi
    echo "    $name is new here: installing it once (removed later, an update won't bring it back)"; did=1
    NIGHTDRIVE_INSTALL=1 plugin_install "$id" || missed+=("$name: nightdrive plugins install $id")
    echo "$id" >> "$offered"
    [[ $id == deck ]] && deck=0
  done
  (( did )) || echo "    up to date"
}

# as_root WHAT CMD…: an update step that needs sudo (CMD is sudo itself, or a script that runs it). Skipped without a
# way to ask for the password (can_sudo, update); skipped or failed, it goes to update's list with the command.
as_root() {
  local what=$1; shift
  if (( ! can_sudo )); then
    echo "    skipped: needs sudo, and there's no terminal to ask for the password" >&2
    missed+=("$what: $*"); return 1
  fi
  "$@" && return
  echo "    failed: $*" >&2; missed+=("$what: $*"); return 1
}
