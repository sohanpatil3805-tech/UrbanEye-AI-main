from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class LocationPayload(BaseModel):
    vehicle_id: str = Field(..., min_length=1, max_length=64)
    latitude: float = Field(..., ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(..., ge=-180, le=180, allow_inf_nan=False)
    speed: float = Field(..., ge=0, allow_inf_nan=False)
    accuracy: float = Field(..., ge=0, allow_inf_nan=False)
    timestamp: datetime


class EventPayload(BaseModel):
    event_type: Literal["pothole", "traffic", "accident", "other"]
    confidence: float = Field(..., ge=0, le=1)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    source: Literal["mobile", "camera", "manual"] = "camera"
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    depth_cm: float | None = None
    speed_kmh: float | None = None
    device_id: str | None = None
    telemetry: list[dict[str, float]] | None = None
    is_simulated: bool = False


class EventResponse(EventPayload):
    id: int


class UploadResponse(BaseModel):
    filename: str
    message: str
    yolo_stub_result: str
