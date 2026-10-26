#!/bin/bash
# Contacts' installer (plugin.conf): the packages, Contacts among the apps and the sync. The accounts are set up after
# it, with Claude (`contacts setup`, README.md › Setting up an account) or by hand. Safe to run again.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

sudo dnf install -y vdirsyncer python3-vobject libsecret python3 ImageMagick

bin/contacts enable
if [[ ! -f ${XDG_CONFIG_HOME:-$HOME/.config}/contacts/accounts.conf ]]; then
  cat <<MSG

Contacts needs your account first: Claude can set it up with you (contacts setup, or Set up with Claude on the plugin's
page). To do it yourself, the plugin's page has the steps (launcher › System › Install › Plugins › Contacts, or
$PWD/README.md).
MSG
  # Only on the desktop (not over ssh): its first start offers the setup too
  [[ -n ${WAYLAND_DISPLAY:-} ]] && bin/contacts
  exit 0
fi
echo "Contacts is ready: contacts opens it (or the launcher: Contacts)."
