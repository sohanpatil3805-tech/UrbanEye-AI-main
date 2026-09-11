"""Exercise the unchanged /detect -> /events flow in an isolated local API.

Run after verify_live_frames.py using backend/venv's Python. No running server,
website data, backend source file, or backend upload directory is modified.
"""
import json
import os
from pathlib import Path
import sys
import time

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "backend"))
from fastapi.testclient import TestClient
from PIL import Image
from app.main import app

build = root / "mobile/build"
directory = build / "monitoring-api-check"
directory.mkdir(exist_ok=True)
os.chdir(directory)
image = (build / "live-frame-evidence.jpg").read_bytes()
local = json.loads((build / "live-frame-result.json").read_text())
metadata = {"latitude": "12.3", "longitude": "77.4",
            "confidence": str(local["max_confidence"]), "severity": "high",
            "timestamp": "2026-09-11T12:00:00Z", "source": "monitoring"}
# The Dart uploader embeds exactly this standard JPEG comment segment.
comment = json.dumps(metadata).encode()
image = image[:2] + b"\xff\xfe" + (len(comment) + 2).to_bytes(2, "big") + comment + image[2:]
with TestClient(app) as client:
    started = time.perf_counter()
    response = client.post("/detect", data=metadata,
                           files={"file": ("monitoring.jpg", image, "image/jpeg")})
    elapsed = time.perf_counter() - started
    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["incidents"], payload
    events = client.get("/events").json()
    assert any(event["event_type"] == "pothole" and event["latitude"] == 12.3
               and event["longitude"] == 77.4 for event in events), events
    with Image.open(directory / "uploads" / payload["filename"]) as saved:
        assert json.loads(saved.info["comment"]) == metadata
    report = {"http_status": response.status_code, "backend_seconds": elapsed,
              "pothole_events": sum(e["event_type"] == "pothole" for e in events),
              "jpeg_metadata_preserved": True,
              "note": "Isolated API test; existing website polls /events every 15 seconds."}
    (build / "monitoring-backend-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
