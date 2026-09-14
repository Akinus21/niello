#!/usr/bin/env bash
set -uo pipefail

MAX_RETRIES=3
RETRY_DELAY=30

do_upgrade() {
    /usr/bin/bootc upgrade --quiet "$@"
}

for attempt in $(seq 1 $MAX_RETRIES); do
    if do_upgrade; then
        exit 0
    fi
    last_error=$(/usr/bin/bootc upgrade --quiet 2>&1 || true)
    if echo "$last_error" | grep -qiE "dial|temporary|network|resolve|connection|timeout|registry|fetching"; then
        echo "bootc-fetch-apply-updates: transient error (attempt $attempt/$MAX_RETRIES), retrying in ${RETRY_DELAY}s"
        sleep "$RETRY_DELAY"
    else
        echo "bootc-fetch-apply-updates: non-transient error: $last_error"
        exit 1
    fi
done

echo "bootc-fetch-apply-updates: failed after ${MAX_RETRIES} retries"
exit 1
