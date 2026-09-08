import logging
from contextlib import asynccontextmanager
from datetime import datetime
from io import BytesIO
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from PIL import Image, UnidentifiedImageError
from starlette.concurrency import run_in_threadpool

from .models import EventPayload, EventResponse, LocationPayload, UploadResponse
from .services.detector import run_yolov8_stub
from .services.firebase import publish_event_placeholder
from .services.yolo_service import (
    IncompatibleModelError,
    InferenceError,
    ModelUnavailableError,
    detect_image,
    load_yolo_model,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    try:
        load_yolo_model()
    except ModelUnavailableError:
        # Keep the API available so /detect can return a clear 503 response.
        logger.exception("Road-damage model could not be loaded at startup")
    yield


app = FastAPI(
    title="UrbanEye AI Backend",
    description="FastAPI backend scaffold for UrbanEye AI (SIH26124)",
    version="0.1.0",
    lifespan=lifespan,
)

locations: list[LocationPayload] = []
events: list[EventResponse] = []

_DETECTION_EVENT_TYPES = {
    "Longitudinal Crack": "longitudinal_crack",
    "Transverse Crack": "transverse_crack",
    "Alligator Crack": "alligator_crack",
    "Pothole": "pothole",
}


@app.get("/", tags=["Health"])
def root() -> dict[str, str]:
    return {"message": "UrbanEye AI backend running"}


@app.get("/health", tags=["Health"])
def health() -> dict[str, str]:
    return {"status": "healthy"}


@app.post("/location", tags=["Telemetry"])
def ingest_location(payload: LocationPayload) -> dict[str, str]:
    locations.append(payload)
    logger.info("Received location: %s", payload.model_dump(mode="json"))
    return {"status": "success"}


@app.post("/detect", tags=["Vision"])
async def upload_for_detection(
    file: UploadFile = File(...),
    latitude: float | None = Form(default=None, ge=-90, le=90),
    longitude: float | None = Form(default=None, ge=-180, le=180),
) -> dict[str, object]:
    uploads_dir = Path("uploads")
    extension = Path(file.filename or "").suffix.lower()
    filename = f"{datetime.now():%Y%m%d_%H%M%S_%f}{extension}"
    destination = uploads_dir / filename

    try:
        content = await file.read()
        with Image.open(BytesIO(content)) as image:
            image.verify()
        uploads_dir.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise HTTPException(
            status_code=422, detail="Uploaded file must be a valid image."
        ) from exc
    except Exception as exc:
        logger.exception("Unable to save detection upload")
        raise HTTPException(
            status_code=500, detail="Unable to save uploaded image."
        ) from exc
    finally:
        await file.close()

    try:
        detections = await run_in_threadpool(detect_image, destination)
    except IncompatibleModelError as exc:
        logger.error("Incompatible road-damage model: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ModelUnavailableError as exc:
        logger.error("Road-damage model unavailable: %s", exc)
        raise HTTPException(
            status_code=503, detail="Road-damage model is unavailable."
        ) from exc
    except InferenceError as exc:
        logger.exception("Road-damage inference failed")
        raise HTTPException(
            status_code=500, detail="Unable to process image for detection."
        ) from exc
    except Exception as exc:
        logger.exception("Unexpected road-damage detection failure")
        raise HTTPException(
            status_code=500, detail="Unable to process image for detection."
        ) from exc

    if (latitude is None) != (longitude is None):
        raise HTTPException(
            status_code=422,
            detail="latitude and longitude must be provided together.",
        )

    if latitude is None and locations:
        latest_location = locations[-1]
        latitude = latest_location.latitude
        longitude = latest_location.longitude

    incidents: list[EventResponse] = []
    if latitude is not None and longitude is not None:
        for detection in detections:
            event_type = _DETECTION_EVENT_TYPES.get(str(detection["label"]))
            if event_type is None:
                continue
            event = EventResponse(
                id=len(events) + 1,
                event_type=event_type,
                confidence=float(detection["confidence"]),
                latitude=latitude,
                longitude=longitude,
                source="camera",
            )
            events.append(event)
            incidents.append(event)
            publish_event_placeholder(event.model_dump())

    return {
        "status": "success",
        "filename": filename,
        "detections": detections,
        "incidents": [incident.model_dump(mode="json") for incident in incidents],
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
