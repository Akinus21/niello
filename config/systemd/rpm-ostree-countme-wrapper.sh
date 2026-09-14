#!/usr/bin/env bash
set -uo pipefail

MAX_RETRIES=3
RETRY_DELAY=15

for attempt in $(seq 1 $MAX_RETRIES); do
    if rpm-ostree countme "$@"; then
        exit 0
    fi
    last_status=$?
    # Only retry on transient network errors (HTTP 4xx except 404, DNS, connection)
    if [ $last_status -eq 1 ]; then
        last_error=$(rpm-ostree countme 2>&1 || true)
        if echo "$last_error" | grep -qiE "dial|temporary|network|resolve|connection|timeout|500|502|503|504"; then
            echo "rpm-ostree-countme: transient error (attempt $attempt/$MAX_RETRIES), retrying in ${RETRY_DELAY}s"
            sleep "$RETRY_DELAY"
            continue
        fi
    fi
    echo "rpm-ostree-countme: non-transient error (exit $last_status)"
    exit $last_status
done

echo "rpm-ostree-countme: failed after ${MAX_RETRIES} retries"
exit 1
