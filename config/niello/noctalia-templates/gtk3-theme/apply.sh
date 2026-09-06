#!/usr/bin/env bash
# apply.sh — GTK3 theme post_hook for Noctalia
# Sets GTK theme to adw-gtk3-dark (required for @define-color overrides to work),
# restarts Nemo so it picks up the new colors.
set -euo pipefail

# Switch to adw-gtk3-dark — this is the GTK3 theme that actually reads
# @define-color overrides from user-provided gtk.css. Adwaita-dark ignores them.
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true

# Kill any running Nemo instances (they re-spawn via .desktop file, so no need to manually restart)
pkill -x nemo 2>/dev/null || true

# Give the old process a moment to clean up
sleep 0.3

# Ensure Nemo is running (nemo starts on login; if killed, restart it)
if ! pgrep -x nemo >/dev/null 2>&1; then
    nohup nemo >/dev/null 2>&1 &
    disown >/dev/null 2>&1 || true
fi
