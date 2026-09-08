import 'dart:async';
import 'dart:convert';

// Use camera's platform seam without adding a production dependency for tests.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:urbaneye_mobile/screens/camera_screen.dart';
import 'package:urbaneye_mobile/screens/result_screen.dart';
import 'package:urbaneye_mobile/services/detection_result_service.dart';
import 'package:urbaneye_mobile/services/location_service.dart';

final Uint8List _photoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6Q'
  'AAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAALSURBVBhX'
  'Y2AAAgAABQABqtXIUQAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets(
      'successful capture opens its result and preserves the back stack',
      (tester) async {
    var requests = 0;
    final platform = await _openCamera(tester, MockClient((request) async {
      requests += 1;
      expect(request.method, 'POST');
      expect(request.url.path, '/detect');
      return _successResponse([
        {
          'label': 'Pothole',
          'confidence': 0.93,
          'severity': 'Critical',
          'bbox': [0.05, 0.05, 0.95, 0.95],
        },
      ]);
    }));

    final capturePosition = _position(12.345678, 76.123456);
    LocationStore.latestPosition = capturePosition;
    await _capture(tester);
    LocationStore.latestPosition = _position(20, 30);
    final beforeResponse = DateTime.now();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(requests, 1);
    final screen = tester.widget<ResultScreen>(find.byType(ResultScreen));
    expect(screen.photoBytes, orderedEquals(_photoBytes));
    expect(screen.position, same(capturePosition));
    expect(screen.result.detections.single.label, 'Pothole');
    expect(screen.result.timestamp.isBefore(beforeResponse), isFalse);
    expect(screen.result.timestamp.isAfter(DateTime.now()), isFalse);
    expect(find.text('Reported to Dashboard'), findsOneWidget);
    expect(
      find.text('Latitude: 12.345678\nLongitude: 76.123456'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultScreen), findsNothing);
    expect(find.byTooltip('Capture'), findsOneWidget);
    expect(platform.resumeCount, 1);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open camera'), findsOneWidget);
    expect(find.byType(CameraScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a successful empty response opens the no-hazards result',
      (tester) async {
    await _openCamera(tester, MockClient((_) async => _successResponse([])));
    await _capture(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(ResultScreen), findsOneWidget);
    expect(find.text('Reported to Dashboard'), findsOneWidget);
    expect(find.text('GPS coordinates unavailable'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('No hazards detected'), 200);
    expect(find.text('No hazards detected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a failed response retains the photo and allows a successful retry',
      (tester) async {
    var requests = 0;
    await _openCamera(tester, MockClient((_) async {
      requests += 1;
      return requests == 1
          ? http.Response('{"detail":"Unavailable"}', 503)
          : _successResponse([]);
    }));
    await _capture(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(ResultScreen), findsNothing);
    expect(find.text('Review your photo'), findsOneWidget);
    expect(find.text('Upload Failed'), findsOneWidget);
    final preview = tester.widget<Image>(find.byType(Image));
    expect((preview.image as MemoryImage).bytes, orderedEquals(_photoBytes));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(find.byType(ResultScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<_FakeCameraPlatform> _openCamera(
  WidgetTester tester,
  http.Client client,
) async {
  final previousPlatform = CameraPlatform.instance;
  final previousPosition = LocationStore.latestPosition;
  final platform = _FakeCameraPlatform();
  final service = DetectionResultService(client: client);
  CameraPlatform.instance = platform;
  LocationStore.latestPosition = null;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 932);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    service.dispose();
    client.close();
    CameraPlatform.instance = previousPlatform;
    LocationStore.latestPosition = previousPosition;
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => CameraScreen(apiService: service),
            )),
            child: const Text('Open camera'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open camera'));
  await tester.pumpAndSettle();
  expect(find.byTooltip('Capture'), findsOneWidget);
  return platform;
}

Future<void> _capture(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Capture'));
  await tester.pumpAndSettle();
  expect(find.text('Review your photo'), findsOneWidget);
}

http.Response _successResponse(List<Map<String, Object>> detections) =>
    http.Response(
        jsonEncode({'status': 'success', 'detections': detections}), 200);

Position _position(double latitude, double longitude) => Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime(2026, 9, 5),
      accuracy: 4,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class _FakeCameraPlatform extends CameraPlatform {
  final _errors = StreamController<CameraErrorEvent>.broadcast();
  int resumeCount = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
        CameraDescription(
          name: 'Test camera',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 0,
        ),
      ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? settings,
  ) async =>
      1;

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(const CameraInitializedEvent(
        1,
        640,
        480,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ));

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _errors.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      Stream.value(
          const DeviceOrientationChangedEvent(DeviceOrientation.portraitUp));

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Future<XFile> takePicture(int cameraId) async =>
      XFile.fromData(_photoBytes, mimeType: 'image/png', name: 'capture.png');

  @override
  Future<void> pausePreview(int cameraId) async {}

  @override
  Future<void> resumePreview(int cameraId) async {
    resumeCount += 1;
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.black);

  @override
  Future<void> dispose(int cameraId) async {
    // Resolve the controller's pending first-error listener before closing.
    _errors.add(CameraErrorEvent(cameraId, 'Disposed'));
    await _errors.close();
  }
}
