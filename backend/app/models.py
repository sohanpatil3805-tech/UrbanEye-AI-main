from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class LocationPayload(BaseModel):
    device_id: str = Field(..., min_length=2, max_length=64)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    speed_kmph: Optional[float] = Field(default=None, ge=0)
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class EventPayload(BaseModel):
    event_type: Literal["pothole", "traffic", "accident", "other"]
    confidence: float = Field(..., ge=0, le=1)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    source: Literal["mobile", "camera", "manual"] = "camera"
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class EventResponse(EventPayload):
    id: int


class UploadResponse(BaseModel):
    filename: str
    message: str
    yolo_stub_result: str
