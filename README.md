# Brother to Paperless-ngx Bridge 🖨️🐳📄

This Docker container bridges the gap between legacy Brother MFC scanners (using `brscan4`) and **Paperless-ngx**. It utilizes **AirSane** to provide a modern Web-UI and Apple AirPrint scanning capabilities while managing the automated push to your Paperless consumption directory.

---

## Features
* **Legacy Support:** Built specifically for older Brother scanners (like MFC-7360N and others using `brscan4`).
* **AirSane Integration:** Exposes your scanner via a lightweight web interface and SANE network protocol.
* **Automated Workflow:** Integrates `brscan-skey` to process scans via custom scripts.
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
SCANNER_IP=192.168.1.X
SCANNER_NAME=Brother_MFC
PAPERLESS_URL=http[s]://your-paperless-instance:Port
PAPERLESS_TOKEN=your_secret_api_token
AIRSANE_PORT=8095
```

### 2. Docker Compose (compose.yaml)
You can pull the pre-built image directly from Docker Hub or use the local setup:
```
YAML
services:
  brother-bridge:
    image: moepchi/brother-to-paperless-bridge:latest
    container_name: brother-bridge
    restart: unless-stopped
    ports:
      - "8095:8095" # AirSane Web UI
    env_file:
      - .env
    devices:
      - /dev/bus/usb:/dev/bus/usb # Optional: Only if connected via USB
```

### 3. Start the Engine
Simply spin up the container using Docker Compose:

```Bash
docker compose up -d
```
Open your browser and navigate to http://YOUR_SERVER_IP:8095 to access the AirSane web interface and start scanning straight to Paperless-ngx!

Contributing & License
Feel free to open issues or submit pull requests if you want to add support for other brscan driver versions.

Maintained with ☕ by Moepchi.
