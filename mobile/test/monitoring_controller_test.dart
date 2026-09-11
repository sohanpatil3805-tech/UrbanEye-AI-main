import 'dart:async';

import 'package:camera/camera.dart' show CameraImage;

// Exercise the camera plugin's platform seam without a production dependency.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/services/monitoring_controller.dart';
import 'package:urbaneye_mobile/services/dashcam_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CameraPlatform original;
  late _MonitoringCameraPlatform platform;
  late MonitoringController controller;

  setUp(() {
    original = CameraPlatform.instance;
    platform = _MonitoringCameraPlatform();
    CameraPlatform.instance = platform;
    controller = MonitoringController();
  });

  tearDown(() async {
    controller.dispose();
    await controller.stop();
    await platform.close();
    CameraPlatform.instance = original;
  });

  test('starts only on request, prefers rear camera, and releases on stop',
      () async {
    expect(controller.state, MonitoringState.idle);
    expect(controller.cameraController, isNull);
    expect(platform.discoveryCalls, 0);

    final starting = controller.start();
    expect(controller.state, MonitoringState.starting);
    await starting;
    expect(controller.state, MonitoringState.active);
    expect(controller.cameraController!.value.isInitialized, isTrue);
    expect(platform.created, [_backCamera]);
    expect(platform.settings.single!.enableAudio, isFalse);
    expect(platform.streamStarts, 0);
    await controller.start();
    expect(platform.created, hasLength(1));

    final stopping = controller.stop();
    expect(controller.state, MonitoringState.stopping);
    await stopping;
    expect(controller.state, MonitoringState.idle);
    expect(controller.cameraController, isNull);
    expect(platform.disposedIds, [1]);
    await controller.start();
    expect(controller.state, MonitoringState.active);
    expect(platform.created, hasLength(2));
  });

  test('falls back to the available lens and handles missing cameras',
      () async {
    platform.cameras = [];
    await controller.start();
    expect(controller.state, MonitoringState.error);
    expect(controller.errorMessage, contains('No camera'));
    expect(controller.cameraController, isNull);

    platform.cameras = [_frontCamera];
    await controller.start();
    expect(controller.state, MonitoringState.active);
    expect(controller.errorMessage, isNull);
    expect(platform.created, [_frontCamera]);
  });

  for (final code in [
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
  ]) {
    test('$code reports permission guidance and releases the camera', () async {
      platform.initializeError = CameraException(code, 'Not allowed');
      await controller.start();
      expect(controller.state, MonitoringState.error);
      expect(controller.errorMessage, contains('Allow camera access'));
      expect(controller.cameraController, isNull);
      expect(platform.disposedIds, [1]);
      platform.initializeError = null;
      await controller.start();
      expect(controller.state, MonitoringState.active);
    });
  }

  test('initialization failure permits retry', () async {
    platform.initializeError = CameraException('CameraFailed', 'Unavailable');
    await controller.start();
    expect(controller.state, MonitoringState.error);
    expect(controller.errorMessage, contains('Unable to start'));
    expect(platform.disposedIds, [1]);
    platform.initializeError = null;
    await controller.start();
    expect(controller.state, MonitoringState.active);
  });

  test('stop during discovery cancels startup without opening a camera',
      () async {
    final cameras = Completer<List<CameraDescription>>();
    platform.discovery = cameras.future;
    final starting = controller.start();
    await _flush();
    final stopping = controller.stop();
    cameras.complete([_backCamera]);
    await Future.wait([starting, stopping]);
    expect(controller.state, MonitoringState.idle);
    expect(platform.created, isEmpty);
    expect(controller.cameraController, isNull);
  });

  test('rapid stop and start releases the pending camera before reopening',
      () async {
    final initialization = Completer<void>();
    platform.initialization = initialization.future;
    final firstStart = controller.start();
    await _flush();
    expect(platform.created, hasLength(1));
    final stopping = controller.stop();
    final secondStart = controller.start();
    initialization.complete();
    await Future.wait([firstStart, stopping, secondStart]);
    expect(controller.state, MonitoringState.active);
    expect(platform.disposedIds, [1]);
    expect(platform.events, ['create:1', 'dispose:1', 'create:2']);
    expect(controller.cameraController!.cameraId, 2);
  });

  test('dispose during initialization releases resources without late updates',
      () async {
    final initialization = Completer<void>();
    platform.initialization = initialization.future;
    var notifications = 0;
    controller.addListener(() => notifications++);
    final starting = controller.start();
    await _flush();
    expect(notifications, 1);
    controller.dispose();
    initialization.complete();
    await starting;
    await controller.stop();
    expect(notifications, 1);
    expect(controller.cameraController, isNull);
    expect(platform.disposedIds, [1]);
    await controller.start();
    expect(platform.created, hasLength(1));
  });

  test('runtime camera failure stops monitoring and permits retry', () async {
    await controller.start();
    platform.errors[1]!.add(const CameraErrorEvent(1, 'Disconnected'));
    await _flush();
    expect(controller.state, MonitoringState.error);
    expect(controller.errorMessage, contains('camera stopped working'));
    expect(controller.cameraController, isNull);
    expect(platform.disposedIds, [1]);
    await controller.start();
    expect(controller.state, MonitoringState.active);
  });

  test('optional frame handler processes only one frame at a time', () async {
    controller.dispose();
    await controller.stop();
    final processing = Completer<void>();
    var calls = 0;
    controller = MonitoringController(onFrame: (image) async {
      expect(image.width, 1);
      calls++;
      if (calls == 1) await processing.future;
    });
    await controller.start();
    expect(platform.streamStarts, 1);
    platform.frames.add(_frame);
    await _flush();
    platform.frames.add(_frame);
    await _flush();
    expect(calls, 1);
    processing.complete();
    await _flush();
    platform.frames.add(_frame);
    await _flush();
    expect(calls, 2);
    await controller.stop();
    expect(platform.streamStops, 1);
    platform.frames.add(_frame);
    await _flush();
    expect(calls, 2);
  });

  test('a frame failure from an old session cannot stop the new session',
      () async {
    controller.dispose();
    await controller.stop();
    final processing = Completer<void>();
    var calls = 0;
    controller = MonitoringController(onFrame: (_) async {
      calls++;
      if (calls == 1) await processing.future;
    });
    await controller.start();
    platform.frames.add(_frame);
    await _flush();
    await controller.stop();
    await controller.start();
    platform.frames.add(_frame);
    await _flush();
    expect(calls, 1);
    processing.completeError(StateError('Old inference failed'));
    await _flush();
    expect(controller.state, MonitoringState.active);
    expect(controller.errorMessage, isNull);
    platform.frames.add(_frame);
    await _flush();
    expect(calls, 2);
  });

  test('frame processing errors release the camera and surface a message',
      () async {
    controller.dispose();
    await controller.stop();
    controller = MonitoringController(onFrame: (_) async {
      throw StateError('Inference failed');
    });
    await controller.start();
    platform.frames.add(_frame);
    await _flush();
    expect(controller.state, MonitoringState.error);
    expect(
        controller.errorMessage, contains('Unable to process camera images'));
    expect(platform.disposedIds, [1]);
    expect(platform.streamStops, 1);
  });

  test('monitoring keeps image stream running and never starts video',
      () async {
    controller.dispose();
    await controller.stop();
    final dashcam = _FakeDashcamService();
    controller = MonitoringController(dashcam: dashcam);
    await controller.start();
    expect(controller.state, MonitoringState.active);
    expect(platform.streamStarts, 1);
    expect(platform.streamStops, 0);
    expect(platform.videoStarts, 0);
    expect(controller.cameraController!.value.isRecordingVideo, isFalse);
    expect(controller.cameraController!.value.isStreamingImages, isTrue);
    expect(platform.created.single.lensDirection, CameraLensDirection.back);
    await controller.stop();
    expect(platform.videoStops, 0);
    expect(platform.streamStops, 1);
    expect(dashcam.stops, 1);
    expect(platform.events, ['create:1', 'dispose:1']);
    expect(controller.state, MonitoringState.idle);
  });

  test('dashcam processes every third frame and drops work while busy',
      () async {
    controller.dispose();
    await controller.stop();
    final dashcam = _FakeDashcamService();
    controller = MonitoringController(dashcam: dashcam);
    await controller.start();
    platform.frames.add(_frame);
    platform.frames.add(_frame);
    await _flush();
    expect(dashcam.frames, 0);
    final pending = Completer<void>();
    dashcam.pending = pending.future;
    platform.frames.add(_frame);
    await _flush();
    expect(dashcam.frames, 1);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    for (var i = 0; i < 6; i++) {
      platform.frames.add(_frame);
    }
    await _flush();
    expect(dashcam.frames, 1);
    pending.complete();
    await _flush();
    dashcam.pending = null;
    for (var i = 0; i < 3; i++) {
      platform.frames.add(_frame);
    }
    await _flush();
    expect(dashcam.frames, 2);
    await controller.stop();
    platform.frames.add(_frame);
    await _flush();
    expect(dashcam.frames, 2);
  });

  test('model failure is visible and allows retry without recording', () async {
    controller.dispose();
    await controller.stop();
    final dashcam = _FakeDashcamService();
    controller = MonitoringController(dashcam: dashcam);
    dashcam.initializeError = StateError('Model unavailable');
    await controller.start();
    expect(controller.state, MonitoringState.error);
    expect(platform.disposedIds, [1]);
    expect(dashcam.stops, 1);
    expect(controller.errorMessage, contains('Model unavailable'));
    expect(platform.videoStarts, 0);
    dashcam.initializeError = null;
    await controller.start();
    expect(controller.state, MonitoringState.active);
  });

  test('dashcam requires rear lens instead of recording a selfie', () async {
    controller.dispose();
    await controller.stop();
    controller = MonitoringController(dashcam: _FakeDashcamService());
    platform.cameras = [_frontCamera];
    await controller.start();
    expect(controller.state, MonitoringState.error);
    expect(controller.errorMessage, contains('rear camera'));
    expect(platform.created, isEmpty);
  });
}

