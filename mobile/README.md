# urbaneye_mobile

A new Flutter project.

## AI dashcam

**Start Monitoring** opens the rear camera immediately, starts an image stream,
then switches to `startVideoRecording(onAvailable: ...)` for simultaneous video
and inference. Flutter rejects `startImageStream` during a recording; the shared
recording callback keeps inference running throughout the recording. Android
uses `camera_android` (Camera2), because the CameraX implementation does not
support the combined recording callback. Camera Ready and Gallery still use
their existing `/detect` flow; the backend and checkpoint are unchanged.

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

An incident requires confidence ≥50%, NMS IoU <0.45, and three consecutive
observations matched at IoU >0.30. Each track reports once and survives up to
1.5 seconds of occlusion. Uploads require a capture-time GPS fix no older than
10 seconds and accuracy ≤50 meters. Missing/denied GPS pauses confirmation and
uploads while local preview, inference, and recording continue. Only confirmed
incident JSON goes to the existing **POST `/events`** endpoint, with coordinates,
confidence, and capture timestamp; camera frames and video are not uploaded.
Uploads are serialized with a 30-event bound and cancellation on stop. Failed
events remain in the local log; automatic retries are avoided because the
existing endpoint has no idempotency key.

Video is silent and saved on stop to the app's Documents `dashcam/` directory,
alongside a `.jsonl` GPS/confirmed-detection/upload-status log. The saved video
path is shown on screen. Raw video does not have boxes burned in. Back navigation
waits for video finalization; backgrounding stops and saves the session. Resume
requires another Start. Sessions have no automatic retention/deletion policy.
Android API 26 or later is required.

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
grant permissions, check REC and measured FPS, observe colored/confidence boxes,
verify confirmed `/events` with GPS, then stop and play the saved MP4. Also test
rotation, background/Back, permission denial, offline backend, and a fresh
Camera Ready capture and Gallery upload after monitoring. No physical Android
device was connected during the automated checks.

For an optimized ARM64 device build, run from `mobile`:

```sh
flutter build apk --release --no-pub --target-platform android-arm64
```

The output is `build/app/outputs/flutter-apk/app-release.apk`. This project still
uses its existing debug signing configuration for release builds. Automated
validation passed 124 Flutter tests and Dart analysis; the packaged TFLite model
matched PyTorch on ten local images (maximum absolute difference 0.00165).

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
