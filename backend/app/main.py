from pathlib import Path

from fastapi import FastAPI, File, UploadFile

from .models import EventPayload, EventResponse, LocationPayload, UploadResponse
from .services.detector import run_yolov8_stub
from .services.firebase import publish_event_placeholder

app = FastAPI(
    title="UrbanEye AI Backend",
    description="FastAPI backend scaffold for UrbanEye AI (SIH26124)",
    version="0.1.0",
)

locations: list[LocationPayload] = []
events: list[EventResponse] = []


@app.get("/", tags=["Health"])
def root() -> dict[str, str]:
    return {"message": "UrbanEye AI backend running"}


@app.post("/location", tags=["Telemetry"])
def ingest_location(payload: LocationPayload) -> dict[str, object]:
    locations.append(payload)
    return {
        "message": "Location recorded",
        "count": len(locations),
        "latest": payload,
    }


@app.post("/upload", response_model=UploadResponse, tags=["Vision"])
async def upload_frame(file: UploadFile = File(...)) -> UploadResponse:
    uploads_dir = Path("uploads")
    uploads_dir.mkdir(parents=True, exist_ok=True)
    destination = uploads_dir / file.filename
    content = await file.read()
    destination.write_bytes(content)

    stub_result = run_yolov8_stub(destination)
    return UploadResponse(
        filename=file.filename,
        message="File received successfully",
        yolo_stub_result=stub_result,
    )


@app.post("/events", response_model=EventResponse, tags=["Events"])
def create_event(payload: EventPayload) -> EventResponse:
    event = EventResponse(id=len(events) + 1, **payload.model_dump())
    events.append(event)
    publish_event_placeholder(event.model_dump())
    return event


@app.get("/events", response_model=list[EventResponse], tags=["Events"])
def list_events() -> list[EventResponse]:
    return events
