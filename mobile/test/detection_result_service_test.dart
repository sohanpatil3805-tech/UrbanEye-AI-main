import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:urbaneye_mobile/models/detection_result.dart';
import 'package:urbaneye_mobile/services/detection_result_service.dart';

void main() {
  test('uploads one multipart request and retains every backend detection',
      () async {
    var requests = 0;
    final imageBytes =
        Uint8List.fromList(<int>[0xff, 0xd8, 12, 24, 0xff, 0xd9]);
    final client = MockClient.streaming((request, bodyStream) async {
      requests += 1;
      expect(request, isA<http.AbortableMultipartRequest>());
      expect(request.method, 'POST');
      expect(request.url, Uri.parse('https://example.test/api/detect'));
      expect(request.headers['Accept'], 'application/json');
      expect(
          request.headers['content-type'], startsWith('multipart/form-data'));

      final multipart = request as http.MultipartRequest;
      expect(multipart.files, hasLength(1));
      expect(multipart.files.single.field, 'file');
      expect(multipart.files.single.filename, 'road.jpg');
      expect(multipart.files.single.length, imageBytes.length);
      final body = latin1.decode(await bodyStream.toBytes());
      expect(body, contains('name="file"; filename="road.jpg"'));
      expect(body, contains(latin1.decode(imageBytes)));

      return _streamedResponse(_successBody(<Map<String, Object>>[
        _detection('Pothole', severity: 'Critical', confidence: 0.99),
        _detection('Longitudinal Crack', severity: 'High', confidence: 0.88),
        _detection('Alligator Crack', severity: 'Medium', confidence: 0.76),
        _detection('Transverse Crack', severity: 'Low', confidence: 0.51),
      ]));
    });
    final service = DetectionResultService(
      client: client,
      baseUrl: 'https://example.test/api/',
    );
    addTearDown(service.dispose);

    final startedAt = DateTime.now();
    expect(
      await service.uploadDetectionImage(
        imageBytes: imageBytes,
        filename: 'road.jpg',
      ),
      isTrue,
    );
    final finishedAt = DateTime.now();

    expect(requests, 1);
    final result = service.result!;
    expect(result.detections.map((item) => item.label), <String>[
      'Pothole',
      'Longitudinal Crack',
      'Alligator Crack',
      'Transverse Crack',
    ]);
    expect(result.detections.map((item) => item.confidence),
        <double>[0.99, 0.88, 0.76, 0.51]);
    expect(result.detections.map((item) => item.severity), <HazardSeverity>[
      HazardSeverity.critical,
      HazardSeverity.high,
      HazardSeverity.medium,
      HazardSeverity.low,
    ]);
    expect(result.timestamp.isBefore(startedAt), isFalse);
    expect(result.timestamp.isAfter(finishedAt), isFalse);
  });

  test('an empty detections array is a successful fresh result', () async {
    var body = _successBody(<Map<String, Object>>[_detection('Pothole')]);
    final service = DetectionResultService(
      client: MockClient((_) async => http.Response(body, 200)),
    );
    addTearDown(service.dispose);

    expect(await _upload(service), isTrue);
    expect(service.result!.detections, hasLength(1));

    body = _successBody(<Map<String, Object>>[]);
    expect(await _upload(service), isTrue);
    expect(service.result, isNotNull);
    expect(service.result!.detections, isEmpty);
  });

  final invalidBodies = <String, String>{
    'invalid JSON': '{',
    'non-object JSON': '[]',
    'missing detections': '{"status":"success"}',
    'null detections': '{"status":"success","detections":null}',
    'failed status': '{"status":"error","detections":[]}',
    'missing status': '{"detections":[]}',
    'non-object detection': '{"status":"success","detections":[null]}',
    'missing label': _successBody(<Map<String, Object>>[
      <String, Object>{'confidence': 0.9, 'severity': 'High'},
    ]),
    'empty label': _successBody(<Map<String, Object>>[_detection(' ')]),
    'non-numeric confidence': _successBody(<Map<String, Object>>[
      <String, Object>{..._detection('Pothole'), 'confidence': '0.9'},
    ]),
    'confidence out of range': _successBody(<Map<String, Object>>[
      _detection('Pothole', confidence: 1.1),
    ]),
    'unknown severity': _successBody(<Map<String, Object>>[
      _detection('Pothole', severity: 'Unknown'),
    ]),
    'partially valid detections': _successBody(<Map<String, Object>>[
      _detection('Pothole'),
      <String, Object>{'label': 'Crack'},
    ]),
  };

  for (final invalidBody in invalidBodies.entries) {
    test('${invalidBody.key} fails without exposing the previous result',
        () async {
      var body = _successBody(<Map<String, Object>>[_detection('Pothole')]);
      final service = DetectionResultService(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      addTearDown(service.dispose);

      expect(await _upload(service), isTrue);
      expect(service.result, isNotNull);

      body = invalidBody.value;
      expect(await _upload(service), isFalse);
      expect(service.result, isNull);
    });
  }

  for (final status in <int>[400, 500]) {
    test('HTTP $status fails even with a valid body and clears old results',
        () async {
      var responseStatus = 200;
      final service = DetectionResultService(
        client: MockClient((_) async => http.Response(
              _successBody(<Map<String, Object>>[_detection('Pothole')]),
              responseStatus,
            )),
      );
      addTearDown(service.dispose);

      expect(await _upload(service), isTrue);
      responseStatus = status;
      expect(await _upload(service), isFalse);
      expect(service.result, isNull);
    });
  }

  test('empty image data makes no request and clears the previous result',
      () async {
    var requests = 0;
    final service = DetectionResultService(client: MockClient((_) async {
      requests += 1;
      return http.Response(
        _successBody(<Map<String, Object>>[_detection('Pothole')]),
        200,
      );
    }));
    addTearDown(service.dispose);

    expect(await _upload(service), isTrue);
    expect(
      await service.uploadDetectionImage(imageBytes: Uint8List(0)),
      isFalse,
    );
    expect(requests, 1);
    expect(service.result, isNull);
  });

  test('forwards cancellation and permits a successful next capture', () async {
    final abort = Completer<void>();
    final started = Completer<void>();
    final lateResponse = Completer<http.StreamedResponse>();
    var requests = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      await bodyStream.drain<void>();
      requests += 1;
      if (requests == 1) {
        final abortable = request as http.Abortable;
        expect(abortable.abortTrigger, same(abort.future));
        started.complete();
        // MockClient delegates cancellation to its handler, just as a real
        // transport completes send with RequestAbortedException on abortion.
        return Future.any(<Future<http.StreamedResponse>>[
          lateResponse.future,
          abortable.abortTrigger!.then<http.StreamedResponse>((_) {
            throw http.RequestAbortedException(request.url);
          }),
        ]);
      }
      return _streamedResponse(
        _successBody(<Map<String, Object>>[_detection('New capture')]),
      );
    });
    final service = DetectionResultService(client: client);
    addTearDown(service.dispose);

    final upload = service.uploadDetectionImage(
      imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      abortTrigger: abort.future,
    );
    await started.future;
    abort.complete();
    expect(await upload, isFalse);
    expect(service.result, isNull);

    expect(await _upload(service), isTrue);
    final nextResult = service.result;
    lateResponse.complete(_streamedResponse(
      _successBody(<Map<String, Object>>[_detection('Aborted capture')]),
    ));
    await Future<void>.delayed(Duration.zero);
    expect(service.result, same(nextResult));
    expect(service.result!.detections.single.label, 'New capture');
  });

  testWidgets('a timed-out response body cannot overwrite the next result',
      (tester) async {
    final lateBody = StreamController<List<int>>();
    var requests = 0;
    final service = DetectionResultService(
      detectionUploadTimeout: const Duration(seconds: 1),
      client: MockClient.streaming((request, bodyStream) async {
        await bodyStream.drain<void>();
        requests += 1;
        if (requests == 1) {
          return http.StreamedResponse(lateBody.stream, 200);
        }
        return _streamedResponse(
          _successBody(<Map<String, Object>>[_detection('New capture')]),
        );
      }),
    );
    addTearDown(service.dispose);

    final upload = _upload(service);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await upload, isFalse);
    expect(service.result, isNull);

    expect(await _upload(service), isTrue);
    final nextResult = service.result;
    lateBody.add(utf8.encode(
      _successBody(<Map<String, Object>>[_detection('Timed-out capture')]),
    ));
    await lateBody.close();
    await tester.pump();

    expect(service.result, same(nextResult));
    expect(service.result!.detections.single.label, 'New capture');
    expect(requests, 2);
  });

  test('disposing preserves a client supplied by the caller', () async {
    final client = _CloseTrackingClient();
    final service = DetectionResultService(client: client);
    expect(await _upload(service), isTrue);

    service.dispose();

    expect(service.result, isNull);
    expect(client.closeCalls, 0);
    client.close();
  });

  test('disposing closes a client created by the service', () async {
    final client = _CloseTrackingClient();
    final service = http.runWithClient(
      () => DetectionResultService(),
      () => client,
    );
    expect(await _upload(service), isTrue);

    service.dispose();

    expect(service.result, isNull);
    expect(client.closeCalls, 1);
  });
}

Future<bool> _upload(DetectionResultService service) {
  return service.uploadDetectionImage(
    imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
  );
}

Map<String, Object> _detection(
  String label, {
  double confidence = 0.9,
  String severity = 'High',
}) {
  return <String, Object>{
    'label': label,
    'confidence': confidence,
    'severity': severity,
    'bbox': <double>[10, 20, 30, 40],
  };
}

String _successBody(List<Map<String, Object>> detections) {
  return jsonEncode(<String, Object>{
    'status': 'success',
    'detections': detections,
  });
}

http.StreamedResponse _streamedResponse(String body) {
  return http.StreamedResponse(Stream<List<int>>.value(utf8.encode(body)), 200);
}

class _CloseTrackingClient extends MockClient {
  _CloseTrackingClient()
      : super((_) async => http.Response(
              _successBody(<Map<String, Object>>[]),
              200,
            ));

  int closeCalls = 0;

  @override
  void close() {
    closeCalls += 1;
    super.close();
  }
}
