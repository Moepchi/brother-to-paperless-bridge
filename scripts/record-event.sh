#!/usr/bin/env bash

# Statistics must never interfere with scanning or delivery.
set +e

event=${1:-unknown}
detail=${2:-}
duration=${3:-}
document_id=${4:-}
queue_dir=${SCAN_QUEUE_DIR:-/var/lib/brother-bridge/queue}
stats_dir=${BRIDGE_STATS_DIR:-${queue_dir}/.stats}
events_file=${BRIDGE_EVENTS_FILE:-${stats_dir}/events.jsonl}

install -d "${stats_dir}" 2>/dev/null || exit 0
exec 8>>"${stats_dir}/events.lock" || exit 0
flock -w 2 8 || exit 0

jq --compact-output --null-input \
  --arg timestamp "$(date --utc +%Y-%m-%dT%H:%M:%SZ)" \
  --arg event "${event}" \
  --arg detail "${detail}" \
  --arg duration "${duration}" \
  --arg document_id "${document_id}" \
  '{timestamp: $timestamp, event: $event}
   + (if $detail == "" then {} else {detail: $detail} end)
   + (if $duration == "" then {} else {duration_seconds: ($duration | tonumber)} end)
   + (if $document_id == "" then {} else {document_id: $document_id} end)' \
  >>"${events_file}" 2>/dev/null || true

# Keep a bounded history without requiring a database.
line_count=$(wc -l <"${events_file}" 2>/dev/null || printf '0')
if (( line_count > 2000 )); then
  tail -n 1000 "${events_file}" >"${events_file}.partial" \
    && mv -- "${events_file}.partial" "${events_file}"
fi

exit 0
