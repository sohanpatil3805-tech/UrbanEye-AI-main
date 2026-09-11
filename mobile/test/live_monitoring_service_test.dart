import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart'
    as platform;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:urbaneye_mobile/models/live_detection.dart';
import 'package:urbaneye_mobile/services/dashcam_service.dart';
import 'package:urbaneye_mobile/services/monitoring_upload_service.dart';
import 'package:urbaneye_mobile/services/yolo_worker.dart';

void main() {
  late _Worker worker;
  late _Gps gps;
  late _Uploader uploader;
  late DashcamService service;
  late DateTime now;
  setUp(() {
    now = DateTime.utc(2026, 9, 11);
    worker = _Worker();
    gps = _Gps();
    uploader = _Uploader();
    service = DashcamService(
        worker: worker,
        gps: gps,
        uploaderFactory: () => uploader,
        now: () => now);
  });
  tearDown(() async {
    await service.stop();
    service.dispose();
    await gps.positions.close();
  });

  test('indoor confirmation and boxes do not depend on GPS or uploads',
      () async {
    gps.denied = true;
    await service.initialize();
    service.setStreaming(true);
    service.cameraFrame(frame);
    await service.process(frame, 90);
    final state = service.snapshot.value;
    expect(state.modelLoaded, isTrue);
    expect(state.streaming, isTrue);
    expect(state.totalFrames, 1);
    expect(state.detections, [pothole]);
    expect(state.confirmed, 1);
    expect(state.inferenceMs, 12);
    expect(state.maxConfidence, .94);
    expect(state.pending, 1);
    expect(uploader.calls, 0);
    expect(state.notice, contains('waiting for GPS'));
  });

  test(
      'new pothole uploads immediately with capture GPS; repeats do not upload',
      () async {
    await service.initialize();
    gps.positions.add(fix(now,
        accuracy: 90)); // Poor indoor accuracy must not hide detections.
    await flush();
    await service.process(frame, 0);
    await flush();
    expect(service.snapshot.value.confirmed, 1);
    expect(uploader.calls, 1);
    expect(uploader.latitude, 12.3);
    expect(uploader.confidence, .94);
    expect(uploader.timestamp, now);
    expect(service.snapshot.value.backendIncidents, 1);
    await service.process(frame, 0);
    await flush();
    expect(worker.encodes, 1);
    expect(uploader.calls, 1);
    expect(service.snapshot.value.confirmed, 1);
  });

  test('first GPS fix releases pending image with its original detection time',
      () async {
    await service.initialize();
    await service.process(frame, 0);
    final capturedAt = now;
    expect(uploader.calls, 0);
    now = now.add(const Duration(seconds: 2));
    gps.positions.add(fix(now));
    await flush();
    expect(uploader.calls, 1);
    expect(uploader.timestamp, capturedAt);
    expect(uploader.gpsTimestamp, now);
  });

  test(
      'GPS arriving during JPEG encoding uploads without waiting for another fix',
      () async {
    await service.initialize();
    worker.pendingEvidence = Completer<Uint8List>();
    final processing = service.process(frame, 0);
    await flush();
    expect(service.snapshot.value.confirmed, 1);
    gps.positions.add(fix(now));
    await flush();
    worker.pendingEvidence!
        .complete(Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]));
    await processing;
    await flush();
    expect(uploader.calls, 1);
    expect(service.snapshot.value.pending, 0);
  });

  test('late GPS never assigns a far later location to an old pothole',
      () async {
    await service.initialize();
    await service.process(frame, 0);
    now = now.add(const Duration(seconds: 40));
    gps.positions.add(fix(now));
    await flush();
    expect(uploader.calls, 0);
    expect(service.snapshot.value.pending, 0);
    expect(service.snapshot.value.confirmed, 1);
  });

  test('local counting continues while backend upload is slow', () async {
    await service.initialize();
    gps.positions.add(fix(now));
    await flush();
    uploader.pending = Completer<MonitoringUploadResult>();
    await service.process(frame, 0);
    worker.result = const InferenceResult([
      LiveDetection([.7, .7, .9, .9], .8)
    ], 13, .8);
    await service.process(frame, 0);
    expect(service.snapshot.value.confirmed, 2);
    expect(uploader.calls, 1);
    expect(service.snapshot.value.pending, 1);
    uploader.pending!
        .complete(const MonitoringUploadResult(true, 'OK', incidents: 1));
    await flush();
    expect(uploader.calls, 2);
  });

  test('stop cancels upload and clears pending evidence', () async {
    await service.initialize();
    gps.positions.add(fix(now));
    await flush();
    uploader.pending = Completer<MonitoringUploadResult>();
    await service.process(frame, 0);
    await service.stop();
    await flush();
    expect(uploader.aborted, isTrue);
    expect(service.snapshot.value.streaming, isFalse);
    expect(service.snapshot.value.pending, 0);
    uploader.pending!
        .complete(const MonitoringUploadResult(true, 'late', incidents: 1));
    await flush();
    expect(service.snapshot.value.uploaded, 0);
  });

  test('model failures explicitly report Model Loaded No', () async {
    worker.error = StateError('bad model tensor');
    await expectLater(service.initialize(), throwsStateError);
    expect(service.snapshot.value.modelLoaded, isFalse);
    expect(service.snapshot.value.notice, contains('bad model tensor'));
  });

  test(
      'IoU filter confirms first sighting and suppresses continuous visibility',
      () {
    final filter = LiveConfirmationFilter();
    expect(filter.update([pothole, pothole], now), [pothole]);
    for (var i = 1; i <= 20; i++) {
      expect(filter.update([pothole], now.add(Duration(seconds: i))), isEmpty);
    }
    expect(filter.update([pothole], now.add(const Duration(seconds: 31))),
        [pothole]);
    expect(
        filter.update([
          const LiveDetection([0, 0, .1, .1], .24)
        ], now),
        isEmpty);
  });

  test('confirmed multipart uses /detect and sends image and all metadata',
      () async {
    final jpeg = img.encodeJpg(img.Image(width: 8, height: 8));
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://192.168.1.44:8000/detect');
      expect(
          request.headers['content-type'], startsWith('multipart/form-data'));
      final body = latin1.decode(request.bodyBytes);
      for (final field in [
        'file',
        'latitude',
        'longitude',
        'confidence',
        'severity',
        'timestamp',
        'detections'
      ]) {
        expect(body, contains('name="$field"'));
      }
      expect(body, contains('Pothole'));
      expect(body, contains('0.94'));
      return http.Response('{"incidents":[{"id":1}]}', 200);
    });
    final api = MonitoringUploadService(
        client: client, baseUrl: 'http://192.168.1.44:8000');
    final result = await api.upload(
        image: jpeg,
        detections: [pothole],
        latitude: 12.3,
        longitude: 77.4,
        accuracy: 5,
        timestamp: now,
        gpsTimestamp: now,
        abortTrigger: Completer<void>().future);
    expect(result.success, isTrue, reason: result.message);
    expect(result.incidents, 1);
    api.dispose();
  });

  test('JPEG remains decodable and contains persisted confidence and severity',
      () {
    final jpeg = img.encodeJpg(img.Image(width: 8, height: 8));
    final evidence =
        jpegWithMetadata(jpeg, {'confidence': '.94', 'severity': 'high'});
    expect(img.decodeJpg(evidence)?.width, 8);
    final length = ByteData.sublistView(evidence).getUint16(4) - 2;
    expect(jsonDecode(utf8.decode(evidence.sublist(6, 6 + length))),
        {'confidence': '.94', 'severity': 'high'});
  });
}

