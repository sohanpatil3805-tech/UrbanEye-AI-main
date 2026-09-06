import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:urbaneye_mobile/services/api_service.dart';

void main() {
  ApiService serviceFor(
    FutureOr<http.Response> Function(http.Request request) handler, {
    Duration detectionUploadTimeout = const Duration(seconds: 15),
  }) => ApiService(
    client: MockClient(handler),
    baseUrl: 'http://example.test',
    detectionUploadTimeout: detectionUploadTimeout,
  );

  test('posts the file multipart field to /detect and parses detections', () async {
    final service = serviceFor((request) {
      expect(request.method, 'POST');
      expect(request.url.path, '/detect');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(utf8.decode(request.bodyBytes), contains('name="file"'));
      return http.Response(
        jsonEncode({
          'status': 'success',
          'filename': 'road.jpg',
          'detections': [
            {
              'label': 'Pothole',
              'confidence': 0.91,
              'bbox': [1, 2, 30, 40],
              'severity': 'High',
            },
            {
              'label': 'Crack',
              'confidence': 0.52,
              'bbox': [5, 6, 15, 16],
              'severity': 'Medium',
            },
          ],
        }),
        200,
      );
    });

    final result = await service.uploadDetectionImage(
      imageBytes: Uint8List.fromList([1]),
    );

    expect(result.isSuccess, isTrue);
    expect(result.response!.detections, hasLength(2));
    expect(
      result.response!.detections.first.boundingBox,
      [1.0, 2.0, 30.0, 40.0],
    );
  });

  test('parses an empty detections list', () async {
    final service = serviceFor(
      (_) => http.Response(
        jsonEncode({
          'status': 'success',
          'filename': 'clear.jpg',
          'detections': [],
        }),
        200,
      ),
    );

    final result = await service.uploadDetectionImage(
      imageBytes: Uint8List.fromList([1]),
    );

    expect(result.isSuccess, isTrue);
    expect(result.response!.detections, isEmpty);
  });

  test('keeps valid detections when a sibling is malformed', () async {
    final service = serviceFor(
      (_) => http.Response(
        jsonEncode({
          'status': 'success',
          'filename': 'road.jpg',
          'detections': [
            {
              'label': 'Pothole',
              'confidence': 0.91,
              'bbox': [1, 2, 30, 40],
              'severity': 'High',
            },
            {
              'label': 'Broken',
              'confidence': 'unknown',
              'bbox': [],
              'severity': 'Low',
            },
          ],
        }),
        200,
      ),
    );

    final result = await service.uploadDetectionImage(
      imageBytes: Uint8List.fromList([1]),
    );

    expect(result.isSuccess, isTrue);
    expect(result.response!.detections, hasLength(1));
  });

  test('returns a friendly error for malformed top-level responses', () async {
    final service = serviceFor(
      (_) => http.Response('{"status":"success"}', 200),
    );

    final result = await service.uploadDetectionImage(
      imageBytes: Uint8List.fromList([1]),
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('invalid detection result'));
  });

  test('returns a friendly error for HTTP 500', () async {
    final service = serviceFor((_) => http.Response('failed', 500));

    final result = await service.uploadDetectionImage(
      imageBytes: Uint8List.fromList([1]),
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('temporarily unavailable'));
  });

  test('returns a friendly error for HTTP 503', () async {
    final service = serviceFor((_) => http.Response('unavailable', 503));

    final result = await service.uploadDetectionImage(
      imageBytes: Uint8List.fromList([1]),
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('temporarily unavailable'));
  });

  test('returns a friendly error when the upload times out', () async {
    final service = serviceFor(
      (_) => Completer<http.Response>().future,
      detectionUploadTimeout: const Duration(milliseconds: 1),
    );

    final result = await service.uploadDetectionImage(
      imageBytes: Uint8List.fromList([1]),
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('timed out'));
  });

  test('returns a friendly error for a network client exception', () async {
    final service = serviceFor(
      (_) => throw http.ClientException('network unavailable'),
    );

    final result = await service.uploadDetectionImage(
      imageBytes: Uint8List.fromList([1]),
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('Unable to reach'));
  });
}
