# urbaneye_mobile

A new Flutter project.

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
