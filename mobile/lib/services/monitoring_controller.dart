import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

enum MonitoringState { idle, starting, active, stopping, error }

/// Owns a monitoring camera independently of the manual capture flow.
///
/// Supplying [onFrame] opts into image streaming for a future AI integration.
/// Frames are dropped while its previous callback is still running, including
/// across restarts. Without a callback, only the live preview is started.
class MonitoringController extends ChangeNotifier {
  MonitoringController({this.onFrame});

  final Future<void> Function(CameraImage image)? onFrame;

  MonitoringState _state = MonitoringState.idle;
  CameraController? _cameraController;
  String? _errorMessage;
  Future<void> _pending = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  bool _processingFrame = false;

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
      final camera = CameraController(
        cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        ),
        ResolutionPreset.medium,
        enableAudio: false,
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
      if (onFrame != null) {
        if (!camera.supportsImageStreaming()) {
          throw CameraException(
              'StreamingUnsupported', 'Streaming unavailable');
        }
        await camera.startImageStream(
          (image) => unawaited(_processFrame(image, generation)),
        );
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
    if (!_isCurrent(generation) ||
        _state != MonitoringState.active ||
        _processingFrame) {
      return;
    }
    _processingFrame = true;
    try {
      await onFrame!(image);
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
    unawaited(_enqueue(() async {
      await _releaseCamera();
    }));
    _setState(MonitoringState.error, message);
  }

  Future<bool> _releaseCamera() async {
    final camera = _cameraController;
    _cameraController = null;
    if (camera == null) return true;
    camera.removeListener(_handleCameraError);
    if (camera.value.isStreamingImages) {
      try {
        await camera.stopImageStream();
      } catch (_) {
        // Still release the native camera if stopping its stream fails.
      }
    }
    try {
      await camera.dispose();
      return true;
    } catch (_) {
      return false;
    }
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
    }
    return 'Unable to start the camera. Please try again.';
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    unawaited(_enqueue(() async {
      await _releaseCamera();
    }));
    super.dispose();
  }
}
