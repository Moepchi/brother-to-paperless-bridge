#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

readonly SCRIPT_DIR=${BRIDGE_SCRIPT_DIR:-/usr/local/lib/brother-bridge}
readonly QUEUE_DIR=${SCAN_QUEUE_DIR:-/var/lib/brother-bridge/queue}
readonly LOCK_DIR=${SCAN_LOCK_DIR:-/tmp/brother-bridge-scan.lock}
work_dir=''
queued_partial=''

cleanup() {
  [[ -z "${work_dir}" ]] || rm -rf -- "${work_dir}"
  [[ -z "${queued_partial}" ]] || rm -f -- "${queued_partial}"
  rmdir -- "${LOCK_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

if ! mkdir -- "${LOCK_DIR}" 2>/dev/null; then
  echo "ERROR: Another scan is already running." >&2
  exit 1
fi

device=${1:-${SCAN_DEVICE:-}}
if [[ -z "${device}" ]]; then
  device=$(scanimage -L | grep -o "brother4:[^ ']*" | head -n 1)
fi

if [[ -z "${device}" ]]; then
  echo "ERROR: No Brother scanner device found." >&2
  exit 1
fi

timestamp=$(date +%Y%m%d_%H%M%S)
work_dir=$(mktemp -d "/tmp/brother-scan-${timestamp}-XXXXXX")
install -d "${QUEUE_DIR}"

echo "Starting Brother hardware-button scan from ${device}..."
scan_file="${work_dir}/scan.tif"
scan_command=${SKEY_SCANIMAGE:-/opt/brother/scanner/brscan-skey/skey-scanimage}
scan_arguments=(
  --device-name "${device}"
  --resolution "${SCAN_RESOLUTION:-100}"
  --source "${SCAN_SOURCE:-FB}"
  --size "${SCAN_SIZE:-A4}"
  --outputfile "${scan_file}"
)
if [[ "${SCAN_DUPLEX:-false}" == true ]]; then
  scan_arguments+=(--duplex)
fi

scan_status=0
if [[ "${device}" == *net* ]]; then
  sleep 1
fi

"${scan_command}" "${scan_arguments[@]}" || scan_status=$?
if [[ ! -s "${scan_file}" ]]; then
  echo "First Brother scan attempt produced no file; retrying once..."
  sleep 1
  scan_status=0
  "${scan_command}" "${scan_arguments[@]}" || scan_status=$?
fi

if [[ ! -s "${scan_file}" ]]; then
  echo "Scan canceled or no pages found (scanimage exit ${scan_status})."
  exit "${scan_status}"
fi

unique_id=${work_dir##*-}
queued_document="${QUEUE_DIR}/scan_${timestamp}_${unique_id}.tiff"
queued_partial="${queued_document}.partial"
mv -- "${scan_file}" "${queued_partial}"
mv -- "${queued_partial}" "${queued_document}"
queued_partial=''

echo "Document safely queued: ${queued_document}"
if "${SCRIPT_DIR}/upload-document.sh" "${queued_document}"; then
  rm -f -- "${queued_document}"
  echo "Document accepted by Paperless."
else
  echo "WARNING: Upload failed; document remains safely queued: ${queued_document}" >&2
  exit 1
fi
