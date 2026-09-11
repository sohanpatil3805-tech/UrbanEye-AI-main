import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dashcam_service.dart';

enum MonitoringState { idle, starting, active, stopping, error }

/// Owns a monitoring camera independently of the manual capture flow.
///
/// [dashcam] enables local inference and recording. [onFrame] is also available
/// for isolated camera tests and custom stream consumers.
class MonitoringController extends ChangeNotifier {
  MonitoringController({this.onFrame, this.dashcam});

  final Future<void> Function(CameraImage image)? onFrame;
  final DashcamService? dashcam;

  MonitoringState _state = MonitoringState.idle;
  CameraController? _cameraController;
  String? _errorMessage;
  Future<void> _pending = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  bool _processingFrame = false;
  int _frameCount = 0;
  final _frameClock = Stopwatch();
  int _lastFrameMs = -100;

  MonitoringState get state => _state;
  CameraController? get cameraController => _cameraController;
  String? get errorMessage => _errorMessage;

  Future<void> start() {
    if (_disposed ||
        _state == MonitoringState.starting ||
        _state == MonitoringState.active) {
      return _pending;
    }
    final generation = ++_generation;
    final operation = _enqueue(() => _startCamera(generation));
    _setState(MonitoringState.starting);
    return operation;
  }

  Future<void> stop() {
    if (_disposed) return _pending;
    dashcam?.cancelProcessing();
    final generation = ++_generation;
    final operation = _enqueue(() async {
      final released = await _releaseCamera();
      if (_isCurrent(generation)) {
        _setState(
          released ? MonitoringState.idle : MonitoringState.error,
          released ? null : 'Unable to stop the camera. Please try again.',
        );
      }
    });
    _setState(MonitoringState.stopping);
    return operation;
  }

  Future<void> _startCamera(int generation) async {
    if (!_isCurrent(generation)) return;
    try {
      final cameras = await availableCameras().timeout(
        const Duration(seconds: 10),
      );
      if (!_isCurrent(generation)) return;
      if (cameras.isEmpty) {
        _setState(
            MonitoringState.error, 'No camera is available on this device.');
        return;
      }
      if (dashcam != null &&
          !cameras.any((c) => c.lensDirection == CameraLensDirection.back)) {
        throw CameraException('RearCameraUnavailable', 'Rear camera required');
      }
      final camera = CameraController(
        cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        ),
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      _cameraController = camera;
      await camera.initialize();
      if (!_isCurrent(generation)) {
        await _releaseCamera();
        return;
      }
      if (camera.value.hasError) {
        throw CameraException('CameraError', camera.value.errorDescription);
      }
      camera.addListener(_handleCameraError);
      if (dashcam != null) {
        await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
        await dashcam!.initialize();
        if (!_isCurrent(generation)) {
          await _releaseCamera();
          return;
        }
      }
      _frameCount = 0;
      _lastFrameMs = -100;
      _frameClock
        ..reset()
        ..start();
      if (onFrame != null || dashcam != null) {
        if (!camera.supportsImageStreaming()) {
          throw CameraException(
              'StreamingUnsupported', 'Streaming unavailable');
        }
        await camera.startImageStream(
          (image) => unawaited(_processFrame(image, generation)),
        );
        if (dashcam != null) {
          // CameraController rejects startImageStream during recording. Move
          // from the initial stream to Camera2's combined recording callback.
          await camera.stopImageStream();
          await camera.startVideoRecording(
            onAvailable: (image) => unawaited(_processFrame(image, generation)),
            enablePersistentRecording: false,
          );
        }
      }
      if (!_isCurrent(generation)) {
        await _releaseCamera();
        return;
      }
      _setState(MonitoringState.active);
    } catch (error) {
      await _releaseCamera();
      if (_isCurrent(generation)) {
        _setState(MonitoringState.error, _cameraErrorMessage(error));
      }
    }
  }

