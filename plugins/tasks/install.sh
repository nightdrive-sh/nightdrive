#!/bin/bash
# Tasks' installer (plugin.conf): Tasks among the apps and its notifications. Nothing to set up: the first task makes
# the first list. Safe to run again.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

rpm -q python3 libnotify >/dev/null 2>&1 || sudo dnf install -y python3 libnotify
bin/tasks enable
echo "Tasks is ready: tasks opens it (or the Launcher: Tasks), tasks add TITLE adds one, and so does Claude."
