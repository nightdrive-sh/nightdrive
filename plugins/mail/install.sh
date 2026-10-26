#!/bin/bash
# Mail's installer (plugin.conf): the packages, Mail among the apps and the sync. Without an account yet, Mail's first
# start offers to set one up with Claude (`nightmail setup`, README.md › Setting up an account).
# Safe to run again: `nightmail enable` at the end of the setup does the same.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

sudo dnf install -y notmuch isync libsecret zenity python3

bin/nightmail enable
if [[ ! -f ~/.config/isyncrc || ! -f ~/.config/nightmail/account.conf ]] || ! notmuch config get database.path >/dev/null 2>&1; then
  # Nightdrive's own installer (install.sh) installs Mail on every machine: the setup waits for Mail's first start
  [[ -n ${NIGHTDRIVE_INSTALL:-} ]] && { echo "Mail is installed; its first start offers to set up your account."; exit 0; }
  # Mail isn't opened from here: its window would take the focus, and the Enter meant to close the install terminal
  # would accept the setup offer instead
  cat <<MSG

Mail needs your email account first: open Mail, its first start offers to set it up with Claude (or: nightmail setup).
To do it yourself, Mail's README has the steps: $PWD/README.md
MSG
  exit 0
fi
echo "Mail is ready: nightmail opens it (or the launcher: Mail)."