const pothole = LiveDetection([.2, .2, .5, .5], .94);
final frame = CameraImage.fromPlatformInterface(platform.CameraImageData(
    format: const platform.CameraImageFormat(ImageFormatGroup.bgra8888, raw: 0),
    planes: [platform.CameraImagePlane(bytes: Uint8List(16), bytesPerRow: 8)],
    height: 2,
    width: 2));
Future<void> flush() => Future<void>.delayed(Duration.zero);
Position fix(DateTime time, {double accuracy = 5}) => Position(
    latitude: 12.3,
    longitude: 77.4,
    timestamp: time,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0);

class _Worker extends YoloWorker {
  Completer<Uint8List>? pendingEvidence;
  InferenceResult result = const InferenceResult([pothole], 12, .94);
  Object? error;
  int encodes = 0;
  @override
  Future<void> initialize() async {
    if (error != null) throw error!;
  }

  @override
  Future<InferenceResult> detect(CameraImage image, int rotation) async =>
      result;
  @override
  Future<Uint8List> encodeEvidence() async {
    encodes++;
    if (pendingEvidence != null) return pendingEvidence!.future;
    return Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
  }

  @override
  Future<void> close() async {}
}

class _Gps implements MonitoringGps {
  bool denied = false;
  final positions = StreamController<Position>.broadcast();
  @override
  Future<Stream<Position>> open() async {
    if (denied) throw StateError('Permission denied');
    return positions.stream;
  }

  @override
  Future<Position?> lastKnown() async => null;
}

class _Uploader extends MonitoringUploadService {
  int calls = 0;
  double? latitude, confidence;
  DateTime? timestamp, gpsTimestamp;
  bool aborted = false;
  Completer<MonitoringUploadResult>? pending;
  @override
  Future<MonitoringUploadResult> upload(
      {required Uint8List image,
      required List<LiveDetection> detections,
      required double latitude,
      required double longitude,
      required double accuracy,
      required DateTime timestamp,
      required DateTime gpsTimestamp,
      required Future<void> abortTrigger}) async {
    calls++;
    this.latitude = latitude;
    confidence = detections.first.confidence;
    this.timestamp = timestamp;
    this.gpsTimestamp = gpsTimestamp;
    unawaited(abortTrigger.then((_) {
      aborted = true;
    }));
    return pending != null
        ? await pending!.future
        : const MonitoringUploadResult(true, 'OK', incidents: 1);
  }
}
