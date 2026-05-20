FROM debian:bookworm-slim

# Installation der Abhängigkeiten und AirSane Build
RUN apt-get update && apt-get install -y \
    wget sane-utils libsane libsane-dev git cmake build-essential \
    libavahi-client-dev libjpeg-dev libpng-dev libusb-1.0-0-dev \
    avahi-daemon dbus curl iputils-ping ca-certificates libtiff-tools \
    && update-ca-certificates \
    && wget https://slackware.uk/sbosrcarch/by-name/system/brother-brscan4/brscan4-0.4.11-1.amd64.deb -O /tmp/brscan4.deb \
    && dpkg -i /tmp/brscan4.deb \
    && git clone https://github.com/SimulPiscator/AirSane.git /tmp/airsane \
    && cd /tmp/airsane && cmake -DCMAKE_BUILD_TYPE=Release . && make -j$(nproc) install \
    && rm -rf /tmp/airsane /tmp/brscan4.deb /var/lib/apt/lists/*

RUN mkdir -p /opt/brother/scanner/brscan-skey/script/

ENTRYPOINT ["/bin/bash", "-c"]