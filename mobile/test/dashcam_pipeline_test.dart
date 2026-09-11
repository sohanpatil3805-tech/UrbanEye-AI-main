import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:urbaneye_mobile/models/live_detection.dart';
import 'package:urbaneye_mobile/services/api_service.dart';
import 'package:urbaneye_mobile/services/yolo_worker.dart';

void main() {
  test('undoes letterboxing and suppresses duplicate boxes', () {
    final detections = decodeDetections(
        Float32List.fromList([
          .25,
          .3125,
          .75,
          .6875,
          .9,
          .25,
          .3125,
          .75,
          .6875,
          .8,
          .1,
          .3,
          .2,
          .4,
          .2,
        ]),
        640,
        480);
    expect(detections, hasLength(1));
    for (var i = 0; i < 4; i++) {
      expect(detections.single.box[i], closeTo([.25, .25, .75, .75][i], 1e-6));
    }
    expect(detections.single.confidence, closeTo(.9, 1e-6));
    expect(detections.single.label, 'Pothole');
  });

  test('rejects invalid scores, inverted boxes and padded-only boxes', () {
    expect(
        decodeDetections(
            Float32List.fromList([
              0,
              0,
              1,
              1,
              double.nan,
              .8,
              .8,
              .2,
              .2,
              .9,
              .1,
              .01,
              .2,
              .1,
              .9,
              0,
              0,
              1,
              1,
              2,
            ]),
            640,
            480),
        isEmpty);
  });

  test('BGRA conversion respects row padding and clockwise rotation', () {
    final frame = CameraFrame(2, 2, 90, true, [
      FramePlane(
          TransferableTypedData.fromList([
            Uint8List.fromList([
              0,
              0,
              255,
              255,
              0,
              255,
              0,
              255,
              99,
              99,
              99,
              99,
              255,
              0,
              0,
              255,
              255,
              255,
              255,
              255,
              99,
              99,
              99,
              99,
            ])
          ]),
          12,
          4),
    ]);
    final target = Float32List(12);
    prepareInput(frame, target, 2);
    expect(target, [0, 0, 1, 1, 0, 0, 1, 1, 1, 0, 1, 0]);
  });

  test('YUV conversion respects row and chroma pixel strides', () {
    final frame = CameraFrame(2, 2, 0, false, [
      FramePlane(
          TransferableTypedData.fromList([
            Uint8List.fromList([255, 0, 17, 128, 64, 17])
          ]),
          3,
          1),
      FramePlane(
          TransferableTypedData.fromList([
            Uint8List.fromList([128, 99])
          ]),
          2,
          2),
      FramePlane(
          TransferableTypedData.fromList([
            Uint8List.fromList([128, 99])
          ]),
          2,
          2),
    ]);
    final target = Float32List(12);
    prepareInput(frame, target, 2);
    expect(target.take(6), [1, 1, 1, 0, 0, 0]);
    expect(target[6], closeTo(128 / 255, 1e-6));
    expect(target[9], closeTo(64 / 255, 1e-6));
  });

  test('letterbox uses training padding color', () {
    final frame = CameraFrame(2, 1, 0, true, [
      FramePlane(TransferableTypedData.fromList([Uint8List(8)]), 8, 4)
    ]);
    final target = Float32List(4 * 4 * 3);
    prepareInput(frame, target, 4);
    expect(target.first, closeTo(114 / 255, 1e-6));
    expect(target[12], 0);
    expect(target.last, closeTo(114 / 255, 1e-6));
  });

  test('confirmation needs three consecutive frames and reports once', () {
    final tracker = DetectionTracker();
    final time = DateTime.utc(2026);
    const pothole = LiveDetection([.2, .2, .5, .5], .9);
    expect(tracker.update([pothole], time), isEmpty);
    expect(
        tracker.update([pothole], time.add(const Duration(milliseconds: 100))),
        isEmpty);
    expect(
        tracker.update([pothole], time.add(const Duration(milliseconds: 200))),
        [pothole]);
    expect(
        tracker.update([pothole], time.add(const Duration(milliseconds: 300))),
        isEmpty);
    tracker.update([], time.add(const Duration(milliseconds: 400)));
    expect(
        tracker.update([pothole], time.add(const Duration(milliseconds: 500))),
        isEmpty);
  });

  test('duplicate boxes cannot confirm a track in one frame; gaps reset hits',
      () {
    final tracker = DetectionTracker();
    final time = DateTime.utc(2026);
    const pothole = LiveDetection([.2, .2, .5, .5], .9);
    expect(tracker.update([pothole, pothole, pothole], time), isEmpty);
    tracker.clear();
    tracker.update([pothole], time);
    tracker.update([], time.add(const Duration(milliseconds: 100)));
    expect(
        tracker.update([pothole], time.add(const Duration(milliseconds: 200))),
        isEmpty);
    expect(
        tracker.update([pothole], time.add(const Duration(milliseconds: 300))),
        isEmpty);
    expect(
        tracker.update([pothole], time.add(const Duration(milliseconds: 400))),
        [pothole]);
  });

  test('severity uses apparent size independently of confidence', () {
    expect(const LiveDetection([0, 0, .1, .1], .99).severity,
        DetectionSeverity.low);
    expect(const LiveDetection([0, 0, .3, .3], .6).severity,
        DetectionSeverity.medium);
    expect(const LiveDetection([0, 0, .5, .5], .5).severity,
        DetectionSeverity.high);
  });

  test('confirmed events use existing /events schema and capture timestamp',
      () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://localhost:8000/events');
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {
        'event_type': 'pothole',
        'confidence': .9,
        'latitude': 12.3,
        'longitude': 77.4,
        'timestamp': '2026-01-01T00:00:00.000Z',
        'source': 'camera',
      });
      return http.Response('{}', 200);
    });
    final api = ApiService(client: client, baseUrl: 'http://localhost:8000/');
    expect(
        await api.uploadConfirmedEvent(
            confidence: .9,
            latitude: 12.3,
            longitude: 77.4,
            timestamp: DateTime.utc(2026)),
        isTrue);
    client.close();
  });

  test('invalid GPS never uploads, network errors return failure', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      throw Exception('offline');
    });
    final api = ApiService(client: client, baseUrl: 'http://localhost:8000');
    expect(
        await api.uploadConfirmedEvent(
            confidence: .9,
            latitude: double.nan,
            longitude: 77.4,
            timestamp: DateTime.utc(2026)),
        isFalse);
    expect(calls, 0);
    expect(
        await api.uploadConfirmedEvent(
            confidence: .9,
            latitude: 12.3,
            longitude: 77.4,
            timestamp: DateTime.utc(2026)),
        isFalse);
    expect(calls, 1);
    client.close();
  });
}
