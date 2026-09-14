#!/usr/bin/env bash
set -uo pipefail

CHECK_HOST="1.1.1.1"
MAX_WAIT=30
INTERVAL=2
MAX_RETRIES=3
RETRY_DELAY=10

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

do_bootc_upgrade() {
    bootc upgrade --check 2>&1 | grep -q "Update available"
}

if do_bootc_upgrade; then
    echo "niello-boot-upgrade: update found, applying and rebooting"
    bootc upgrade
    systemctl reboot
    return
fi

# Retry loop for transient failures (DNS, registry errors, etc.)
for attempt in $(seq 1 $MAX_RETRIES); do
    echo "niello-boot-upgrade: checking for update (attempt $attempt/$MAX_RETRIES)"
    if do_bootc_upgrade; then
        echo "niello-boot-upgrade: update found, applying and rebooting"
        bootc upgrade
        systemctl reboot
        return
    fi
    # Check if it was a transient error vs. no update available
    last_error=$(bootc upgrade --check 2>&1 || true)
    if echo "$last_error" | grep -qiE "dial|temporary|network|resolve|connection|timeout|registry"; then
        echo "niello-boot-upgrade: transient error, retrying in ${RETRY_DELAY}s: $last_error"
        sleep "$RETRY_DELAY"
    else
        echo "niello-boot-upgrade: no update available or non-transient error"
        break
    fi
done

echo "niello-boot-upgrade: no update after ${MAX_RETRIES} retries"
exit 0
