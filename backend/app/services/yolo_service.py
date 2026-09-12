"""Singleton YOLOv5 service for RDD2022 road-damage detection."""

from pathlib import Path
from threading import Lock
from typing import Any

import numpy as np
import torch
from PIL import Image, ImageOps
from ultralytics.data.augment import LetterBox
from ultralytics.utils.nms import non_max_suppression as ultralytics_nms
from ultralytics.utils.ops import scale_boxes


_MODEL_PATH = Path(__file__).resolve().parents[1] / "models" / "best.pt"
_CONFIDENCE_THRESHOLD = 0.20
_IOU_THRESHOLD = 0.40
_MAX_DETECTIONS = 20
_IMAGE_SIZE = 1280
_DETERMINISTIC_SEED = 0

_LABELS = {
    "D00": "Longitudinal Crack",
    "D10": "Transverse Crack",
    "D20": "Alligator Crack",
    "D40": "Pothole",
    "longitudinal_crack": "Longitudinal Crack",
    "transverse_crack": "Transverse Crack",
    "alligator_crack": "Alligator Crack",
    "pothole": "Pothole",
}
_MODEL_NAME_VARIANTS = (
    ("D00", "D10", "D20", "D40"),
    (
        "longitudinal_crack",
        "transverse_crack",
        "alligator_crack",
        "pothole",
    ),
)
_INCOMPATIBLE_MODEL_MESSAGE = (
    "Configured checkpoint is incompatible: expected a YOLOv5 RDD2022 model "
    "with longitudinal crack, transverse crack, alligator crack, and pothole classes."
)


class ModelUnavailableError(RuntimeError):
    """Raised when the RDD2022 model cannot be loaded."""


class IncompatibleModelError(ModelUnavailableError):
    """Raised when a checkpoint is not a YOLOv5 RDD2022 model."""


class InferenceError(RuntimeError):
    """Raised when YOLOv5 cannot process an uploaded image."""


_model: Any | None = None
_model_load_error: ModelUnavailableError | None = None
_model_lock = Lock()
_inference_lock = Lock()


def _ordered_model_names(model: Any) -> tuple[str, ...]:
    """Return model class names ordered by their numeric class IDs."""
    names = getattr(model, "names", None)
    try:
        if isinstance(names, dict):
            normalized_names = {int(index): str(label) for index, label in names.items()}
            ordered_names = tuple(
                normalized_names[index] for index in range(len(normalized_names))
            )
        else:
            ordered_names = tuple(str(label) for label in names)
    except (KeyError, TypeError, ValueError) as exc:
        raise IncompatibleModelError(_INCOMPATIBLE_MODEL_MESSAGE) from exc

    return ordered_names


def _verify_loaded_model(model: Any) -> None:
    """Confirm Hub loaded the four RDD classes in the expected class-id order."""
    if _ordered_model_names(model) not in _MODEL_NAME_VARIANTS:
        raise IncompatibleModelError(_INCOMPATIBLE_MODEL_MESSAGE)


def _configure_model(model: Any) -> None:
    """Apply the fixed inference settings to the shared YOLOv5 model."""
    torch.manual_seed(_DETERMINISTIC_SEED)
    torch.use_deterministic_algorithms(True, warn_only=True)

    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(_DETERMINISTIC_SEED)
        torch.backends.cudnn.benchmark = False
        torch.backends.cudnn.deterministic = True

    model.eval()


def load_yolo_model() -> Any:
    """Load the RDD2022 YOLOv5 model once and reuse it for all requests."""
    global _model, _model_load_error

    if _model is not None:
        return _model
    if _model_load_error is not None:
        raise _model_load_error

    with _model_lock:
        if _model is not None:
            return _model
        if _model_load_error is not None:
            raise _model_load_error

        if not _MODEL_PATH.is_file():
            _model_load_error = ModelUnavailableError(
                f"Road-damage model file is missing: {_MODEL_PATH}"
            )
            raise _model_load_error

        try:
            model = torch.hub.load(
                "ultralytics/yolov5",
                "custom",
                path=str(_MODEL_PATH),
                autoshape=False,
                force_reload=False,
            )
            _verify_loaded_model(model)
            _configure_model(model)
        except ModelUnavailableError as exc:
            _model_load_error = exc
            raise
        except Exception as exc:
            _model_load_error = ModelUnavailableError(
                "Unable to load the road-damage detection model."
            )
            raise _model_load_error from exc

        _model = model
        return _model


def _severity_for(detected_class: str, area_ratio: float) -> str:
    label = _LABELS.get(detected_class, detected_class)

    if label == "Pothole":
        if area_ratio >= 0.10:
            return "Critical"
        if area_ratio >= 0.05:
            return "High"
        return "Medium"

    if label == "Alligator Crack":
        return "High" if area_ratio >= 0.15 else "Medium"

    if label in {"Longitudinal Crack", "Transverse Crack"}:
        return "Medium" if area_ratio >= 0.10 else "Low"

    if label == "Structural Anomaly - Flag for Manual Inspection":
        return "Critical"

    return "Low"


