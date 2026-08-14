#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly INTERVAL=${QUEUE_RETRY_INTERVAL:-60}

echo "Queue worker started; retry interval is ${INTERVAL}s."
while sleep "${INTERVAL}"; do
  "${SCRIPT_DIR}/retry-queue.sh" || true
done
