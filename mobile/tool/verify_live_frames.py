"""Verify production Dart YUV conversion and decoding around actual TFLite inference.

Run from repo root using the existing isolated model-export Python environment.
Uses only local images and writes ignored artifacts under mobile/build/.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
import numpy as np
from PIL import Image, ImageOps
import tensorflow as tf

root = Path(__file__).resolve().parents[2]
mobile = root / "mobile"
build = mobile / "build"
build.mkdir(exist_ok=True)
asset = mobile / "assets/models/best.tflite"
metadata = json.loads(asset.with_name("model.json").read_text())
assert hashlib.sha256(asset.read_bytes()).hexdigest() == metadata["tflite_sha256"]
assert hashlib.sha256((root / metadata["source"]).read_bytes()).hexdigest() == metadata["source_sha256"]
interpreter = tf.lite.Interpreter(model_path=str(asset), num_threads=3)
interpreter.allocate_tensors()
inp = interpreter.get_input_details()[0]
out = interpreter.get_output_details()[0]
best_score, selected = 0, None
images = [p for p in sorted((root / "backend/uploads").iterdir())
          if p.suffix.lower() in (".jpg", ".jpeg", ".png")][:10]
for path in images:
    with Image.open(path) as photo:
        image = ImageOps.pad(ImageOps.exif_transpose(photo).convert("RGB"),
                             (320, 320), color=(114, 114, 114))
        tensor = np.asarray(image, dtype=np.float32)[None] / 255
    interpreter.set_tensor(inp["index"], tensor)
    interpreter.invoke()
    score = float(interpreter.get_tensor(out["index"])[..., 4].max())
    if score > best_score:
        best_score, selected = score, path
assert selected is not None and best_score >= .25, "No positive local road sample found"
shutil.copyfile(selected, build / "live-frame-source.jpg")
flutter = shutil.which("flutter")
assert flutter, "Flutter must be on PATH"
subprocess.run([flutter, "test", "--no-pub", "tool/check_live_frame.dart"], cwd=mobile, check=True)
tensor = np.fromfile(build / "live-frame-input.bin", dtype=np.float32).reshape(1, 320, 320, 3)
interpreter.set_tensor(inp["index"], tensor)
interpreter.invoke()
interpreter.get_tensor(out["index"]).tofile(build / "live-frame-output.bin")
subprocess.run([flutter, "test", "--no-pub", "--dart-define=LIVE_FRAME_STAGE=decode",
                "tool/check_live_frame.dart"], cwd=mobile, check=True)
with Image.open(build / "live-frame-evidence.jpg") as evidence:
    evidence.verify()
report = {**json.loads((build / "live-frame-conversion.json").read_text()),
          **json.loads((build / "live-frame-result.json").read_text()),
          "model_sha256": metadata["tflite_sha256"],
          "note": "Host integration test with synthetic strided camera planes; physical camera/FPS not verified."}
(build / "live-pipeline-verification.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
