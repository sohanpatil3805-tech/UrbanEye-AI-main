# urbaneye_mobile

A new Flutter project.

## Start Monitoring: live detection

**Start Monitoring** opens the rear camera and keeps
`CameraController.startImageStream()` running throughout the session. It does
not record video or write images/logs to device storage. Camera Ready, Gallery,
their shared ApiService, website, dashboard, and backend are unchanged.

The bundled `assets/models/best.tflite` was converted from
`backend/app/models/best.pt`. That checkpoint actually contains four classes;
the exporter reads its names and selects **pothole (source index 3)**. Only
`Pothole` is exposed by the mobile model. `model.json` records source/model SHA256
hashes, tensor shapes, and numerical verification. No crack is relabeled as a
pothole. The contract is float32 RGB `[1,320,320,3]`, normalized by 255 with
114-gray letterboxing, and float32 `[1,2100,5]` output rows containing normalized
`[x1,y1,x2,y2,confidence]`. Weights use float16 storage.

The app processes every third camera frame, caps inference submissions at
15 FPS, and drops frames while inference is busy. A persistent isolate performs
stride-aware YUV/BGRA conversion, rotation, inference with three CPU threads,
letterbox reversal, and NMS. Camera preview stays on its native texture;
`CustomPainter` repaints only the overlay. The screen displays measured inference
FPS; 10–15 FPS is a device-dependent target, not a guarantee. Use a release build
on a physical Android device to measure performance.

Boxes include the label, confidence, and severity. Green/yellow/red use apparent
box area: below 3.5%, 3.5–12%, and at least 12% of the frame. This is a visual
size/proximity heuristic; a single-class pothole model cannot measure depth or
physical damage severity.

`Confirmed` increments on the first observation at confidence ≥25%, after NMS
(IoU 0.45). Overlapping observations at IoU ≥0.30 refresh a ten-second duplicate
window; continuous visibility produces only one confirmation. GPS, network
access, and server inference never gate live boxes or confirmation.

Only newly confirmed frames are encoded as upright JPEGs in the worker isolate
and sent to the existing **POST `/detect`**, using multipart `file`, latitude,
longitude, confidence, severity, timestamp, and per-detection bounding boxes.
The GPS timestamp and accuracy are included. Extra local metadata is also stored
in a standard JPEG comment, preserving it in the image the backend already saves.
The unchanged backend independently runs inference and populates `/events`;
it ignores the extra multipart metadata and uses its own confidence/timestamp
for events. The website reads these events on its existing **15-second poll**.
Faster website updates or using local metadata as event fields would require
changes outside this monitoring-only scope.

GPS fixes must have valid coordinates and be within 30 seconds of the detection.
There is no accuracy gate preventing indoor confirmation; actual accuracy is
displayed and sent. Frames waiting for the first GPS fix remain in memory for
up to 30 seconds, with at most 20 queued frames. No coordinates are invented.
Uploads are serialized, time out after 60 seconds, and cancel on stop. Failed
requests are shown on screen and not blindly retried because `/detect` is not
idempotent. Backend re-inference can return zero events for an accepted image;
the UI explicitly distinguishes images uploaded from backend incidents.

Diagnostics show Camera FPS, AI FPS, Model Loaded, Last Inference (ms),
Detections This Frame, Confirmed, Image Stream, Frames Received, Peak Confidence,
GPS status, and upload status. A periodically refreshed RGB model-input thumbnail
exposes bad conversion/orientation even when inference finds nothing. The model
is reported loaded only after tensor checks and a successful warmup invocation.
Background/Back stop streaming and release resources; resume requires another
Start. Android API 26 or later is required.

To reproduce the model (Python 3.13 was used):

```sh
python -m venv .model-export
# Activate the isolated environment for your shell, then:
pip install -r mobile/tool/export-requirements.txt
python mobile/tool/export_pothole.py
python mobile/tool/verify_pothole.py --images backend/uploads
```