def _model_stride(model: Any) -> int:
    stride = getattr(model, "stride", 32)
    if isinstance(stride, torch.Tensor):
        return int(stride.max().item())
    if isinstance(stride, (list, tuple)):
        return int(max(stride))
    return int(stride)


def _prepare_image(image_path: Path, model: Any) -> tuple[torch.Tensor, tuple[int, int]]:
    """Load an image and convert it to normalized BCHW input for the raw model."""
    with Image.open(image_path) as image_file:
        image = ImageOps.exif_transpose(image_file).convert("RGB")
        original_image = np.array(image, dtype=np.uint8, copy=True)

    original_shape = original_image.shape[:2]
    letterbox = LetterBox(
        new_shape=(_IMAGE_SIZE, _IMAGE_SIZE),
        auto=False,
        stride=_model_stride(model),
    )
    resized_image = letterbox(image=original_image)
    input_tensor = (
        torch.from_numpy(np.ascontiguousarray(resized_image))
        .permute(2, 0, 1)
        .unsqueeze(0)
        .contiguous()
    )

    device = getattr(model, "device", None)
    if device is None:
        device = next(model.parameters()).device
    input_tensor = input_tensor.to(device)
    input_tensor = (
        input_tensor.half() if getattr(model, "fp16", False) else input_tensor.float()
    )
    input_tensor.div_(255.0)
    return input_tensor, original_shape


def _apply_nms(raw_output: Any, class_count: int) -> torch.Tensor:
    """Apply NMS to modern YOLOv5u or legacy YOLOv5 raw predictions."""
    prediction = raw_output[0] if isinstance(raw_output, (list, tuple)) else raw_output
    if not isinstance(prediction, torch.Tensor) or prediction.ndim != 3:
        raise InferenceError("YOLOv5 returned an unsupported prediction format.")

    if prediction.shape[1] == class_count + 4:
        return ultralytics_nms(
            prediction,
            conf_thres=_CONFIDENCE_THRESHOLD,
            iou_thres=_IOU_THRESHOLD,
            max_det=_MAX_DETECTIONS,
            nc=class_count,
        )[0]

    if prediction.shape[2] == class_count + 5:
        from utils.general import non_max_suppression as yolov5_nms

        return yolov5_nms(
            prediction,
            conf_thres=_CONFIDENCE_THRESHOLD,
            iou_thres=_IOU_THRESHOLD,
            max_det=_MAX_DETECTIONS,
        )[0]

    raise InferenceError("YOLOv5 returned an unsupported prediction layout.")


def detect_image(image_path: Path) -> list[dict[str, object]]:
    """Run the shared model on one image and format RDD2022 detections."""
    model = load_yolo_model()

    try:
        input_tensor, original_shape = _prepare_image(image_path, model)
        model_names = _ordered_model_names(model)

        # The lock prevents concurrent requests from changing the shared model's
        # inference state and keeps repeated requests deterministic.
        with _inference_lock, torch.inference_mode():
            raw_output = model(input_tensor, augment=False)
            prediction_tensor = _apply_nms(raw_output, len(model_names))
            
            # Extract max raw confidence to detect OOD scenes
            pred = raw_output[0] if isinstance(raw_output, (list, tuple)) else raw_output
            if pred.shape[-1] == len(model_names) + 5: # YOLOv5 format
                obj_conf = pred[0, :, 4]
                cls_conf = pred[0, :, 5:].max(dim=1).values
                max_conf = (obj_conf * cls_conf).max().item()
            else: # YOLOv8/YOLOv5u format
                max_conf = pred[0, :, 4:].max().item()

            if prediction_tensor.numel():
                scale_boxes(
                    input_tensor.shape[2:],
                    prediction_tensor[:, :4],
                    original_shape,
                )

        predictions = sorted(
            prediction_tensor.detach().cpu().tolist(),
            key=lambda prediction: (
                -float(prediction[4]),
                int(prediction[5]),
                float(prediction[0]),
                float(prediction[1]),
                float(prediction[2]),
                float(prediction[3]),
            ),
        )[:_MAX_DETECTIONS]
        detections: list[dict[str, object]] = []

        image_area = float(original_shape[0] * original_shape[1])

        for (
            x1,
            y1,
            x2,
            y2,
            confidence_value,
            class_id,
        ) in predictions:
            confidence = float(confidence_value)
            raw_label = model_names[int(class_id)]
            box_area = (float(x2) - float(x1)) * (float(y2) - float(y1))
            area_ratio = box_area / image_area if image_area > 0 else 0.0

            detections.append(
                {
                    "label": _LABELS.get(raw_label, raw_label),
                    "confidence": confidence,
                    "bbox": [float(x1), float(y1), float(x2), float(y2)],
                    "severity": _severity_for(raw_label, area_ratio),
                }
            )

        # OOD Fallback Check
        if not detections and max_conf < 0.05:
            detections.append(
                {
                    "label": "Structural Anomaly - Flag for Manual Inspection",
                    "confidence": max_conf,
                    "bbox": [0.0, 0.0, float(original_shape[1]), float(original_shape[0])],
                    "severity": "Critical",
                }
            )

        return detections
    except InferenceError:
        raise
    except Exception as exc:
        raise InferenceError("Road-damage inference failed.") from exc
