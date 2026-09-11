"""Compare the packaged mobile model with the source checkpoint on local images."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
parser = argparse.ArgumentParser()
parser.add_argument("--dependency-path")
parser.add_argument("--images", type=Path, required=True)
args = parser.parse_args()
if args.dependency_path:
    sys.path.append(str(Path(args.dependency_path).resolve()))

import numpy as np
from PIL import Image, ImageOps
import tensorflow as tf
import torch
from ultralytics import YOLO

root = Path(__file__).resolve().parents[2]
asset = root / "mobile/assets/models/best.tflite"
metadata = json.loads(asset.with_name("model.json").read_text())
assert hashlib.sha256(asset.read_bytes()).hexdigest() == metadata["tflite_sha256"]
source = root / metadata["source"]
assert hashlib.sha256(source.read_bytes()).hexdigest() == metadata["source_sha256"]
model = YOLO(str(source)).model.float().eval().fuse()
model.model[-1].xyxy = True
torch.set_num_threads(3)
interpreter = tf.lite.Interpreter(model_path=str(asset), num_threads=3)
interpreter.allocate_tensors()
inp = interpreter.get_input_details()[0]
out = interpreter.get_output_details()[0]
errors = []
scores = []
for path in sorted(args.images.iterdir()):
    if path.suffix.lower() not in (".jpg", ".jpeg", ".png"):
        continue
    with Image.open(path) as image:
        upright = ImageOps.exif_transpose(image).convert("RGB")
        resized = ImageOps.contain(upright, (320, 320))
        padded = Image.new("RGB", (320, 320), (114, 114, 114))
        padded.paste(resized, ((320 - resized.width) // 2, (320 - resized.height) // 2))
        data = np.asarray(padded, dtype=np.float32)[None] / 255
    with torch.no_grad():
        raw = model(torch.from_numpy(data.transpose(0, 3, 1, 2).copy()))[0].numpy()
    selected = metadata["selected_source_class"]
    expected = np.concatenate((raw[:, :4] / 320,
                               raw[:, 4 + selected:5 + selected]), axis=1).transpose(0, 2, 1)
    interpreter.set_tensor(inp["index"], data)
    interpreter.invoke()
    actual = interpreter.get_tensor(out["index"])
    np.testing.assert_allclose(actual, expected, rtol=.02, atol=.015)
    errors.append(float(np.max(np.abs(actual - expected))))
    scores.append(float(np.max(actual[:, :, 4])))
    if len(errors) == 10:
        break
if not errors:
    raise ValueError("No validation images found")
for _ in range(3):
    interpreter.invoke()
started = time.perf_counter()
for _ in range(20):
    interpreter.invoke()
report = {"images_checked": len(errors), "max_abs_error": max(errors),
          "max_pothole_confidence": max(scores),
          "desktop_inference_ms": (time.perf_counter() - started) * 1000 / 20,
          "note": "Conversion equivalence only; not an accuracy or Android FPS benchmark.",
          "tflite_sha256": metadata["tflite_sha256"]}
Path(__file__).with_name("model-validation.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
