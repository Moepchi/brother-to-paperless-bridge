#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${SANE_ONLY_BROTHER4:-true}" != true ]]; then
  echo "Keeping all installed SANE backends enabled."
  exit 0
fi

config_dir=${SANE_CONFIG_DIR:-/etc/sane.d}
install -d "${config_dir}"

# This image is a brscan4 bridge. Loading every Debian SANE backend makes
# device discovery slow and lets sane-airscan rediscover AirSane itself.
printf 'brother4\n' > "${config_dir}/dll.conf"

if [[ -d "${config_dir}/dll.d" ]]; then
  while IFS= read -r -d '' backend_file; do
    printf '# Disabled by brother-to-paperless-bridge; brother4 is loaded via dll.conf.\n' \
      > "${backend_file}"
  done < <(find "${config_dir}/dll.d" -maxdepth 1 -type f -print0)
fi
