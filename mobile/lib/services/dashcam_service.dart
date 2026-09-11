import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../models/live_detection.dart';
import 'api_service.dart';
import 'location_service.dart';
import 'yolo_worker.dart';

class DashcamSnapshot {
  const DashcamSnapshot(
      {this.detections = const [],
      this.fps = 0,
      this.confirmed = 0,
      this.uploaded = 0,
      this.gps = 'Waiting for GPS',
      this.notice,
      this.recordingPath});
  final List<LiveDetection> detections;
  final double fps;
  final int confirmed, uploaded;
  final String gps;
  final String? notice, recordingPath;
}

/// Session-scoped GPS, local inference, confirmation and bounded event uploads.
class DashcamService {
  final snapshot = ValueNotifier(const DashcamSnapshot());
  final _worker = YoloWorker();
  final _tracker = DetectionTracker();
  final _queue = Queue<_Incident>();
  ApiService? _api;
  StreamSubscription<Position>? _gpsSubscription;
  Position? _position;
  IOSink? _journal;
  String? _stem;
  String? _notice;
  String _gps = 'Waiting for GPS';
  int _generation = 0, _confirmed = 0, _uploaded = 0, _frames = 0;
  bool _uploading = false;
  Completer<void>? _abort;
  final _fpsClock = Stopwatch();
  double _fps = 0;
  List<LiveDetection> _detections = [];
  String? _recordingPath;
  bool _disposed = false;

  Future<void> initialize() async {
    final generation = ++_generation;
    _tracker.clear();
    _queue.clear();
    _position = null;
    _notice = null;
    _recordingPath = null;
    _confirmed = _uploaded = _frames = 0;
    _fps = 0;
    _detections = [];
    _gps = 'Waiting for GPS';
    _abort = Completer<void>();
    _api = ApiService();
    final directory = await getApplicationDocumentsDirectory();
    final recordings =
        await Directory('${directory.path}/dashcam').create(recursive: true);
    _stem =
        '${recordings.path}/${DateTime.now().toUtc().microsecondsSinceEpoch}';
    _journal = File('$_stem.jsonl').openWrite();
    unawaited(_journal!.done.catchError((Object error) {
      _notice = 'Unable to save GPS log: $error';
      _publish();
    }));
    _log({
      'type': 'session',
      'started_at': DateTime.now().toUtc().toIso8601String()
    });
    await _worker.initialize();
    await _startGps(generation);
    _fpsClock
      ..reset()
      ..start();
    _publish();
  }

