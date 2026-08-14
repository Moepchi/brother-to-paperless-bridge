#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly TMP_ROOT=$(mktemp -d)
trap 'rm -rf -- "${TMP_ROOT}"' EXIT

pass=0
fail=0

run_test() {
  local name=$1
  shift
  if "$@"; then
    printf 'PASS: %s\n' "${name}"
    pass=$((pass + 1))
  else
    printf 'FAIL: %s\n' "${name}" >&2
    fail=$((fail + 1))
  fi
}

valid_config() {
  BRSCAN_IP=192.168.1.20 \
  PAPERLESS_URL=http://paperless:8000 \
  PAPERLESS_TOKEN=secret \
  SCAN_PC_NAME=Paperless \
  AIRSANE_PORT=8095 \
    "${ROOT}/scripts/validate-config.sh"
}

rejects_missing_token() {
  ! BRSCAN_IP=192.168.1.20 \
    PAPERLESS_URL=http://paperless:8000 \
    SCAN_PC_NAME=Paperless \
      "${ROOT}/scripts/validate-config.sh" >/dev/null 2>&1
}

rejects_invalid_retry_interval() {
  ! BRSCAN_IP=192.168.1.20 \
    PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret \
    SCAN_PC_NAME=Paperless \
    QUEUE_RETRY_INTERVAL=0 \
      "${ROOT}/scripts/validate-config.sh" >/dev/null 2>&1
}

rejects_invalid_airsane_debug() {
  ! BRSCAN_IP=192.168.1.20 \
    PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret \
    SCAN_PC_NAME=Paperless \
    AIRSANE_DEBUG=yes \
      "${ROOT}/scripts/validate-config.sh" >/dev/null 2>&1
}

rejects_invalid_skey_checksum() {
  ! BRSCAN_IP=192.168.1.20 \
    PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret \
    SCAN_PC_NAME=Paperless \
    BRSCAN_SKEY_SHA256=not-a-checksum \
      "${ROOT}/scripts/validate-config.sh" >/dev/null 2>&1
}

retry_keeps_failed_upload() {
  local case_dir="${TMP_ROOT}/failed"
  mkdir -p "${case_dir}/bin" "${case_dir}/queue"
  printf 'scan' > "${case_dir}/queue/document.tiff"
  printf '#!/usr/bin/env bash\nexit 22\n' > "${case_dir}/bin/curl"
  chmod +x "${case_dir}/bin/curl"

  ! PATH="${case_dir}/bin:${PATH}" \
    PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret \
    SCAN_QUEUE_DIR="${case_dir}/queue" \
      "${ROOT}/scripts/retry-queue.sh" >/dev/null 2>&1 \
    && [[ -f "${case_dir}/queue/document.tiff" ]]
}

retry_removes_successful_upload() {
  local case_dir="${TMP_ROOT}/success"
  mkdir -p "${case_dir}/bin" "${case_dir}/queue"
  printf 'scan' > "${case_dir}/queue/document.tiff"
  write_successful_curl_mock "${case_dir}/bin/curl"
  chmod +x "${case_dir}/bin/curl"

  PATH="${case_dir}/bin:${PATH}" \
    PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret \
    SCAN_QUEUE_DIR="${case_dir}/queue" \
      "${ROOT}/scripts/retry-queue.sh" >/dev/null \
    && [[ ! -e "${case_dir}/queue/document.tiff" ]]
}

