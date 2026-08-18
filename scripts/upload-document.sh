#!/usr/bin/env bash
set -Eeuo pipefail

document=${1:?Usage: upload-document.sh DOCUMENT}
readonly QUEUE_DIR=${SCAN_QUEUE_DIR:-/var/lib/brother-bridge/queue}
readonly UPLOAD_LOCK_FILE=${UPLOAD_LOCK_FILE:-${QUEUE_DIR}/.upload.lock}
readonly UPLOAD_LOCK_TIMEOUT=${UPLOAD_LOCK_TIMEOUT:-330}
readonly TASK_TIMEOUT=${PAPERLESS_TASK_TIMEOUT:-300}
readonly TASK_POLL_INTERVAL=${PAPERLESS_TASK_POLL_INTERVAL:-5}
readonly TASK_FILE="${document}.task"
readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

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

# Another worker may have completed and removed this same queued document
# while this process was waiting for the shared upload lock.
if [[ ! -e "${document}" ]]; then
  echo "Document was already completed by another uploader."
  exit 0
fi

task_id=''
if [[ -s "${TASK_FILE}" ]]; then
  task_id=$(<"${TASK_FILE}")
  echo "Resuming Paperless task ${task_id}."
else
  response_file=$(mktemp)
  error_file=$(mktemp)
  task_partial="${TASK_FILE}.partial"
  cleanup_upload() {
    rm -f -- "${response_file}" "${error_file}" "${task_partial}"
  }
  trap cleanup_upload EXIT

  if ! curl --silent --show-error --fail-with-body \
    --connect-timeout "${UPLOAD_CONNECT_TIMEOUT:-10}" \
    --max-time "${UPLOAD_MAX_TIME:-300}" \
    --retry "${UPLOAD_RETRIES:-3}" \
    --retry-delay "${UPLOAD_RETRY_DELAY:-2}" \
    --retry-connrefused \
    -H "Authorization: Token ${PAPERLESS_TOKEN}" \
    -F "document=@${document}" \
    --output "${response_file}" \
    "${paperless_url}/api/documents/post_document/" 2>"${error_file}"; then
    failure_detail=$(tr '\r\n' '  ' <"${response_file}")
    if [[ -z "${failure_detail}" ]]; then
      failure_detail=$(tr '\r\n' '  ' <"${error_file}")
    fi
    failure_detail=${failure_detail//${PAPERLESS_TOKEN}/[redacted]}
    failure_detail=${failure_detail:0:500}
    "${SCRIPT_DIR}/record-event.sh" upload_failed \
      "Paperless upload request failed${failure_detail:+: ${failure_detail}}" || true
    exit 1
  fi

  task_id=$(jq --raw-output --exit-status \
    'if type == "string" then . elif .task_id then .task_id else empty end' \
    "${response_file}") \
    || { echo "ERROR: Paperless returned no task ID after upload." >&2; "${SCRIPT_DIR}/record-event.sh" upload_failed "Paperless returned no task ID" || true; exit 1; }

  printf '%s\n' "${task_id}" > "${task_partial}"
  mv -- "${task_partial}" "${TASK_FILE}"
  echo "Paperless accepted upload as task ${task_id}; waiting for processing."
  "${SCRIPT_DIR}/record-event.sh" upload_accepted || true
fi

task_started=${SECONDS}
deadline=$((SECONDS + TASK_TIMEOUT))
while (( SECONDS < deadline )); do
  task_json=$(curl --silent --show-error --fail-with-body \
    --connect-timeout "${UPLOAD_CONNECT_TIMEOUT:-10}" \
    --max-time "${UPLOAD_STATUS_MAX_TIME:-30}" \
    -H "Authorization: Token ${PAPERLESS_TOKEN}" \
    --get --data-urlencode "task_id=${task_id}" \
    "${paperless_url}/api/tasks/") \
    || { echo "WARNING: Could not query Paperless task ${task_id}." >&2; return_status=1; break; }

  status=$(jq --raw-output '
    (if type == "array" then .[0]
     elif (.results | type) == "array" then .results[0]
     else . end) // {} | .status // empty | ascii_upcase
  ' <<<"${task_json}")

  case "${status}" in
    SUCCESS)
      document_id=$(jq --raw-output '
        (if type == "array" then .[0]
         elif (.results | type) == "array" then .results[0]
         else . end) // {} | .related_document // empty
      ' <<<"${task_json}")
      # Remove the task marker and document while still holding the upload
      # lock, so the queue worker cannot select the completed file again.
      rm -f -- "${TASK_FILE}" "${document}"
      "${SCRIPT_DIR}/record-event.sh" processing_succeeded "" "$((SECONDS - task_started))" "${document_id}" || true
      echo "Paperless task ${task_id} completed successfully."
      exit 0
      ;;
    FAILURE|REVOKED)
      error_message=$(jq --raw-output '
        (if type == "array" then .[0]
         elif (.results | type) == "array" then .results[0]
         else . end) // {} | .result // .error // "unknown processing error"
      ' <<<"${task_json}")
      rm -f -- "${TASK_FILE}"
      error_message=${error_message//${PAPERLESS_TOKEN}/[redacted]}
      "${SCRIPT_DIR}/record-event.sh" processing_failed \
        "${error_message:0:500}" || true
      echo "ERROR: Paperless task ${task_id} ended as ${status}: ${error_message}" >&2
      exit 1
      ;;
  esac

  sleep "${TASK_POLL_INTERVAL}"
done

echo "WARNING: Paperless task ${task_id} is not finished; its ID remains queued for later polling." >&2
"${SCRIPT_DIR}/record-event.sh" processing_pending "Paperless task will be resumed" || true
exit "${return_status:-75}"
