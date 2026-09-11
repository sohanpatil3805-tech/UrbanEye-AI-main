"""Export the checkpoint's actual pothole class; verify TFLite against PyTorch.

Run in an environment containing torch, ultralytics, tensorflow, tf-keras,
onnx, onnxruntime, onnx2tf==1.28.2, onnx_graphsurgeon, sng4onnx, ai-edge-litert.
The backend checkpoint is read only. Intermediate files stay in export-work/.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
os.environ.setdefault("TF_ENABLE_ONEDNN_OPTS", "0")

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--dependency-path", help="Optional existing torch/ultralytics site-packages")
args = parser.parse_args()
if args.dependency_path:
    sys.path.append(str(Path(args.dependency_path).resolve()))

import numpy as np
import torch
from ultralytics import YOLO
from onnx2tf import convert
import tensorflow as tf
import onnx
import onnxslim

torch.set_num_threads(3)
source = ROOT / "backend/app/models/best.pt"
work = Path(__file__).parent / "export-work"
work.mkdir(parents=True, exist_ok=True)
destination = ROOT / "mobile/assets/models"
destination.mkdir(parents=True, exist_ok=True)
model = YOLO(str(source)).model.float().eval().fuse()
names = model.names
names = dict(enumerate(names)) if isinstance(names, list) else names
potholes = [int(i) for i, label in names.items() if label.lower() in ("pothole", "potholes")]
if len(potholes) != 1:
    raise ValueError(f"Expected exactly one named pothole class, found {names}")
class_id = potholes[0]
print(f"Checkpoint labels: {names}; exporting only class {class_id} as Pothole", flush=True)
head = model.model[-1]
head.export = True
head.format = "onnx"
head.dynamic = False
head.xyxy = True


class PotholeOnly(torch.nn.Module):
    def __init__(self, detector):
        super().__init__()
        self.detector = detector

    def forward(self, image):
        predictions = self.detector(image)
        # Fixed contract: [1,N,5], normalized x1,y1,x2,y2,confidence.
        return torch.cat((predictions[:, :4] / 320.0,
                          predictions[:, 4 + class_id:5 + class_id]), dim=1).transpose(1, 2)


wrapper = PotholeOnly(model).eval()
sample = torch.rand(1, 3, 320, 320, generator=torch.Generator().manual_seed(42))
with torch.no_grad():
    expected = wrapper(sample).numpy()
    torch.onnx.export(wrapper, sample, str(work / "pothole.onnx"),
                      input_names=["images"], output_names=["detections"],
                      opset_version=17, dynamo=False)
print(f"Exported ONNX {expected.shape}", flush=True)
onnx.save(onnxslim.slim(onnx.load(str(work / "pothole.onnx"))),
          str(work / "pothole.onnx"))
np.save(work / "sample.npy", sample.permute(0, 2, 3, 1).numpy())
# onnx2tf requests dummy images even with custom validation inputs. Supply
# deterministic local dummy data; this is float16 export, not INT8 calibration.
np.save(work / "calibration_image_sample_data_20x128x128x3_float32.npy",
        np.random.default_rng(42).random((20, 128, 128, 3), dtype=np.float32))
os.chdir(work)
convert(input_onnx_file_path=str(work / "pothole.onnx"),
        output_folder_path=str(work / "converted"),
        not_use_onnxsim=True, non_verbose=True,
        disable_strict_mode=False,
        custom_input_op_name_np_data_path=[["images", str(work / "sample.npy")]])

# Float16 weights reduce APK size; input/output and CPU arithmetic remain float32.
candidate = work / "converted/pothole_float16.tflite"
interpreter = tf.lite.Interpreter(model_path=str(candidate), num_threads=3)
interpreter.allocate_tensors()
input_spec = interpreter.get_input_details()[0]
output_spec = interpreter.get_output_details()[0]
assert list(input_spec["shape"]) == [1, 320, 320, 3], input_spec
assert list(output_spec["shape"]) == list(expected.shape), output_spec
errors = []
for tensor in (sample, torch.zeros_like(sample), torch.ones_like(sample) * (114 / 255)):
    with torch.no_grad():
        expected = wrapper(tensor).numpy()
    interpreter.set_tensor(input_spec["index"], tensor.permute(0, 2, 3, 1).numpy())
    interpreter.invoke()
    actual = interpreter.get_tensor(output_spec["index"])
    np.testing.assert_allclose(actual, expected, rtol=0.02, atol=0.015)
    errors.append(float(np.max(np.abs(actual - expected))))
shutil.copyfile(candidate, destination / "best.tflite")
(destination / "labels.txt").write_text("Pothole\n", encoding="utf-8")
metadata = {
    "source": "backend/app/models/best.pt",
    "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "source_labels": names,
    "selected_source_class": class_id,
    "labels": ["Pothole"],
    "input_shape": input_spec["shape"].tolist(),
    "input_type": "float32", "normalization": "RGB / 255, letterbox 114",
    "output_shape": output_spec["shape"].tolist(),
    "output_format": "normalized [x1,y1,x2,y2,confidence], no NMS",
    "weights": "float16", "validation_max_abs_errors": errors,
    "tflite_sha256": hashlib.sha256((destination / "best.tflite").read_bytes()).hexdigest(),
}
(destination / "model.json").write_text(json.dumps(metadata, indent=2) + "\n")
print(json.dumps(metadata, indent=2), flush=True)
