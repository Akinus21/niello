#!/usr/bin/env bash
set -uo pipefail

CHECK_HOST="1.1.1.1"
MAX_WAIT=10       # total seconds to wait for connectivity
INTERVAL=1        # seconds between checks

have_connectivity() {
    nm-online -q --timeout=1 2>/dev/null
}

elapsed=0
connected=false

while [ "$elapsed" -lt "$MAX_WAIT" ]; do
    if have_connectivity; then
        connected=true
        break
    fi
    sleep "$INTERVAL"
    elapsed=$((elapsed + INTERVAL))
done

if [ "$connected" = false ]; then
    echo "niello-boot-upgrade: no connectivity after ${MAX_WAIT}s, skipping upgrade check"
    exit 0
fi

echo "niello-boot-upgrade: connectivity confirmed, checking for update"

if bootc upgrade --check 2>&1 | grep -q "Update available"; then
    echo "niello-boot-upgrade: update found, applying and rebooting"
    bootc upgrade
    systemctl reboot
fi

exit 0