class _FakeDashcamService extends DashcamService {
  int frames = 0, stops = 0;
  Object? initializeError;
  Future<void>? pending;
  @override
  Future<void> initialize() async {
    if (initializeError != null) throw initializeError!;
  }

  @override
  Future<void> process(CameraImage image, int rotation) async {
    frames++;
    await pending;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

const _frontCamera = CameraDescription(
  name: 'Front camera',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 0,
);
const _backCamera = CameraDescription(
  name: 'Back camera',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 0,
);
final _frame = CameraImageData(
  format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 0),
  planes: [CameraImagePlane(bytes: Uint8List(4), bytesPerRow: 4)],
  height: 1,
  width: 1,
);

class _MonitoringCameraPlatform extends CameraPlatform {
  List<CameraDescription> cameras = [_frontCamera, _backCamera];
  Future<List<CameraDescription>>? discovery;
  Future<void>? initialization;
  CameraException? initializeError;
  int discoveryCalls = 0;
  int streamStarts = 0;
  int streamStops = 0;
  int videoStarts = 0, videoStops = 0;
  PlatformException? videoError;
  void Function(CameraImageData)? videoFrame;
  final created = <CameraDescription>[];
  final settings = <MediaSettings?>[];
  final disposedIds = <int>[];
  final events = <String>[];
  final errors = <int, StreamController<CameraErrorEvent>>{};
  late final frames = StreamController<CameraImageData>.broadcast(
    onListen: () => streamStarts++,
    onCancel: () => streamStops++,
  );

