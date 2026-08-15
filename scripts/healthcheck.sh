#!/usr/bin/env bash
set -Eeuo pipefail

: "${AIRSANE_PORT:=8095}"

pgrep -x brscan-skey-exe >/dev/null \
  || { echo "Brother button service is not running." >&2; exit 1; }

pgrep -f '[q]ueue-worker\.sh' >/dev/null \
  || { echo "Queue worker is not running." >&2; exit 1; }

curl --silent --show-error --fail \
  --connect-timeout 2 \
  --max-time 5 \
  "http://127.0.0.1:${AIRSANE_PORT}/" >/dev/null \
  || { echo "AirSane is not responding." >&2; exit 1; }

if [[ "${STATUS_ENABLED:-true}" == true ]]; then
  curl --silent --show-error --fail \
    --connect-timeout 2 \
    --max-time 5 \
    "http://127.0.0.1:${STATUS_PORT:-8096}/health" >/dev/null \
    || { echo "Status dashboard is not responding." >&2; exit 1; }
fi
