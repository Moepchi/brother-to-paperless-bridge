<div align="center">

# Brother → Paperless-ngx Bridge

**Use the hardware scan button on a legacy Brother network scanner to deliver documents safely to Paperless-ngx.**

[![Release](https://img.shields.io/github/v/release/Moepchi/brother-to-paperless-bridge?display_name=tag&sort=semver)](https://github.com/Moepchi/brother-to-paperless-bridge/releases/latest)
[![Tests](https://github.com/Moepchi/brother-to-paperless-bridge/actions/workflows/tests.yml/badge.svg)](https://github.com/Moepchi/brother-to-paperless-bridge/actions/workflows/tests.yml)
[![Container](https://github.com/Moepchi/brother-to-paperless-bridge/actions/workflows/container.yml/badge.svg)](https://github.com/Moepchi/brother-to-paperless-bridge/actions/workflows/container.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-22c55e.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20amd64-2563eb.svg)](#compatibility)

[Quick start](#quick-start) · [Configuration](#configuration) · [Operations](#operations) · [Troubleshooting](#troubleshooting)

</div>

---

## Why this bridge exists

Older Brother MFC devices can expose their scanner through the proprietary `brscan4`
driver and send hardware-button events through `brscan-skey`. This container connects that
legacy workflow to the Paperless-ngx API and also exposes the scanner through AirSane.

| Capability | What it provides |
| --- | --- |
| 🖨️ Hardware-button scanning | Supports Brother **Scan to File** and **Scan to Image** actions |
| 📥 Safe delivery | A completed scan enters a persistent queue before any upload is attempted |
| 🔁 Automatic recovery | Failed uploads are retried after startup and periodically in the background |
| 🧯 Duplicate protection | The scan handler and retry worker cannot upload at the same time |
| 🩺 Observable health | Docker checks AirSane, the Brother button service, and the queue worker |
| 🔒 Safer runtime | Network-scanner deployments run without privileged container access |
| 📱 AirSane | Makes the scanner available to compatible eSCL/AirScan clients and a small web UI |
| 📊 Status dashboard | Shows service health, queue depth, delivery statistics, and recent activity |

```text
Brother scan button → brscan-skey → multi-page TIFF → PDF queue → Paperless task
                                  └── keep until processing succeeds ──┘
```

## Compatibility

| Component | Status |
| --- | --- |
| Brother MFC-7360N over Ethernet | ✅ Tested |
| Other network scanners supported by `brscan4` | 🧪 Expected to work, hardware reports welcome |
| Linux `amd64` Docker host | ✅ Supported |
| USB-connected scanners | ⚠️ Not tested; map the specific USB device instead of enabling privileged mode |
| Paperless-ngx | ✅ Uses the document upload API |

The bundled defaults and package checksums currently target `brscan4 0.4.11-1` and
`brscan-skey 0.3.5-0` for `amd64`.

## Prerequisites

- Docker Engine with Docker Compose v2
- A Brother network scanner with a static IP address
- A reachable Paperless-ngx instance and API token
- The Brother **Scan Key Tool for Linux** package
  `brscan-skey-0.3.5-0.amd64.deb`

Brother's Scan Key Tool is proprietary and is therefore not redistributed in this
repository. Download the Linux package for your model from
[Brother Support](https://support.brother.com/) and review Brother's
[Scan Key Tool instructions](https://support.brother.com/g/b/faqend.aspx?c=at&faqid=faq00100714_000&lang=de&prod=mfc7360n_all).

## Quick start

### 1. Get the project

```bash
git clone https://github.com/Moepchi/brother-to-paperless-bridge.git
cd brother-to-paperless-bridge
cp example.env .env
```

Place the Brother package beside `compose.yaml`:

```text
brother-to-paperless-bridge/
├── brscan-skey-0.3.5-0.amd64.deb
├── certs/                       # optional private CA certificates
├── compose.yaml
├── Dockerfile
└── .env
```

### 2. Configure the bridge

Edit `.env` and set at least these values:

```dotenv
BRSCAN_IP=192.168.1.50
SCANNER_MODEL=MFC-7360N
SCAN_PC_NAME=ScanToPaperless

PAPERLESS_URL=http://192.168.1.100:8000
PAPERLESS_TOKEN=replace_with_your_api_token

SCAN_DEVICE="brother4:net1;dev0"
```

Keep the quotes around `SCAN_DEVICE`: the semicolon has special meaning in shell syntax.
The default `BRSCAN_SKEY_SHA256` already matches
`brscan-skey-0.3.5-0.amd64.deb`. When intentionally using another package, calculate its
SHA-256 checksum and update the variable before starting the container.

Protect the file because it contains your Paperless token:

```bash
chmod 600 .env
```

### 3. Add an optional private CA

The included Compose file mounts the `certs/` directory. No Compose editing or placeholder
certificate is required:

- **Private certificate authority:** place one or more PEM `.crt` files in `./certs/`.
- **Publicly trusted HTTPS or trusted local HTTP:** leave `./certs/` empty.

### 4. Pull and start

```bash
docker compose pull
docker compose up -d
docker compose ps
```

The default image is published as
`ghcr.io/moepchi/brother-to-paperless-bridge:latest`. It contains the open-source bridge,
AirSane, and the `brscan4` network driver. The proprietary Scan Key Tool is installed from
your locally mounted Brother package whenever the container starts.

After the start period, Compose should report the container as `healthy`. AirSane is then
available at `http://DOCKER_SERVER_IP:8095` and the bridge dashboard at
`http://DOCKER_SERVER_IP:8096`.

### 5. Make the first scan

On the scanner, select **Scan → File → ScanToPaperless** (wording varies by model). The
document is scanned as a multi-page TIFF, placed safely in the queue, and submitted to
Paperless-ngx.

## Configuration

The complete, commented configuration lives in [`example.env`](example.env).

### Scanner

| Variable | Default | Description |
| --- | --- | --- |
| `BRSCAN_IP` | required | Static IP address of the Brother scanner |
| `SCANNER_NAME` | `Brother_Scanner` | Internal SANE registration name |
| `SCANNER_MODEL` | `MFC-7360N` | Exact model passed to `brsaneconfig4` |
| `SCAN_PC_NAME` | required | Target shown on the scanner; maximum 15 characters |
| `SCAN_DEVICE` | auto-detect | Direct SANE device, commonly `brother4:net1;dev0` |
| `SCAN_RESOLUTION` | `100` | Resolution used by Brother's hardware-button helper |
| `SCAN_SOURCE` | `FB` | `FB`, `ADF_L`, or `ADF_C` |
| `SCAN_SIZE` | `A4` | Page size passed to the Brother helper |
| `SCAN_DUPLEX` | `false` | Enables duplex where supported by model and source |

### Paperless and reliability

| Variable | Default | Description |
| --- | --- | --- |
| `PAPERLESS_URL` | required | Base URL of Paperless-ngx, without a trailing API path |
| `PAPERLESS_TOKEN` | required | Paperless API token |
| `UPLOAD_RETRIES` | `3` | Immediate retries for one upload attempt |
| `UPLOAD_LOCK_TIMEOUT` | `330` | Maximum wait for another active uploader |
| `PAPERLESS_TASK_TIMEOUT` | `300` | Seconds to wait for one Paperless processing task |
| `PAPERLESS_TASK_POLL_INTERVAL` | `5` | Seconds between task status checks |
| `QUEUE_RETRY_INTERVAL` | `60` | Seconds between background queue retries |

### AirSane and diagnostics

| Variable | Default | Description |
| --- | --- | --- |
| `AIRSANE_PORT` | `8095` | AirSane HTTP/eSCL port on the Docker host |
| `AIRSANE_DEBUG` | `false` | Enables verbose AirSane diagnostics |
| `STATUS_ENABLED` | `true` | Enables the lightweight bridge dashboard |
| `STATUS_PORT` | `8096` | Dashboard and JSON status API port |
| `STATUS_BIND` | `0.0.0.0` | Address on which the dashboard listens |
| `SANE_ONLY_BROTHER4` | `true` | Avoids slow discovery and AirSane discovering itself |

## Status dashboard

Open `http://DOCKER_SERVER_IP:8096` to see:

- scanner, Paperless, Brother button service, and queue worker availability
- queued documents and currently tracked Paperless tasks
- successful deliveries, failures, and average Paperless processing time
- the latest delivery history and Paperless document IDs
- running bridge version and dashboard uptime

The JSON representation is available at `/api/status`; `/health` provides a minimal
monitoring endpoint. Events are stored under `.stats/` in the persistent queue volume and
survive ordinary container recreation. The history is automatically bounded to 1,000 recent
events after rotation. Neither the Paperless token nor document contents are exposed.

The dashboard has no built-in authentication. Keep it on a trusted LAN, bind it to a specific
local address with `STATUS_BIND`, protect it through a reverse proxy, or disable it with
`STATUS_ENABLED=false` when the Docker host is reachable from an untrusted network.

## How safe delivery works

1. The Brother helper completes the scan in a temporary directory.
2. The finished TIFF is converted to PDF and moved atomically into the persistent `scan-queue` volume.
   If conversion fails, the original TIFF is preserved instead of discarding the scan.
3. The bridge requests a Paperless upload while holding a shared upload lock.
4. The returned Paperless task ID is stored beside the queued document.
5. The bridge follows that task until Paperless reports successful processing.
6. Only then are the PDF and task ID removed.

Timeouts and connection failures keep both files for the background worker, which resumes
the existing task instead of uploading the document again. A task that explicitly fails is
cleared so the original PDF can be submitted again later. Existing queued TIFF files remain
supported during upgrades. The queue survives container
recreation and server restarts.

## Operations

### Status and logs

```bash
docker compose ps
docker compose logs --tail=100 brother-bridge
docker compose logs -f brother-bridge
```

### Inspect queued documents

```bash
docker exec brother-bridge \
  find /var/lib/brother-bridge/queue -maxdepth 1 -type f \
    \( -name '*.pdf' -o -name '*.tiff' \) -print
```

Do not delete queued files unless you have confirmed that the corresponding documents are
already present in Paperless.

### Update

```bash
git pull --ff-only
docker compose pull
docker compose up -d
docker compose ps
```

The named queue volume is retained during ordinary rebuilds and container recreation. Do
not run `docker compose down -v` unless you intentionally want to remove queued documents.

### Build locally

To build the open-source portion locally instead of pulling the published image:

```bash
BRIDGE_IMAGE=brother-to-paperless-bridge:local docker compose build
BRIDGE_IMAGE=brother-to-paperless-bridge:local docker compose up -d
```

Release tags such as `1.2.0`, `1.2`, and `1` are also published for installations that prefer
an explicitly pinned version over `latest`. The `edge` tag follows the current `main` branch.

## Troubleshooting

### The scanner says “Check connection” / “Verbindung prüfen”

- Confirm that `BRSCAN_IP` points to the scanner, not the Docker server.
- Confirm that the scanner can reach the Docker server on the local network.
- Keep `network_mode: host`; Brother's button service relies on network discovery/events.
- Check that `SCAN_PC_NAME` is at most 15 characters.
- Inspect logs with `docker compose logs --tail=100 brother-bridge`.

### The container is unhealthy

```bash
docker inspect --format '{{json .State.Health}}' brother-bridge
docker exec brother-bridge /usr/local/lib/brother-bridge/healthcheck.sh
```

The healthcheck requires AirSane, `brscan-skey`, and the queue worker to be running.

### The scan is not visible in Paperless

Check the queue and logs first. A queued PDF (or an older TIFF) means scanning succeeded, but its upload or
Paperless processing has not completed yet. A neighboring `.task` file contains the accepted
Paperless task ID. Verify `PAPERLESS_URL`, the API token, TLS trust, and connectivity from the
Docker server. The worker resumes automatically; restarting is normally unnecessary.

### The Brother package checksum fails

Do not bypass this check for an unexplained mismatch. Confirm that the package came from
Brother, calculate its checksum with `sha256sum`, and update `BRSCAN_SKEY_SHA256` only when
the different package is intentional.

### AirSane is slow or discovers itself

Leave `SANE_ONLY_BROTHER4=true`. Enable other SANE backends only if this same container must
serve additional non-Brother scanners.

## Security notes

- The network-scanner setup does not require `privileged: true`.
- The Paperless token stays in `.env`; never commit that file.
- AirSane is exposed through host networking. Restrict access with your host firewall when
  the Docker server is reachable from untrusted networks.
- The status dashboard is read-only but unauthenticated; apply the same network restriction.
- AirSane, the Debian base image, and Brother packages are pinned or checksum-verified.

## Development

Run the dependency-free regression suite with:

```bash
bash tests/run.sh
```

The same checks run automatically in GitHub Actions for pushes and pull requests. Pull
requests also build the container without publishing it. Changes merged into `main` publish
the `edge` image; version tags publish matching release images and `latest`.

## License

Released under the [MIT License](LICENSE). Contributions and hardware compatibility reports
are welcome.

<div align="center">

Maintained with ☕ by **Moepchi**

</div>
