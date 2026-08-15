#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR=${BRIDGE_SCRIPT_DIR:-/usr/local/lib/brother-bridge}

: "${SCANNER_NAME:=Brother_Scanner}"
: "${SCANNER_MODEL:=MFC-7360N}"
: "${AIRSANE_PORT:=8095}"
: "${STATUS_PORT:=8096}"

"${SCRIPT_DIR}/validate-config.sh"
"${SCRIPT_DIR}/configure-sane.sh"

if [[ -f /tmp/skey.deb ]]; then
  echo "${BRSCAN_SKEY_SHA256}  /tmp/skey.deb" | sha256sum --check --strict
  dpkg -i /tmp/skey.deb || apt-get install -f -y
else
  echo "ERROR: /tmp/skey.deb is missing. Mount the matching brscan-skey package." >&2
  exit 1
fi

if compgen -G '/usr/local/share/ca-certificates/*.crt' >/dev/null; then
  update-ca-certificates
fi

install -d /opt/brother/scanner/brscan-skey/script /var/lib/brother-bridge/queue /var/run/dbus
for trigger in scantoimage.sh scantofile.sh; do
  install -m 0755 "${SCRIPT_DIR}/scan-to-paperless.sh" \
    "/opt/brother/scanner/brscan-skey/script/${trigger}"
done
cp /opt/brother/scanner/brscan-skey/script/scantoimage.sh \
  /opt/brother/scanner/brscan-skey/script/scantoimage-0.3.5-0.sh

brsaneconfig4 -r "${SCANNER_NAME}" >/dev/null 2>&1 || true
brsaneconfig4 -a \
  name="${SCANNER_NAME}" \
  model="${SCANNER_MODEL}" \
  ip="${BRSCAN_IP}"

rm -f /var/run/dbus/pid
dbus-daemon --system --fork
avahi-daemon -D

echo "Registering scan target '${SCAN_PC_NAME}' on ${SCANNER_MODEL} (${BRSCAN_IP})"
brscan-skey -u "${SCAN_PC_NAME}"
brscan-skey -r

"${SCRIPT_DIR}/retry-queue.sh" || true
"${SCRIPT_DIR}/queue-worker.sh" &

if [[ "${STATUS_ENABLED:-true}" == true ]]; then
  python3 /usr/local/share/brother-bridge/status/server.py &
fi

echo "SYSTEM READY: AirSane is listening on port ${AIRSANE_PORT}"
exec /usr/local/bin/airsaned \
  --listen-port="${AIRSANE_PORT}" \
  --access-log=- \
  --debug="${AIRSANE_DEBUG:-false}"
