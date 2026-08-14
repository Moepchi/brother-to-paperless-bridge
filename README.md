# Brother to Paperless-ngx Bridge 🖨️🐳📄

This Docker container bridges the gap between legacy Brother MFC scanners (using `brscan4`) and **Paperless-ngx**. It utilizes **AirSane** to provide a modern Web-UI and Apple AirPrint scanning capabilities while managing the automated push to your Paperless consumption directory.

---

## Features
* **Legacy Support:** Built specifically for older Brother scanners (like MFC-7360N and others using `brscan4`).
* **AirSane Integration:** Exposes your scanner via a lightweight web interface and SANE network protocol.
* **Automated Workflow:** Integrates `brscan-skey` to process scans via custom scripts.
* **Safe Delivery:** Stores completed scans in a persistent queue until Paperless accepts them.
* **Secure Setup:** Environment-variable driven configuration (no hardcoded credentials).

---

## Prerequisites
Before deploying, make sure you have:
1. The static IP address of your Brother scanner.
2. A running Paperless-ngx instance.
3. The specific `.deb` drivers for your Brother scanner (if required during your own custom image builds).

---

## Quick Start

### 1. Configuration (`.env`)
Create an `.env` file based on the provided `example.env`:

```env
    BRSCAN_IP=192.168.1.X
    SCANNER_NAME=Brother_Scanner
    SCANNER_MODEL=MFC-7360N
    SCAN_PC_NAME=ScanToPaperless
    PAPERLESS_URL=http[s]://your-paperless-instance:Port
    PAPERLESS_TOKEN=your_secret_api_token
    AIRSANE_PORT=8095
    SCAN_DEVICE="brother4:net1;dev0"
    SCAN_MODE=True Gray
    SCAN_RESOLUTION=100
    SCAN_SOURCE=FB
    SCAN_SIZE=A4
    SCAN_DUPLEX=false
    QUEUE_RETRY_INTERVAL=60
```

### 2. Docker Compose (compose.yaml)
Build the image locally so the Brother driver package can be supplied according to its license:
```
YAML
services:
  brother-bridge:
        build: .
        image: brother-to-paperless-bridge:local
    container_name: brother-bridge
    restart: unless-stopped
        network_mode: host
        env_file: [.env]
        volumes:
          - ./brscan-skey-0.3.5-0.amd64.deb:/tmp/skey.deb:ro
          - scan-queue:/var/lib/brother-bridge/queue

    volumes:
      scan-queue:
```

### 3. Start the Engine
Simply spin up the container using Docker Compose:

```Bash
docker compose up -d
```
Open `http://YOUR_SERVER_IP:8095` for AirSane scans to a browser or compatible client.
The scanner's `Scan to Image` and `Scan to File` hardware-button actions use Brother's
`skey-scanimage` helper and send the resulting multi-page TIFF to Paperless-ngx. Supported
sources are `FB` (flatbed), `ADF_L` (left-aligned feeder), and `ADF_C` (centered feeder).

By default, the container enables only the `brother4` SANE backend. This keeps device
discovery fast and prevents the bundled AirScan backend from rediscovering AirSane itself.
Set `SANE_ONLY_BROTHER4=false` only when the same container intentionally needs other
SANE backends.

The default network-scanner setup does not run the container in privileged mode. If you
adapt the stack for a scanner connected by USB, map only that USB device explicitly instead
of granting unrestricted host-device access.

If Paperless is unavailable or rejects an upload, the completed document remains in the
persistent `scan-queue` volume. Queued documents are retried when the container starts,
and periodically in the background. An upload failure therefore never deletes the scan.
The retry interval defaults to 60 seconds and can be changed with
`QUEUE_RETRY_INTERVAL`. Uploads are serialized with a shared lock so the scan handler
and background retry worker cannot submit the same document at the same time.

Docker also checks the Brother button service, queue worker, and AirSane endpoint every
30 seconds. `docker compose ps` reports the container as `healthy` when all three are
available.

### Custom certificates

The included Compose file expects `rootCA.crt` for installations that use a private CA.
If your Paperless instance uses a publicly trusted certificate or plain HTTP on a trusted
local network, remove the `rootCA.crt` volume line from `compose.yaml`.

### Tests

Run the dependency-free regression checks with:

```bash
bash tests/run.sh
```

The build uses a separate AirSane build stage, while the final image contains only runtime
packages. AirSane is checked out at a pinned Git commit and the Brother driver download is
SHA-256 verified. Override the corresponding Docker build arguments only when intentionally
upgrading either component.

Contributing & License
Feel free to open issues or submit pull requests if you want to add support for other brscan driver versions.

Maintained with ☕ by Moepchi.