The converter refuses incompatible labels and checks TFLite against PyTorch
before copying the model. The verification script checks up to ten existing
images without uploading them. `tool/model-validation.json` contains the result.

Validate from `mobile` with `flutter test --no-pub` and
`flutter build apk --debug --no-pub`. For device acceptance, start monitoring,
grant permissions, check Image Stream: Running and Model Loaded: Yes, observe
colored/confidence boxes and increasing Confirmed, and verify image uploads
create `/events` visible after the website's next poll. Also test
rotation, background/Back, permission denial, offline backend, and a fresh
Camera Ready capture and Gallery upload after monitoring. No physical Android
device was connected during the automated checks.

For an optimized ARM64 device build, run from `mobile`:

```sh
flutter build apk --release --no-pub --target-platform android-arm64
```

The output is `build/app/outputs/flutter-apk/app-release.apk`. This project still
uses its existing debug signing configuration for release builds. Automated
validation passed 136 Flutter tests and Dart analysis; the packaged TFLite model
matched PyTorch on ten local images (maximum absolute difference 0.00165).

Additional monitoring integration checks, from the repository root:

```powershell
.\.model-export\Scripts\python.exe mobile/tool/verify_live_frames.py
.\backend\venv\Scripts\python.exe mobile/tool/verify_monitoring_backend.py
```

These test production Dart conversion of padded, rotated YUV420 planes around
actual TFLite inference, confirmation/duplicate filtering, and the unchanged
FastAPI image-to-event flow in an isolated instance. Reports go to `mobile/build`.
The tested frame returned one pothole at 75.7% confidence, one confirmation and
zero duplicate confirmations; its upload returned HTTP 200 and one pothole event.
This is host-side verification, not a physical camera or Android FPS measurement.

## Backend URL

All backend requests use `ApiConfig.baseUrl` in `lib/config/api_config.dart`.
On the dashboard, open **Backend Settings**, enter the PC's Wi-Fi or hotspot
address (including port `8000`), and tap **Save URL**. The app saves this value
with `shared_preferences`, tests the connection, and refreshes the dashboard.
**Test Connection** checks the entered address without saving it.

A saved address takes precedence over the optional build-time default. To supply
that default, run from the `mobile` directory:

```sh
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000
```

Replace the example IP with the PC's address on the phone's network. If the phone
uses the Windows mobile hotspot, use the hotspot adapter's IPv4 address. The
PC's upstream Wi-Fi address can be on a different subnet. Run `ipconfig` on the PC
to identify the correct adapter. A server bind address is not a client URL.

There is no baked-in device-local or emulator address. Without a saved value or
`API_BASE_URL`, configure the address in Settings. Changes in Settings apply to
existing API services immediately and survive app restarts; they need no rebuild.
The old `URBANEYE_API_BASE_URL` define is no longer used.

Run FastAPI from `backend` with:

```sh
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Open `http://<PC-LAN-IP>:8000/ping` in the phone's browser first. If it cannot
connect, check the Wi-Fi/hotspot connection, Windows firewall access for TCP
8000 on that local network, and router client isolation. CORS does not fix an
unreachable server on a native Android app.

Health checks use `/ping`, falling back to `/openapi.json` only if `/ping` returns
404. Camera and Gallery share `ApiService.uploadDetectionImage`: `POST /detect`,
multipart field `file`, and the existing optional coordinate fields. GPS retains
`POST /location`. Request timeouts, cancellation, and detection result navigation
are unchanged. Android's main manifest grants Internet access and allows local
HTTP via `res/xml/network_security_config.xml`; HTTPS still uses system trust.

Verification commands (from `mobile`):

```sh
flutter test --no-pub
flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://<PC-LAN-IP>:8000
```

Install the rebuilt APK to apply Android networking and native plugin changes.
Then test the connection in Settings, confirm **Backend Online**, select a
Gallery image, grant the existing location permission, and tap **Continue**.
Confirm `POST /detect` returns 200 in the backend log and the result screen opens.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
