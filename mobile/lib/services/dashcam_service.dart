import 'dart:async';
import 'dart:collection';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/live_detection.dart';
import 'location_service.dart';
import 'monitoring_upload_service.dart';
import 'yolo_worker.dart';

class DashcamSnapshot {
  const DashcamSnapshot(
      {this.detections = const [],
      this.fps = 0,
      this.cameraFps = 0,
      this.modelLoaded = false,
      this.streaming = false,
      this.inferenceMs = 0,
      this.maxConfidence = 0,
      this.totalFrames = 0,
      this.confirmed = 0,
      this.uploaded = 0,
      this.pending = 0,
      this.backendIncidents = 0,
      this.gps = 'Waiting for GPS',
      this.frameFormat = 'No camera frames yet',
      this.notice,
      this.preview});
  final List<LiveDetection> detections;
  final double fps, cameraFps, inferenceMs, maxConfidence;
  final bool modelLoaded, streaming;
  final int confirmed, uploaded, pending, totalFrames, backendIncidents;
  final String gps, frameFormat;
  final String? notice;
  final Uint8List? preview;
}

abstract class MonitoringGps {
  Future<Stream<Position>> open();
  Future<Position?> lastKnown();
}

class DeviceMonitoringGps implements MonitoringGps {
  @override
  Future<Stream<Position>> open() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('GPS disabled');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw StateError('GPS permission required for uploads');
    }
    return Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
    ));
  }

  @override
  Future<Position?> lastKnown() => Geolocator.getLastKnownPosition();
}

/// Live detection only: no recording, directories, journals or device file IO.
class DashcamService {
  DashcamService(
      {YoloWorker? worker,
      MonitoringGps? gps,
      MonitoringUploadService Function()? uploaderFactory,
      DateTime Function()? now})
      : _worker = worker ?? YoloWorker(),
        _gpsSource = gps ?? DeviceMonitoringGps(),
        _uploaderFactory = uploaderFactory ?? (() => MonitoringUploadService()),
        _now = now ?? DateTime.now;

  final snapshot = ValueNotifier(const DashcamSnapshot());
  final YoloWorker _worker;
  final MonitoringGps _gpsSource;
  final MonitoringUploadService Function() _uploaderFactory;
  final DateTime Function() _now;
  final _filter = LiveConfirmationFilter();
  final _queue = Queue<_Incident>();
  MonitoringUploadService? _uploader;
  StreamSubscription<Position>? _gpsSubscription;
  Timer? _metricsTimer;
  final _clock = Stopwatch();
  Completer<void>? _abort;
  int _generation = 0, _confirmed = 0, _uploaded = 0, _backendIncidents = 0;
  int _cameraFrames = 0, _aiFrames = 0, _totalFrames = 0;
  double _cameraFps = 0, _aiFps = 0, _inferenceMs = 0, _maxConfidence = 0;
  bool _modelLoaded = false, _streaming = false, _disposed = false;
  int? _uploadGeneration;
  Position? _position;
  DateTime? _lastFrame;
  String _gps = 'Waiting for GPS', _frameFormat = 'No camera frames yet';
  String? _notice;
  Uint8List? _preview;
  List<LiveDetection> _detections = [];

