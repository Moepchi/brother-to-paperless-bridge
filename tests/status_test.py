#!/usr/bin/env python3
import importlib.util
import json
import os
import tempfile
from pathlib import Path


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    queue = root / "queue"
    queue.mkdir()
    events = queue / ".stats" / "events.jsonl"
    events.parent.mkdir()
    events.write_text("\n".join([
        json.dumps({"timestamp": "2026-01-01T10:00:00Z", "event": "scan_started"}),
        json.dumps({"timestamp": "2026-01-01T10:00:02Z", "event": "scan_queued"}),
        json.dumps({"timestamp": "2026-01-01T10:00:08Z", "event": "processing_succeeded", "duration_seconds": 6, "document_id": "42"}),
        "not-json",
    ]) + "\n", encoding="utf-8")
    (queue / "pending.pdf").write_text("pdf", encoding="utf-8")
    (queue / "pending.pdf.task").write_text("task", encoding="utf-8")

    os.environ.update({
        "SCAN_QUEUE_DIR": str(queue),
        "BRIDGE_EVENTS_FILE": str(events),
        "PAPERLESS_TOKEN": "must-never-appear",
        "BRIDGE_VERSION": "test",
    })
    source = Path(__file__).parents[1] / "status" / "server.py"
    spec = importlib.util.spec_from_file_location("status_server", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.scanner_online = lambda: True
    module.paperless_online = lambda: True
    module.command_ok = lambda command: True

    result = module.build_status()
    encoded = json.dumps(result)
    assert result["version"] == "test"
    assert result["queue"] == {"documents": 1, "active_tasks": 1}
    assert result["statistics"]["scans_started"] == 1
    assert result["statistics"]["successful"] == 1
    assert result["statistics"]["average_processing_seconds"] == 6.0
    assert result["last_success"]["document_id"] == "42"
    assert "must-never-appear" not in encoded

print("status dashboard data model passed")
