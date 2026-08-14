#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly QUEUE_DIR=${SCAN_QUEUE_DIR:-/var/lib/brother-bridge/queue}

install -d "${QUEUE_DIR}"

failed=0
for document in "${QUEUE_DIR}"/*.tiff; do
  echo "Retrying queued document: $(basename -- "${document}")"
  if "${SCRIPT_DIR}/upload-document.sh" "${document}"; then
    rm -f -- "${document}"
    echo "Queued document accepted by Paperless."
  else
    failed=1
    echo "WARNING: Upload still failing; document remains in queue: ${document}" >&2
  fi
done

exit "${failed}"
