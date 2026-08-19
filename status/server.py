#!/usr/bin/env python3
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

STARTED_AT = time.time()
QUEUE_DIR = Path(os.getenv("SCAN_QUEUE_DIR", "/var/lib/brother-bridge/queue"))
EVENTS_FILE = Path(os.getenv("BRIDGE_EVENTS_FILE", str(QUEUE_DIR / ".stats/events.jsonl")))
INDEX_FILE = Path(__file__).with_name("index.html")
PORT = int(os.getenv("STATUS_PORT", "8096"))
BIND = os.getenv("STATUS_BIND", "0.0.0.0")
VERSION = os.getenv("BRIDGE_VERSION", "dev")


def load_events():
    events = []
    try:
        with EVENTS_FILE.open(encoding="utf-8") as handle:
            for line in handle:
                try:
                    events.append(json.loads(line))
                except (ValueError, TypeError):
                    continue
    except FileNotFoundError:
        pass
    return events[-1000:]


def command_ok(command):
    try:
        return subprocess.run(
            command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=2, check=False
        ).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def scanner_online():
    address = os.getenv("BRSCAN_IP", "")
    return bool(address) and command_ok(["ping", "-c", "1", "-W", "1", address])


def paperless_online():
    base_url = os.getenv("PAPERLESS_URL", "").rstrip("/")
    if not base_url:
        return False
    request = urllib.request.Request(base_url + "/api/", method="GET")
    token = os.getenv("PAPERLESS_TOKEN", "")
    if token:
        request.add_header("Authorization", "Token " + token)
    try:
        with urllib.request.urlopen(request, timeout=2):
            return True
    except urllib.error.HTTPError as error:
        return error.code < 500
    except (OSError, urllib.error.URLError):
        return False


def build_status():
    events = load_events()
    counts = Counter(item.get("event") for item in events)
    last_failure_clear = max(
        (index for index, item in enumerate(events)
         if item.get("event") == "failure_cleared"),
        default=-1,
    )
    durations = [
        item.get("duration_seconds") for item in events
        if item.get("event") == "processing_succeeded"
        and isinstance(item.get("duration_seconds"), (int, float))
    ]
    queued = list(QUEUE_DIR.glob("*.pdf")) + list(QUEUE_DIR.glob("*.tiff"))
    active_tasks = list(QUEUE_DIR.glob("*.task"))
    failure_types = {"scan_failed", "upload_failed", "processing_failed"}
    failures = [item for index, item in enumerate(events) if index > last_failure_clear
                and item.get("event") in failure_types]
    successes = [item for item in events if item.get("event") == "processing_succeeded"]
    history_types = {
        "scan_queued", "processing_succeeded", "processing_failed",
        "upload_failed", "processing_pending", "scan_failed"
    }
    return {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "version": VERSION,
        "uptime_seconds": int(time.time() - STARTED_AT),
        "services": {
            "scanner": scanner_online(),
            "paperless": paperless_online(),
            "button_service": command_ok(["pgrep", "-x", "brscan-skey-exe"]),
            "queue_worker": command_ok(["pgrep", "-f", "[q]ueue-worker\\.sh"]),
        },
        "queue": {"documents": len(queued), "active_tasks": len(active_tasks)},
        "statistics": {
            "scans_started": counts["scan_started"],
            "documents_queued": counts["scan_queued"],
            "successful": counts["processing_succeeded"],
            "failed": len(failures),
            "average_processing_seconds": round(sum(durations) / len(durations), 1)
            if durations else None,
        },
        "last_success": successes[-1] if successes else None,
        "last_failure": failures[-1] if failures else None,
        "history": [item for index, item in enumerate(events)
                    if item.get("event") in history_types
                    and (item.get("event") not in failure_types
                         or index > last_failure_clear)][-20:][::-1],
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "BrotherBridgeStatus/1"

    def send_bytes(self, status, body, content_type):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/":
            self.send_bytes(200, INDEX_FILE.read_bytes(), "text/html; charset=utf-8")
        elif self.path == "/api/status":
            body = json.dumps(build_status(), separators=(",", ":")).encode()
            self.send_bytes(200, body, "application/json; charset=utf-8")
        elif self.path == "/health":
            self.send_bytes(200, b'{"status":"ok"}', "application/json")
        else:
            self.send_bytes(404, b'{"error":"not found"}', "application/json")

    def log_message(self, message, *args):
        print("status-ui: " + (message % args), flush=True)


if __name__ == "__main__":
    print(f"Status dashboard listening on {BIND}:{PORT}", flush=True)
    ThreadingHTTPServer((BIND, PORT), Handler).serve_forever()
