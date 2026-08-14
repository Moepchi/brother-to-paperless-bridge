ARG DEBIAN_IMAGE=debian:bookworm-slim

FROM ${DEBIAN_IMAGE} AS airsane-builder

ARG AIRSANE_COMMIT=129cc3bf7258251a0a694dee7741285b59d88f9f

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential ca-certificates cmake git \
      libavahi-client-dev libjpeg-dev libpng-dev libsane-dev libusb-1.0-0-dev \
    && git clone --filter=blob:none --no-checkout \
      https://github.com/SimulPiscator/AirSane.git /tmp/airsane \
    && git -C /tmp/airsane checkout --detach "${AIRSANE_COMMIT}" \
    && test "$(git -C /tmp/airsane rev-parse HEAD)" = "${AIRSANE_COMMIT}" \
    && cd /tmp/airsane \
    && cmake -DCMAKE_BUILD_TYPE=Release . \
    && make --jobs "$(nproc)" install

FROM ${DEBIAN_IMAGE}

ARG BRSCAN4_VERSION=0.4.11-1
ARG BRSCAN4_SHA256=027b73648722ac8c8eb1a9c419d284a6562cc763feac9740a2b75a683b092972

RUN apt-get update \
    && apt-get install -y \
      avahi-daemon ca-certificates curl dbus iputils-ping libsane \
      libtiff-tools procps sane-utils util-linux wget \
    && curl --fail --location --silent --show-error \
      "https://slackware.uk/sbosrcarch/by-name/system/brother-brscan4/brscan4-${BRSCAN4_VERSION}.amd64.deb" \
      --output /tmp/brscan4.deb \
    && echo "${BRSCAN4_SHA256}  /tmp/brscan4.deb" | sha256sum --check --strict \
    && apt-get install -y --no-install-recommends /tmp/brscan4.deb \
    && rm -f /tmp/brscan4.deb \
    && rm -rf /var/lib/apt/lists/*

COPY --from=airsane-builder /usr/local/bin/airsaned /usr/local/bin/airsaned
COPY --from=airsane-builder /etc/airsane/ /etc/airsane/
COPY scripts/ /usr/local/lib/brother-bridge/
COPY entrypoint.sh /usr/local/bin/brother-bridge-entrypoint

RUN chmod +x /usr/local/bin/airsaned \
    /usr/local/bin/brother-bridge-entrypoint \
    /usr/local/lib/brother-bridge/*.sh \
    && mkdir -p /opt/brother/scanner/brscan-skey/script \
      /var/lib/brother-bridge/queue

VOLUME ["/var/lib/brother-bridge/queue"]

ENTRYPOINT ["/usr/local/bin/brother-bridge-entrypoint"]
