#!/bin/bash
# Files' installer (plugin.conf): Files among the apps, as the one that opens folders. Safe to run again.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

rpm -q python3 python3-gobject wl-clipboard poppler-utils fd-find >/dev/null 2>&1 \
  || sudo dnf install -y python3 python3-gobject wl-clipboard poppler-utils fd-find
bin/files enable
echo "Files is ready: Hyper F or files opens it, and ? in it lists the keys."