  Future<void> initialize() async {
    final generation = ++_generation;
    _filter.clear();
    _queue.clear();
    _position = null;
    _notice = null;
    _confirmed = _uploaded = _backendIncidents = 0;
    _cameraFrames = _aiFrames = _totalFrames = 0;
    _cameraFps = _aiFps = _inferenceMs = _maxConfidence = 0;
    _modelLoaded = _streaming = false;
    _lastFrame = null;
    _detections = [];
    _preview = null;
    _gps = 'Waiting for GPS';
    _frameFormat = 'No camera frames yet';
    _abort = Completer<void>();
    _uploader = _uploaderFactory();
    _publish();
    try {
      await _worker.initialize();
      if (generation != _generation) return;
      _modelLoaded = true;
      _publish();
    } catch (error) {
      _notice = 'Model load failed: $error';
      _publish();
      rethrow;
    }
    try {
      final positions = await _gpsSource.open();
      if (generation != _generation) return;
      _gpsSubscription = positions.listen((p) => _acceptPosition(p, generation),
          onError: (Object error) {
        if (generation != _generation) return;
        _gps = 'GPS unavailable: $error';
        _publish();
      });
      unawaited(_gpsSource.lastKnown().then((p) {
        if (p != null &&
            (_position == null || p.timestamp.isAfter(_position!.timestamp))) {
          _acceptPosition(p, generation);
        }
      }).catchError((Object _) {}));
    } catch (error) {
      _gps = '$error · detection continues';
    }
    if (generation != _generation) return;
    _clock
      ..reset()
      ..start();
    _metricsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed = _clock.elapsedMicroseconds / 1000000;
      _cameraFps = _cameraFrames / elapsed;
      _aiFps = _aiFrames / elapsed;
      _cameraFrames = _aiFrames = 0;
      _clock.reset();
      if (_lastFrame == null ||
          _now().difference(_lastFrame!) > const Duration(seconds: 2)) {
        _detections = [];
        _notice = 'Image stream has not delivered frames in the last 2 seconds';
      }
      _expirePending();
      _publish();
    });
    _publish();
  }

  void setStreaming(bool value) {
    _streaming = value;
    _publish();
  }

  /// Called for EVERY stream callback, before throttling or busy-frame drops.
  void cameraFrame(CameraImage image) {
    _cameraFrames++;
    _totalFrames++;
    _lastFrame = _now();
    _frameFormat = '${image.format.group.name} ${image.width}×${image.height}, '
        '${image.planes.length} planes';
    if (_notice?.startsWith('Image stream') == true) _notice = null;
  }

  Future<void> process(CameraImage image, int rotation) async {
    final generation = _generation;
    final capturedAt = _now().toUtc();
    final position = _validFix(_position, capturedAt) ? _position : null;
    InferenceResult result;
    try {
      result = await _worker.detect(image, rotation);
    } catch (error) {
      if (generation == _generation) {
        _notice = 'Inference failed: $error';
        _publish();
      }
      rethrow;
    }
    if (generation != _generation || _disposed) return;
    _detections = result.detections;
    _inferenceMs = result.inferenceMs;
    _maxConfidence = result.maxConfidence;
    _preview = result.preview ?? _preview;
    _aiFrames++;
    final confirmed = _filter.update(result.detections, capturedAt);
    _confirmed +=
        confirmed.length; // Never gated on GPS, upload or another frame.
    _publish();
    if (confirmed.isEmpty) return;
    if (_queue.length >= 20) {
      _notice = 'Upload queue full; detection counted but image not queued';
      _publish();
      return;
    }
    try {
      final jpeg = await _worker.encodeEvidence();
      if (generation != _generation) return;
      final uploadPosition =
          position ?? (_validFix(_position, capturedAt) ? _position : null);
      _queue.add(_Incident(jpeg, confirmed, capturedAt, uploadPosition));
      _notice = uploadPosition == null
          ? 'Confirmed; waiting for GPS to upload'
          : 'Sending confirmed image';
      _publish();
      unawaited(_drain(generation));
    } catch (error) {
      if (generation != _generation) return;
      _notice = 'Could not encode confirmed image: $error';
      _publish();
    }
  }

  void _acceptPosition(Position position, int generation) {
    if (generation != _generation || !_validFix(position, _now())) return;
    _position = position;
    LocationStore.latestPosition = position;
    _gps = 'GPS ±${position.accuracy.round()} m';
    for (final incident in _queue) {
      // Preserve a capture fix; a newly acquired fix includes its own timestamp.
      if (incident.position == null && _validFix(position, incident.time)) {
        incident.position = position;
      }
    }
    unawaited(_drain(generation));
    _publish();
  }

  bool _validFix(Position? p, DateTime time) =>
      p != null &&
      p.latitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.isFinite &&
      p.longitude.abs() <= 180 &&
      p.accuracy.isFinite &&
      p.accuracy >= 0 &&
      time.difference(p.timestamp).abs() <= const Duration(seconds: 30);

  void _expirePending() {
    final before = _queue.length;
    _queue.removeWhere((i) =>
        i.position == null &&
        _now().difference(i.time) > const Duration(seconds: 30));
    if (_queue.length < before) {
      _notice =
          'GPS unavailable; ${before - _queue.length} image(s) not uploaded';
    }
  }

  Future<void> _drain(int generation) async {
    if (_uploadGeneration == generation || generation != _generation) return;
    _uploadGeneration = generation;
    final uploader = _uploader!;
    final abort = _abort!.future;
    try {
      while (generation == _generation) {
        _expirePending();
        final ready = _queue.where((i) => i.position != null);
        if (ready.isEmpty) return;
        final incident = ready.first;
        _queue.remove(incident);
        final p = incident.position!;
        final result = await uploader.upload(
            image: incident.image,
            detections: incident.detections,
            latitude: p.latitude,
            longitude: p.longitude,
            accuracy: p.accuracy,
            timestamp: incident.time,
            gpsTimestamp: p.timestamp,
            abortTrigger: abort);
        if (generation != _generation) return;
        if (result.success) {
          _uploaded++;
          _backendIncidents += result.incidents;
        }
        _notice = result.message;
        _publish();
        // No blind retries: existing /detect is not idempotent.
      }
    } finally {
      if (_uploadGeneration == generation) _uploadGeneration = null;
    }
  }

  void cancelProcessing() {
    ++_generation;
    _metricsTimer?.cancel();
    if (_abort?.isCompleted == false) _abort!.complete();
    _uploader?.dispose();
    _uploader = null;
    _queue.clear();
  }

  Future<void> stop() async {
    cancelProcessing();
    try {
      await _gpsSubscription?.cancel();
    } finally {
      _gpsSubscription = null;
      await _worker.close();
      _streaming = _modelLoaded = false;
      _cameraFps = _aiFps = 0;
      _detections = [];
      _clock.stop();
      _publish();
    }
  }

  void _publish() {
    if (_disposed) return;
    snapshot.value = DashcamSnapshot(
        detections: _detections,
        fps: _aiFps,
        cameraFps: _cameraFps,
        modelLoaded: _modelLoaded,
        streaming: _streaming,
        inferenceMs: _inferenceMs,
        maxConfidence: _maxConfidence,
        totalFrames: _totalFrames,
        confirmed: _confirmed,
        uploaded: _uploaded,
        pending: _queue.length,
        backendIncidents: _backendIncidents,
        gps: _gps,
        frameFormat: _frameFormat,
        notice: _notice,
        preview: _preview);
  }

  void dispose() {
    _disposed = true;
    _metricsTimer?.cancel();
    snapshot.dispose();
  }
}

class _Incident {
  _Incident(this.image, this.detections, this.time, this.position);
  final Uint8List image;
  final List<LiveDetection> detections;
  final DateTime time;
  Position? position;
}
