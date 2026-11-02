#!/bin/bash
# Calendar's installer (plugin.conf): the packages, Calendar among the apps and the sync. The calendars come from
# Contacts' accounts (its README › Setting up an account) and `calendar subscribe` (README.md › Your calendars).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

# Only when one is missing: nightdrive update installs Calendar on an install that never had it, and with the packages
# there (Contacts brings vdirsyncer) it needs no password
rpm -q vdirsyncer khal python3-icalendar libsecret python3 >/dev/null 2>&1 \
  || sudo dnf install -y vdirsyncer khal python3-icalendar libsecret python3

bin/calendar enable
if [[ -z $(python3 lib/sources.py names 2>/dev/null) ]]; then
  cat <<MSG

Calendar reads the calendars of your iCloud account in Contacts: set that up first (contacts setup). A Google calendar
comes by its private ICS address: calendar subscribe NAME. The steps: $PWD/README.md
MSG
  exit 0
fi
bin/calendar sync || echo "The first sync didn't finish: calendar sync tries again."
echo "Calendar is ready: calendar opens it (or the Launcher: Calendar)."