write_successful_curl_mock() {
  local target=$1
  cat > "${target}" <<'EOF'
#!/usr/bin/env bash
output=''
for (( index=1; index <= $#; index++ )); do
  if [[ "${!index}" == --output ]]; then
    next=$((index + 1))
    output=${!next}
  fi
done
if [[ -n "${output}" ]]; then
  printf '"task-success"\n' > "${output}"
else
  printf '[{"task_id":"task-success","status":"SUCCESS","related_document":42}]\n'
fi
EOF
  chmod +x "${target}"
}

uploads_are_serialized() {
  local case_dir="${TMP_ROOT}/serialized"
  mkdir -p "${case_dir}/bin"
  printf 'one' > "${case_dir}/one.tiff"
  printf 'two' > "${case_dir}/two.tiff"
  cat > "${case_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
if ! mkdir "${UPLOAD_TEST_GUARD}" 2>/dev/null; then
  printf 'overlap\n' >> "${UPLOAD_TEST_RESULT}"
fi
sleep 0.2
rmdir "${UPLOAD_TEST_GUARD}" 2>/dev/null || true
output=''
for (( index=1; index <= $#; index++ )); do
  if [[ "${!index}" == --output ]]; then
    next=$((index + 1))
    output=${!next}
  fi
done
if [[ -n "${output}" ]]; then
  printf '"task-success"\n' > "${output}"
else
  printf '[{"status":"SUCCESS"}]\n'
fi
EOF
  chmod +x "${case_dir}/bin/curl"

  PATH="${case_dir}/bin:${PATH}" PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret UPLOAD_LOCK_FILE="${case_dir}/upload.lock" \
    UPLOAD_TEST_GUARD="${case_dir}/guard" UPLOAD_TEST_RESULT="${case_dir}/result" \
    "${ROOT}/scripts/upload-document.sh" "${case_dir}/one.tiff" &
  local first_pid=$!
  PATH="${case_dir}/bin:${PATH}" PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret UPLOAD_LOCK_FILE="${case_dir}/upload.lock" \
    UPLOAD_TEST_GUARD="${case_dir}/guard" UPLOAD_TEST_RESULT="${case_dir}/result" \
    "${ROOT}/scripts/upload-document.sh" "${case_dir}/two.tiff" &
  local second_pid=$!

  wait "${first_pid}" && wait "${second_pid}" \
    && [[ ! -s "${case_dir}/result" ]]
}

pending_task_is_resumed_without_reupload() {
  local case_dir="${TMP_ROOT}/pending-task"
  mkdir -p "${case_dir}/bin" "${case_dir}/queue"
  printf 'scan' > "${case_dir}/queue/document.tiff"
  printf 'existing-task\n' > "${case_dir}/queue/document.tiff.task"
  cat > "${case_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *' -F '* ]]; then
  printf 'unexpected upload\n' >> "${TASK_TEST_RESULT}"
  exit 1
fi
printf '[{"task_id":"existing-task","status":"SUCCESS","related_document":42}]\n'
EOF
  chmod +x "${case_dir}/bin/curl"

  PATH="${case_dir}/bin:${PATH}" \
    PAPERLESS_URL=http://paperless:8000 PAPERLESS_TOKEN=secret \
    SCAN_QUEUE_DIR="${case_dir}/queue" TASK_TEST_RESULT="${case_dir}/result" \
      "${ROOT}/scripts/retry-queue.sh" >/dev/null \
    && [[ ! -e "${case_dir}/queue/document.tiff" ]] \
    && [[ ! -e "${case_dir}/queue/document.tiff.task" ]] \
    && [[ ! -s "${case_dir}/result" ]]
}

pending_task_keeps_document_and_task_id() {
  local case_dir="${TMP_ROOT}/task-timeout"
  mkdir -p "${case_dir}/bin" "${case_dir}/queue"
  printf 'scan' > "${case_dir}/queue/document.tiff"
  cat > "${case_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
output=''
for (( index=1; index <= $#; index++ )); do
  if [[ "${!index}" == --output ]]; then
    next=$((index + 1))
    output=${!next}
  fi
done
if [[ -n "${output}" ]]; then
  printf '"task-pending"\n' > "${output}"
else
  printf '[{"task_id":"task-pending","status":"PENDING"}]\n'
fi
EOF
  chmod +x "${case_dir}/bin/curl"

  ! PATH="${case_dir}/bin:${PATH}" \
    PAPERLESS_URL=http://paperless:8000 PAPERLESS_TOKEN=secret \
    SCAN_QUEUE_DIR="${case_dir}/queue" PAPERLESS_TASK_TIMEOUT=1 \
    PAPERLESS_TASK_POLL_INTERVAL=1 \
      "${ROOT}/scripts/retry-queue.sh" >/dev/null 2>&1 \
    && [[ -f "${case_dir}/queue/document.tiff" ]] \
    && [[ $(<"${case_dir}/queue/document.tiff.task") == task-pending ]]
}

healthcheck_accepts_running_services() {
  local case_dir="${TMP_ROOT}/health"
  mkdir -p "${case_dir}/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${case_dir}/bin/pgrep"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${case_dir}/bin/curl"
  chmod +x "${case_dir}/bin/"*
  PATH="${case_dir}/bin:${PATH}" "${ROOT}/scripts/healthcheck.sh"
}

prepare_scan_mocks() {
  local case_dir=$1
  local curl_exit=$2
  mkdir -p "${case_dir}/bin" "${case_dir}/queue"

  cat > "${case_dir}/bin/skey-scanimage" <<'EOF'
#!/usr/bin/env bash
output=''
while (( $# > 0 )); do
  if [[ "$1" == --outputfile ]]; then
    output=$2
    break
  fi
  shift
done
printf 'page' > "${output}"
EOF
  cat > "${case_dir}/bin/tiff2pdf" <<'EOF'
#!/usr/bin/env bash
output=''
while (( $# > 0 )); do
  if [[ "$1" == -o ]]; then
    output=$2
    break
  fi
  shift
done
printf 'pdf' > "${output}"
EOF
  if [[ "${curl_exit}" == 0 ]]; then
    write_successful_curl_mock "${case_dir}/bin/curl"
  else
    printf '#!/usr/bin/env bash\nexit %s\n' "${curl_exit}" > "${case_dir}/bin/curl"
  fi
  chmod +x "${case_dir}/bin/"*
}

scan_keeps_document_after_failed_upload() {
  local case_dir="${TMP_ROOT}/scan-failed"
  prepare_scan_mocks "${case_dir}" 22

  ! PATH="${case_dir}/bin:${PATH}" \
    BRIDGE_SCRIPT_DIR="${ROOT}/scripts" \
    SCAN_DEVICE=brother4:net1_dev0 \
    SCAN_QUEUE_DIR="${case_dir}/queue" \
    SCAN_LOCK_DIR="${case_dir}/lock" \
    SKEY_SCANIMAGE="${case_dir}/bin/skey-scanimage" \
    PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret \
      "${ROOT}/scripts/scan-to-paperless.sh" >/dev/null 2>&1 \
    && compgen -G "${case_dir}/queue/*.pdf" >/dev/null
}

scan_removes_document_after_successful_upload() {
  local case_dir="${TMP_ROOT}/scan-success"
  prepare_scan_mocks "${case_dir}" 0

  PATH="${case_dir}/bin:${PATH}" \
    BRIDGE_SCRIPT_DIR="${ROOT}/scripts" \
    SCAN_DEVICE=brother4:net1_dev0 \
    SCAN_QUEUE_DIR="${case_dir}/queue" \
    SCAN_LOCK_DIR="${case_dir}/lock" \
    SKEY_SCANIMAGE="${case_dir}/bin/skey-scanimage" \
    PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret \
      "${ROOT}/scripts/scan-to-paperless.sh" >/dev/null \
    && ! compgen -G "${case_dir}/queue/*.pdf" >/dev/null
}

scan_keeps_tiff_when_pdf_conversion_fails() {
  local case_dir="${TMP_ROOT}/conversion-failed"
  prepare_scan_mocks "${case_dir}" 22
  printf '#!/usr/bin/env bash\nexit 1\n' > "${case_dir}/bin/tiff2pdf"
  chmod +x "${case_dir}/bin/tiff2pdf"

  ! PATH="${case_dir}/bin:${PATH}" \
    BRIDGE_SCRIPT_DIR="${ROOT}/scripts" \
    SCAN_DEVICE=brother4:net1_dev0 \
    SCAN_QUEUE_DIR="${case_dir}/queue" \
    SCAN_LOCK_DIR="${case_dir}/lock" \
    SKEY_SCANIMAGE="${case_dir}/bin/skey-scanimage" \
    PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret \
      "${ROOT}/scripts/scan-to-paperless.sh" >/dev/null 2>&1 \
    && compgen -G "${case_dir}/queue/*.tiff" >/dev/null \
    && ! compgen -G "${case_dir}/queue/*.partial" >/dev/null
}

limits_sane_to_brother_backend() {
  local case_dir="${TMP_ROOT}/sane"
  mkdir -p "${case_dir}/dll.d"
  printf 'escl\nbrother4\nepson2\n' > "${case_dir}/dll.conf"
  printf 'airscan\n' > "${case_dir}/dll.d/airscan"

  SANE_CONFIG_DIR="${case_dir}" "${ROOT}/scripts/configure-sane.sh" >/dev/null \
    && [[ $(<"${case_dir}/dll.conf") == brother4 ]] \
    && ! grep -q '^airscan$' "${case_dir}/dll.d/airscan"
}

for script in "${ROOT}"/entrypoint.sh "${ROOT}"/scripts/*.sh; do
  run_test "syntax $(basename -- "${script}")" bash -n "${script}"
done
run_test 'accepts valid configuration' valid_config
run_test 'rejects missing Paperless token' rejects_missing_token
run_test 'rejects invalid queue retry interval' rejects_invalid_retry_interval
run_test 'rejects invalid AirSane debug flag' rejects_invalid_airsane_debug
run_test 'rejects invalid Brother package checksum' rejects_invalid_skey_checksum
run_test 'failed upload remains queued' retry_keeps_failed_upload
run_test 'successful upload leaves queue empty' retry_removes_successful_upload
run_test 'concurrent uploads are serialized' uploads_are_serialized
run_test 'existing Paperless task resumes without another upload' pending_task_is_resumed_without_reupload
run_test 'pending Paperless task keeps document and task ID' pending_task_keeps_document_and_task_id
run_test 'healthcheck accepts running services' healthcheck_accepts_running_services
run_test 'failed upload after scan preserves document' scan_keeps_document_after_failed_upload
run_test 'successful upload after scan clears document' scan_removes_document_after_successful_upload
run_test 'failed PDF conversion safely queues the original TIFF' scan_keeps_tiff_when_pdf_conversion_fails
run_test 'SANE discovery is limited to brother4' limits_sane_to_brother_backend

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
(( fail == 0 ))
