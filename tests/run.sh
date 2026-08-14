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
  printf '#!/usr/bin/env bash\nexit 0\n' > "${case_dir}/bin/curl"
  chmod +x "${case_dir}/bin/curl"

  PATH="${case_dir}/bin:${PATH}" \
    PAPERLESS_URL=http://paperless:8000 \
    PAPERLESS_TOKEN=secret \
    SCAN_QUEUE_DIR="${case_dir}/queue" \
      "${ROOT}/scripts/retry-queue.sh" >/dev/null \
    && [[ ! -e "${case_dir}/queue/document.tiff" ]]
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
  printf '#!/usr/bin/env bash\nexit %s\n' "${curl_exit}" > "${case_dir}/bin/curl"
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
    && compgen -G "${case_dir}/queue/*.tiff" >/dev/null
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
    && ! compgen -G "${case_dir}/queue/*.tiff" >/dev/null
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
run_test 'failed upload remains queued' retry_keeps_failed_upload
run_test 'successful upload leaves queue empty' retry_removes_successful_upload
run_test 'concurrent uploads are serialized' uploads_are_serialized
run_test 'healthcheck accepts running services' healthcheck_accepts_running_services
run_test 'failed upload after scan preserves document' scan_keeps_document_after_failed_upload
run_test 'successful upload after scan clears document' scan_removes_document_after_successful_upload
run_test 'SANE discovery is limited to brother4' limits_sane_to_brother_backend

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
(( fail == 0 ))
