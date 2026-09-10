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
import 'package:image_picker/image_picker.dart';

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
  testWidgets('requests permission and waits for a fresh fix before uploading',
      (tester) async {
    final fix = Completer<Position>();
    final location = _FakeUploadLocationService()
      ..permission = LocationPermission.denied
      ..nextPosition = fix.future;
    final requests = <http.Request>[];
    await _openCamera(tester, MockClient((request) async {
      requests.add(request);
      return _successResponse([]);
    }), locationService: location);
    LocationStore.latestPosition = _position(1, 2);
    await _capture(tester);
    expect(location.positionCalls, 0);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(location.permissionRequests, 1);
    expect(location.positionCalls, 1);
    expect(requests, isEmpty);
    expect(find.text('Getting your location...'), findsOneWidget);

    final position = _position(-12.345678, 76.123456);
    fix.complete(position);
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    final body = latin1.decode(requests.single.bodyBytes);
    expect(body, contains('name="latitude"\r\n\r\n-12.345678'));
    expect(body, contains('name="longitude"\r\n\r\n76.123456'));
    expect(tester.widget<ResultScreen>(find.byType(ResultScreen)).position,
        same(position));
    expect(find.text('Latitude: -12.345678\nLongitude: 76.123456'),
        findsOneWidget);
  });

  for (final scenario in ['disabled', 'denied', 'deniedForever', 'timeout']) {
    testWidgets('$scenario GPS retains the photo and allows retry',
        (tester) async {
      final location = _FakeUploadLocationService();
      switch (scenario) {
        case 'disabled':
          location.enabled = false;
        case 'denied':
          location.permission = LocationPermission.denied;
          location.requestedPermission = LocationPermission.denied;
        case 'deniedForever':
          location.permission = LocationPermission.deniedForever;
        case 'timeout':
          location.failPosition = true;
      }
      var requests = 0;
      await _openCamera(tester, MockClient((_) async {
        requests++;
        return _successResponse([]);
      }), locationService: location);
      LocationStore.latestPosition = _position(1, 2);
      await _capture(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.byType(ResultScreen), findsNothing);
      expect(find.text('Review your photo'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(location.permissionRequests, scenario == 'denied' ? 1 : 0);
      expect(location.positionCalls, scenario == 'timeout' ? 1 : 0);

      location.enabled = true;
      location.permission = LocationPermission.whileInUse;
      location.failPosition = false;
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('leaving during a GPS fix prevents upload', (tester) async {
    final fix = Completer<Position>();
    var requests = 0;
    await _openCamera(tester, MockClient((_) async {
      requests++;
      return _successResponse([]);
    }),
        locationService: _FakeUploadLocationService()
          ..nextPosition = fix.future);
    await _capture(tester);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    fix.complete(_position(3, 4));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('flash toggles off and torch and preserves capture to result',
      (tester) async {
    final platform = await _openCamera(
        tester, MockClient((_) async => _successResponse([])));
    expect(platform.flashModes, [FlashMode.off]);
    expect(find.byIcon(Icons.flash_off_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Turn flash on'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.flash_on_rounded), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.flash_on_rounded))
            .isSelected,
        isTrue);
    await tester.tap(find.byTooltip('Turn flash off'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.flash_off_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('Turn flash on'));
    await tester.pumpAndSettle();

    await _capture(tester);
    expect(platform.flashModes, [
      FlashMode.off,
      FlashMode.torch,
      FlashMode.off,
      FlashMode.torch,
      FlashMode.off,
    ]);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Turn flash on'), findsOneWidget);
    expect(find.byTooltip('Capture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed torch change retains off state and allows capture',
      (tester) async {
    final platform = await _openCamera(
        tester, MockClient((_) async => _successResponse([])));
    platform.rejectTorch = true;
    await tester.tap(find.byTooltip('Turn flash on'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to change flash on this camera.'), findsOneWidget);
    expect(find.byIcon(Icons.flash_off_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await _capture(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('flash is disabled when there is no camera', (tester) async {
    await _openCamera(tester, MockClient((_) async => _successResponse([])),
        hasCamera: false);
    final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.flash_off_rounded));
    expect(button.onPressed, isNull);
    expect(button.isSelected, isFalse);
    expect(find.byTooltip('Flash unavailable'), findsOneWidget);
  });

  testWidgets('gallery image uploads to detect and opens the existing result',
      (tester) async {
    var requests = 0;
    late http.Request uploadRequest;
    final picker = _FakeImagePicker(() async => XFile.fromData(
          _photoBytes,
          name: 'road.png',
          path: 'road.png',
          mimeType: 'image/png',
        ));
    await _openCamera(tester, MockClient((request) async {
      requests += 1;
      uploadRequest = request;
      return _successResponse([]);
    }), imagePicker: picker);
    LocationStore.latestPosition = _position(20, 30);

    await tester.tap(find.byTooltip('Gallery'));
    await tester.pumpAndSettle();
    expect(picker.source, ImageSource.gallery);
    expect(find.text('Review your photo'), findsOneWidget);
    expect(requests, 0);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(uploadRequest.method, 'POST');
    expect(uploadRequest.url.path, '/detect');
    expect(uploadRequest.headers['content-type'],
        startsWith('multipart/form-data'));
    expect(latin1.decode(uploadRequest.bodyBytes),
        contains('filename="road.png"'));
    expect(latin1.decode(uploadRequest.bodyBytes),
        contains(latin1.decode(_photoBytes)));
    final screen = tester.widget<ResultScreen>(find.byType(ResultScreen));
    expect(screen.photoBytes, orderedEquals(_photoBytes));
    expect(screen.position?.latitude, 12.345678);
    expect(screen.position?.longitude, 76.123456);
    expect(latin1.decode(uploadRequest.bodyBytes),
        contains('name="latitude"\r\n\r\n12.345678'));
    expect(latin1.decode(uploadRequest.bodyBytes),
        contains('name="longitude"\r\n\r\n76.123456'));
    expect(requests, 1);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Capture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling gallery restores the camera without uploading',
      (tester) async {
    var requests = 0;
    final selection = Completer<XFile?>();
    await _openCamera(tester, MockClient((_) async {
      requests += 1;
      return _successResponse([]);
    }), imagePicker: _FakeImagePicker(() => selection.future));

    await tester.tap(find.byTooltip('Gallery'));
    await tester.pump();
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.photo_library_outlined))
            .onPressed,
        isNull);
    selection.complete(null);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Capture'), findsOneWidget);
    expect(find.text('Review your photo'), findsNothing);
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'gallery keeps loading beyond 15 seconds until inference finishes',
      (tester) async {
    final response = Completer<http.Response>();
    var requests = 0;
    await _openCamera(tester, MockClient((request) async {
      requests++;
      expect(request.url.path, '/detect');
      expect(
          request.headers['content-type'], startsWith('multipart/form-data'));
      expect(latin1.decode(request.bodyBytes),
          contains('name="file"; filename="road.png"'));
      return response.future;
    }),
        imagePicker: _FakeImagePicker(() async =>
            XFile.fromData(_photoBytes, name: 'road.png', path: 'road.png')),
        hasCamera: false);
    await tester.tap(find.byTooltip('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));

    expect(requests, 1);
    expect(find.text('Uploading image...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(ResultScreen), findsNothing);

    response.complete(_successResponse([]));
    await tester.pumpAndSettle();
    expect(find.byType(ResultScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery errors allow another selection', (tester) async {
    final picker = _FakeImagePicker(() async {
      throw PlatformException(code: 'photo_access_denied');
    });
    await _openCamera(tester, MockClient((_) async => _successResponse([])),
        imagePicker: picker);
    await tester.tap(find.byTooltip('Gallery'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to open gallery image. Please try again.'),
        findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.photo_library_outlined))
            .onPressed,
        isNotNull);
    expect(find.byTooltip('Capture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery works without a camera and retains failed uploads',
      (tester) async {
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    var requests = 0;
    await _openCamera(tester, MockClient((_) async {
      requests += 1;
      return requests == 1
          ? http.Response('{"detail":"Road-damage model is unavailable."}', 503)
          : _successResponse([]);
    }),
        imagePicker: _FakeImagePicker(
            () async => XFile.fromData(_photoBytes, name: 'road.png')),
        hasCamera: false);
    await tester.tap(find.byTooltip('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    debugPrint = previousDebugPrint;
    expect(
        find.text(
            'Unable to upload your image. Please check your connection and try again.'),
        findsOneWidget);
    expect(logs, contains(contains('failed (503)')));
    expect(logs, contains(contains('Road-damage model is unavailable.')));
    expect(
        find.textContaining('Road-damage model is unavailable.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Review your photo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(ResultScreen), findsOneWidget);
    expect(requests, 2);
    expect(tester.takeException(), isNull);
  });

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
    expect(screen.position?.latitude, 12.345678);
    expect(screen.position?.longitude, 76.123456);
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
    expect(
        find.text('Latitude: 12.345678\nLongitude: 76.123456'), findsOneWidget);
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
    expect(
        find.text(
            'Unable to upload your image. Please check your connection and try again.'),
        findsOneWidget);
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
  http.Client client, {
  ImagePicker? imagePicker,
  LocationService? locationService,
  bool hasCamera = true,
}) async {
  final previousPlatform = CameraPlatform.instance;
  final previousPosition = LocationStore.latestPosition;
  final platform = _FakeCameraPlatform(hasCamera: hasCamera);
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
              builder: (_) => CameraScreen(
                apiService: service,
                imagePicker: imagePicker,
                locationService:
                    locationService ?? _FakeUploadLocationService(),
              ),
            )),
            child: const Text('Open camera'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open camera'));
  await tester.pumpAndSettle();
  expect(find.byTooltip(hasCamera ? 'Capture' : 'Camera unavailable'),
      findsOneWidget);
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
  _FakeCameraPlatform({this.hasCamera = true});

  final bool hasCamera;
  var _errors = StreamController<CameraErrorEvent>.broadcast();
  int resumeCount = 0;
  final flashModes = <FlashMode>[];
  bool rejectTorch = false;

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    if (rejectTorch && mode == FlashMode.torch) {
      throw CameraException('setFlashModeFailed', 'Torch is unavailable');
    }
    flashModes.add(mode);
  }

  @override
  Future<List<CameraDescription>> availableCameras() async => !hasCamera
      ? []
      : const [
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
  ) async {
    if (_errors.isClosed) {
      _errors = StreamController<CameraErrorEvent>.broadcast();
    }
    return 1;
  }

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

class _FakeUploadLocationService implements LocationService {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  Future<Position>? nextPosition;
  bool failPosition = false;
  int permissionRequests = 0;
  int positionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return permission = requestedPermission;
  }

  @override
  Future<Position> getCurrentPosition() async {
    positionCalls++;
    if (failPosition) throw TimeoutException('No GPS fix');
    return await nextPosition ?? _position(12.345678, 76.123456);
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker(this.pick);

  final Future<XFile?> Function() pick;
  ImageSource? source;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) {
    this.source = source;
    return pick();
  }
}