  Future<void> _processFrame(CameraImage image, int generation) async {
    if (!_isCurrent(generation) || _state != MonitoringState.active) {
      return;
    }
    if (dashcam != null) {
      // At 30 camera FPS every third frame targets 10 inference FPS. The time
      // gate caps faster cameras at 15 FPS; busy frames are never queued.
      if (++_frameCount % 3 != 0 ||
          _frameClock.elapsedMilliseconds - _lastFrameMs < 66) {
        return;
      }
    }
    if (_processingFrame) return;
    _lastFrameMs = _frameClock.elapsedMilliseconds;
    _processingFrame = true;
    try {
      if (dashcam != null) {
        final camera = _cameraController!;
        final orientation = camera.value.recordingOrientation ??
            camera.value.lockedCaptureOrientation ??
            camera.value.deviceOrientation;
        final degrees = switch (orientation) {
          DeviceOrientation.portraitUp => 0,
          DeviceOrientation.landscapeLeft => 90,
          DeviceOrientation.portraitDown => 180,
          DeviceOrientation.landscapeRight => 270,
        };
        final rotation = defaultTargetPlatform == TargetPlatform.iOS
            ? 0
            : (camera.description.sensorOrientation - degrees + 360) % 360;
        await dashcam!.process(image, rotation);
      } else {
        await onFrame!(image);
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        _fail(
            'Unable to process camera images. Please start monitoring again.');
      }
    } finally {
      _processingFrame = false;
    }
  }

  void _handleCameraError() {
    if (_disposed ||
        _state == MonitoringState.stopping ||
        _state == MonitoringState.error ||
        _cameraController?.value.hasError != true) {
      return;
    }
    _fail('The camera stopped working. Please start monitoring again.');
  }

  void _fail(String message) {
    ++_generation;
    dashcam?.cancelProcessing();
    unawaited(_enqueue(() async {
      await _releaseCamera();
    }));
    _setState(MonitoringState.error, message);
  }

  Future<bool> _releaseCamera() async {
    final camera = _cameraController;
    _cameraController = null;
    if (camera == null) {
      await dashcam?.stop();
      return true;
    }
    camera.removeListener(_handleCameraError);
    var released = true;
    if (camera.value.isRecordingVideo) {
      try {
        final recording = await camera.stopVideoRecording();
        await dashcam?.saveRecording(recording);
      } catch (_) {
        released = false;
      }
    }
    if (camera.value.isStreamingImages) {
      try {
        await camera.stopImageStream();
      } catch (_) {
        // Still release the native camera if stopping its stream fails.
      }
    }
    try {
      await camera.dispose();
    } catch (_) {
      released = false;
    }
    await dashcam?.stop();
    _frameClock.stop();
    return released;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _pending = _pending.then((_) => operation());
    return _pending;
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setState(MonitoringState state, [String? error]) {
    if (_disposed) return;
    _state = state;
    _errorMessage = error;
    notifyListeners();
  }

  String _cameraErrorMessage(Object error) {
    if (error is CameraException) {
      if (error.code == 'CameraAccessDenied' ||
          error.code == 'CameraAccessDeniedWithoutPrompt' ||
          error.code == 'CameraAccessRestricted') {
        return 'Camera access is required for monitoring. '
            'Allow camera access in Settings and try again.';
      }
      if (error.code == 'StreamingUnsupported') {
        return 'Camera image streaming is unavailable on this device.';
      }
      if (error.code == 'RearCameraUnavailable') {
        return 'Monitoring requires a rear camera.';
      }
    }
    if (dashcam != null) {
      return 'Unable to start the dashcam. Check the local model and camera '
          'recording support. $error';
    }
    return 'Unable to start the camera. Please try again.';
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    dashcam?.cancelProcessing();
    unawaited(_enqueue(() async {
      await _releaseCamera();
      dashcam?.dispose();
    }));
    super.dispose();
  }
}