  Future<void> _startGps(int generation) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _gps = 'GPS disabled · uploads paused';
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (generation != _generation) return;
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        _gps = 'GPS permission needed · uploads paused';
        return;
      }
      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
          intervalDuration: const Duration(seconds: 1),
        ),
      ).listen((position) {
        if (generation != _generation) return;
        _position = position;
        LocationStore.latestPosition = position;
        _gps = 'GPS ±${position.accuracy.round()} m';
        _log({
          'type': 'gps',
          ..._coordinates(position),
          'timestamp': position.timestamp.toUtc().toIso8601String()
        });
        _publish();
      }, onError: (Object _) {
        _position = null;
        _gps = 'GPS unavailable · uploads paused';
        _publish();
      });
    } catch (_) {
      _gps = 'GPS unavailable · uploads paused';
    }
  }

  Future<void> process(CameraImage image, int rotation) async {
    final generation = _generation;
    final capturedAt = DateTime.now().toUtc();
    final position = _position;
    final detections = await _worker.detect(image, rotation);
    if (generation != _generation || _disposed) return;
    _detections = detections;
    _frames++;
    if (_fpsClock.elapsedMilliseconds >= 1000) {
      _fps = _frames * 1000 / _fpsClock.elapsedMilliseconds;
      _frames = 0;
      _fpsClock.reset();
    }
    // Do not confirm until we can attach a recent, useful fix at capture time.
    final hasFix = position != null &&
        position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        position.accuracy <= 50 &&
        position.latitude.isFinite &&
        position.latitude.abs() <= 90 &&
        position.longitude.isFinite &&
        position.longitude.abs() <= 180 &&
        capturedAt.difference(position.timestamp).abs() <=
            const Duration(seconds: 10);
    if (hasFix) {
      for (final detection in _tracker.update(detections, capturedAt)) {
        _confirmed++;
        final incident = _Incident(detection, position, capturedAt);
        _log({
          'type': 'confirmed',
          'box': detection.box,
          'confidence': detection.confidence,
          'severity': detection.severity.name,
          'timestamp': capturedAt.toIso8601String(),
          ..._coordinates(position)
        });
        if (_queue.length < 30) {
          _queue.add(incident);
        } else {
          _notice = 'Upload queue full · detections saved locally';
        }
      }
    } else {
      _tracker.clear();
      if (position != null) _gps = 'Waiting for accurate GPS · uploads paused';
    }
    unawaited(_drain(generation));
    _publish();
  }

  Future<void> _drain(int generation) async {
    if (_uploading || _queue.isEmpty) return;
    _uploading = true;
    final api = _api!;
    final abort = _abort!.future;
    try {
      while (generation == _generation && _queue.isNotEmpty) {
        final incident = _queue.removeFirst();
        final success = await api.uploadConfirmedEvent(
          confidence: incident.detection.confidence,
          latitude: incident.position.latitude,
          longitude: incident.position.longitude,
          timestamp: incident.time,
          abortTrigger: abort,
        );
        if (generation != _generation) return;
        if (success) {
          _uploaded++;
        } else {
          // /events has no idempotency key: automatic retries could duplicate
          // incidents after a lost response. Retain the local journal instead.
          _notice = 'Upload failed · detection saved locally';
        }
        _log({
          'type': 'upload',
          'timestamp': incident.time.toIso8601String(),
          'success': success
        });
        _publish();
      }
    } finally {
      _uploading = false;
    }
  }

  Future<void> saveRecording(XFile file) async {
    final destination = '$_stem.mp4';
    try {
      await file.saveTo(destination);
      _recordingPath = destination;
      // Delete only the exact temporary recording returned by the plugin.
      if (file.path != destination) await File(file.path).delete();
    } catch (_) {
      _recordingPath = file.path;
      _notice =
          'Recording kept at ${file.path}; could not move it to Documents';
    }
    _log({'type': 'recording', 'path': _recordingPath});
    _publish();
  }

  Future<void> stop() async {
    cancelProcessing();
    await _gpsSubscription?.cancel();
    _gpsSubscription = null;
    await _worker.close();
    try {
      await _journal?.flush();
      await _journal?.close();
    } catch (_) {
      _notice = 'Unable to finish saving the GPS log';
    }
    _journal = null;
    _detections = [];
    _fpsClock.stop();
    _publish();
  }

  /// Synchronous invalidation prevents late inference/upload results during
  /// video finalization, before asynchronous resource cleanup can finish.
  void cancelProcessing() {
    ++_generation;
    if (_abort?.isCompleted == false) _abort!.complete();
    _api?.dispose();
    _api = null;
    _queue.clear();
  }

  Map<String, Object> _coordinates(Position p) => {
        'latitude': p.latitude,
        'longitude': p.longitude,
        'accuracy': p.accuracy,
      };

  void _log(Map<String, Object?> entry) => _journal?.writeln(jsonEncode(entry));

  void _publish() {
    if (_disposed) return;
    snapshot.value = DashcamSnapshot(
        detections: _detections,
        fps: _fps,
        confirmed: _confirmed,
        uploaded: _uploaded,
        gps: _gps,
        notice: _notice,
        recordingPath: _recordingPath);
  }

  void dispose() {
    _disposed = true;
    snapshot.dispose();
  }
}

class _Incident {
  const _Incident(this.detection, this.position, this.time);
  final LiveDetection detection;
  final Position position;
  final DateTime time;
}
