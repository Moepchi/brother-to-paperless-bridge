#!/usr/bin/env bash
set -Eeuo pipefail

required=(BRSCAN_IP PAPERLESS_URL PAPERLESS_TOKEN SCAN_PC_NAME)

for variable in "${required[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "ERROR: Required environment variable ${variable} is empty." >&2
    exit 1
  fi
done

if [[ ! "${BRSCAN_IP}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
  echo "ERROR: BRSCAN_IP must be an IPv4 address." >&2
  exit 1
fi

if [[ ! "${PAPERLESS_URL}" =~ ^https?:// ]]; then
  echo "ERROR: PAPERLESS_URL must start with http:// or https://." >&2
  exit 1
fi

if (( ${#SCAN_PC_NAME} > 15 )); then
  echo "ERROR: SCAN_PC_NAME must not exceed 15 characters." >&2
  exit 1
fi

if [[ -z "${SCAN_MODE:-True Gray}" ]]; then
  echo "ERROR: SCAN_MODE must not be empty." >&2
  exit 1
fi

if [[ ! "${SCAN_RESOLUTION:-100}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SCAN_RESOLUTION must be a positive integer." >&2
  exit 1
fi

case "${SCAN_SOURCE:-FB}" in
  FB|ADF_L|ADF_C) ;;
  *) echo "ERROR: SCAN_SOURCE must be FB, ADF_L, or ADF_C." >&2; exit 1 ;;
esac

case "${SCAN_DUPLEX:-false}" in
  true|false) ;;
  *) echo "ERROR: SCAN_DUPLEX must be true or false." >&2; exit 1 ;;
esac

if [[ ! "${QUEUE_RETRY_INTERVAL:-60}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: QUEUE_RETRY_INTERVAL must be a positive integer." >&2
  exit 1
fi

if [[ ! "${UPLOAD_LOCK_TIMEOUT:-330}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: UPLOAD_LOCK_TIMEOUT must be a positive integer." >&2
  exit 1
fi

airsane_port=${AIRSANE_PORT:-8095}
if [[ ! "${airsane_port}" =~ ^[0-9]+$ ]] \
  || (( airsane_port < 1 || airsane_port > 65535 )); then
  echo "ERROR: AIRSANE_PORT must be between 1 and 65535." >&2
  exit 1
fi
