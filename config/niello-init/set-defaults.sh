#!/usr/bin/env bash
# set-defaults.sh — Declare XDG default applications for Niello
# Runs on first login per user via niello-init

set -euo pipefail

# File manager — yazi (terminal) as default
xdg-mime default yazi.desktop inode/directory 2>/dev/null || true

# Browser — qutebrowser as default (or Nyxt if installed)
if command -v qutebrowser &>/dev/null; then
    xdg-mime default qutebrowser.desktop x-scheme-handler/http 2>/dev/null || true
    xdg-mime default qutebrowser.desktop x-scheme-handler/https 2>/dev/null || true
    xdg-mime default qutebrowser.desktop text/html 2>/dev/null || true
fi

# Image viewer — imv
if command -v imv &>/dev/null; then
    xdg-mime default imv.desktop image/png 2>/dev/null || true
    xdg-mime default imv.desktop image/jpeg 2>/dev/null || true
    xdg-mime default imv.desktop image/gif 2>/dev/null || true
    xdg-mime default imv.desktop image/webp 2>/dev/null || true
fi

# Screenshot tool — set grim as default for screenshots
xdg-mime default grim.desktop image/png 2>/dev/null || true

# Update desktop database for MIME types
update-desktop-database /usr/share/applications 2>/dev/null || true