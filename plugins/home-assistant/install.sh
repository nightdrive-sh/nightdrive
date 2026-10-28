#!/bin/bash
# Home Assistant: the webapp, the launcher's Home level and the top bar's Home icon (bin/home-assistant).
# Asks for the addresses and a token, writes ~/.config/nightdrive/home-assistant and adds the webapp. Safe to run again.
# Remove: rm ~/.config/nightdrive/home-assistant (Home disappears from the bar and the launcher), and the webapp from
# the launcher's Remove.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ha="$here/bin/home-assistant"
conf="$HOME/.config/nightdrive/home-assistant"

echo "==> Home Assistant"
# Suggestions (pre-filled when they answer): the usual local name and a Tailscale machine called ha / homeassistant
local_url=; ts_url=
curl -s -m 2 -o /dev/null http://homeassistant.local:8123/api/ && local_url=http://homeassistant.local:8123
if command -v tailscale >/dev/null; then
  while read -r h; do
    [[ -n $h ]] && curl -s -m 2 -o /dev/null "http://$h:8123/api/" && { ts_url="http://$h:8123"; break; }
  done < <(tailscale status --json 2>/dev/null | jq -r '.Peer[]? | select(.HostName | test("^(ha|hass|homeassistant|home-assistant)$"; "i")) | .HostName')
fi
# Messages are kept under 70 columns: the launcher's installer terminal is narrow
cat <<'MSG'

Addresses, one at a time. They're tried in this order.
Enter on an empty line skips one; Ctrl+U clears a suggestion.
MSG
urls=; plain=()
# ask PROMPT SUGGESTION [tailnet]: adds the answer to urls; "ha:8123" gets http://, a Nabu Casa address https://.
# An http address goes to plain too, unless it is on the tailnet (Tailscale encrypts its own traffic).
ask() {
  local u
  read -erp "  $1: " -i "$2" u
  u=${u//[[:space:]]/}; u=${u%/}
  [[ -n $u ]] || return 0
  [[ $u =~ ^https?:// ]] || { [[ $u == *.nabu.casa* ]] && u="https://$u" || u="http://$u"; }
  urls+="${urls:+ }$u"
  [[ $u == http://* && ${3:-} != tailnet && ! $u =~ ^http://(100\.|[^/:]*\.ts\.net) ]] && plain+=("$u")
  return 0
}
ask "Home network (homeassistant.local:8123)" "$local_url"
ask "Tailscale (ha:8123)" "$ts_url" tailnet
ask "Nabu Casa (xxxx.ui.nabu.casa)" ""
[[ -n $urls ]] || { echo "No address given" >&2; exit 1; }
# The addresses are tried in order wherever the laptop is, token and all: on another network, whatever answers
# homeassistant.local gets it. Say so, and leave the choice to the user.
if (( ${#plain[@]} )); then
  echo; printf '! Not encrypted: %s\n' "${plain[@]}"
  cat <<'MSG'
  The token goes over the network as plain text there, and on
  another network to whatever answers that address. An https
  address or Tailscale is safer: run this again to change it.
MSG
fi

cat <<'MSG'

A long-lived access token: Home Assistant › your profile ›
Security › Long-lived access tokens › Create token.
Paste it, or an op://vault/item/field reference (1Password).
MSG
read -rsp "Token: " tok; echo
[[ -n $tok ]] || { echo "No token given" >&2; exit 1; }
if [[ $tok == op://* ]]; then
  ref=$tok
  tok=$(op read "$ref") || { echo "op read failed (is 1Password unlocked?)" >&2; exit 1; }
fi

ok=()
for u in $urls; do
  u=${u%/}
  # The token on stdin: an argument is readable by any user in /proc
  if out=$("$ha" test "$u" <<<"$tok" 2>&1); then echo "  ✓ $u  ($out)"; ok+=("$u"); else echo "  ✗ $out"; fi
done
(( ${#ok[@]} )) || { echo "None of the addresses worked" >&2; exit 1; }

mkdir -p "${conf%/*}"
umask 077
{
  echo "# Home Assistant (plugins/home-assistant: install.sh; format: bin/home-assistant)"
  echo "HA_URLS=\"${urls}\""
  if [[ -n ${ref:-} ]]; then echo "HA_TOKEN_CMD=\"op read '$ref'\""; else echo "HA_TOKEN=$tok"; fi
} > "$conf"
rm -f "$HOME/.cache/nightdrive/home-assistant-url" "${XDG_RUNTIME_DIR:-/run/user/$UID}/nightdrive-ha-token"
echo "  saved $conf"

# The webapp has one address: its login is tied to it. One that works anywhere is the better choice.
echo
last=${ok[-1]}
read -erp "Address for the webapp: " -i "$last" web
web=${web:-$last}
icon=$(mktemp --suffix=.png); trap 'rm -f "$icon"' EXIT
curl -sfL -m 5 -o "$icon" "$web/static/icons/favicon-192x192.png" || icon=
"$HOME/.config/hypr/scripts/webapp-add" "Home Assistant" "$web" ${icon:+"$icon"}
"$HOME/.config/fuzzel/sync-apps" >/dev/null 2>&1 || true

qs ipc call bar refresh >/dev/null 2>&1 || true
cat <<'MSG'

Done. Home is in the launcher (⌘Space › Home) and in the top bar.
Shift+Enter on a device in the launcher pins it to the top
bar's Home menu.
MSG
