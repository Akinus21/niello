#!/usr/bin/env bash
# apply.sh — GTK3/4 theme post_hook for Noctalia
# Restarts Nemo (GTK3 file manager) so it picks up the new @define-color values.
set -euo pipefail

# Kill any running Nemo instances (they re-spawn via .desktop file, so no need to manually restart)
pkill -x nemo 2>/dev/null || true

# Give the old process a moment to clean up
sleep 0.3

# Ensure Nemo is running (nemo starts on login; if killed, restart it)
if ! pgrep -x nemo >/dev/null 2>&1; then
    nohup nemo >/dev/null 2>&1 &
    disown >/dev/null 2>&1 || true
fi