  @override
  Future<List<CameraDescription>> availableCameras() async {
    discoveryCalls++;
    return discovery != null ? await discovery! : cameras;
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? settings,
  ) async {
    created.add(description);
    this.settings.add(settings);
    final id = created.length;
    errors[id] = StreamController<CameraErrorEvent>.broadcast();
    events.add('create:$id');
    return id;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(CameraInitializedEvent(
        cameraId,
        640,
        480,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ));

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      errors[cameraId]!.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      Stream.value(
        const DeviceOrientationChangedEvent(DeviceOrientation.portraitUp),
      );

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initialization;
    if (initializeError != null) throw initializeError!;
  }

  @override
  bool supportsImageStreaming() => true;

  @override
  Future<void> lockCaptureOrientation(
      int cameraId, DeviceOrientation orientation) async {}

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    if (videoError != null) throw videoError!;
    videoStarts++;
    videoFrame = options.streamCallback;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    videoStops++;
    events.add('video-stop');
    return XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'road.mp4');
  }

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) =>
      frames.stream;

  @override
  Future<void> dispose(int cameraId) async {
    disposedIds.add(cameraId);
    events.add('dispose:$cameraId');
    // Resolve camera's first-error subscription before closing its stream.
    errors[cameraId]!.add(CameraErrorEvent(cameraId, 'Disposed'));
    await errors[cameraId]!.close();
  }

  Future<void> close() async {
    await frames.close();
    for (final stream in errors.values) {
      if (!stream.isClosed) await stream.close();
    }
  }
}
