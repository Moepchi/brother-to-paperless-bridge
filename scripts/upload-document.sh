#!/usr/bin/env bash
set -Eeuo pipefail

document=${1:?Usage: upload-document.sh DOCUMENT}
readonly UPLOAD_LOCK_FILE=${UPLOAD_LOCK_FILE:-/var/lib/brother-bridge/upload.lock}
readonly UPLOAD_LOCK_TIMEOUT=${UPLOAD_LOCK_TIMEOUT:-330}

if [[ ! -s "${document}" ]]; then
  echo "ERROR: Document does not exist or is empty: ${document}" >&2
  exit 1
fi

paperless_url=${PAPERLESS_URL%/}

install -d "$(dirname -- "${UPLOAD_LOCK_FILE}")"
exec 9>"${UPLOAD_LOCK_FILE}"
if ! flock -w "${UPLOAD_LOCK_TIMEOUT}" 9; then
  echo "ERROR: Timed out waiting for the Paperless upload lock." >&2
  exit 75
fi

curl --silent --show-error --fail-with-body \
  --connect-timeout "${UPLOAD_CONNECT_TIMEOUT:-10}" \
  --max-time "${UPLOAD_MAX_TIME:-300}" \
  --retry "${UPLOAD_RETRIES:-3}" \
  --retry-delay "${UPLOAD_RETRY_DELAY:-2}" \
  --retry-connrefused \
  -H "Authorization: Token ${PAPERLESS_TOKEN}" \
  -F "document=@${document}" \
  "${paperless_url}/api/documents/post_document/"
