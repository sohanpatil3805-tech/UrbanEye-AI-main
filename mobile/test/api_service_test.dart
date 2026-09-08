import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:urbaneye_mobile/services/api_service.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;
  int callCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    callCount += 1;
    return _handler(request);
  }
}

http.StreamedResponse _jsonResponse({
  required int statusCode,
  required Map<String, dynamic> body,
}) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream.value(bytes),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  group('ApiService - Road Damage Detection', () {
    test('successful detection response parses road damage, severity, and bounding boxes',
        () async {
      final client = _FakeHttpClient((request) async {
        expect(request.url.path, endsWith('/detect'));
        expect(request.method, 'POST');

        return _jsonResponse(
          statusCode: 200,
          body: {
            'status': 'success',
            'filename': '20260906_172000_123456.jpg',
            'detections': [
              {
                'label': 'Pothole',
                'confidence': 0.884,
                'bbox': [120.0, 340.5, 450.2, 680.0],
                'severity': 'Critical',
              },
              {
                'label': 'Alligator Crack',
                'confidence': 0.652,
                'bbox': [50.0, 100.0, 200.0, 300.0],
                'severity': 'High',
              },
            ],
          },
        );
      });

      final api = ApiService(client: client, baseUrl: 'http://test-server:8000');
      final result = await api.detectDamage(imageBytes: Uint8List.fromList([1, 2, 3, 4]));

      expect(result, isA<DetectionSuccess>());
      final success = result as DetectionSuccess;
      expect(success.response.status, 'success');
      expect(success.response.filename, '20260906_172000_123456.jpg');
      expect(success.response.hasDamage, isTrue);
      expect(success.response.damageCount, 2);

      final pothole = success.response.detections[0];
      expect(pothole.label, 'Pothole');
      expect(pothole.confidence, closeTo(0.884, 0.001));
      expect(pothole.confidencePercentage, '88%');
      expect(pothole.severity, 'Critical');
      expect(pothole.bbox, [120.0, 340.5, 450.2, 680.0]);

      final crack = success.response.detections[1];
      expect(crack.label, 'Alligator Crack');
      expect(crack.confidencePercentage, '65%');
      expect(crack.severity, 'High');

      // Also verify backwards compatibility of uploadDetectionImage
      final uploadSuccess =
          await api.uploadDetectionImage(imageBytes: Uint8List.fromList([1, 2, 3]));
      expect(uploadSuccess, isTrue);
    });

    test('clean road detection returns success with empty damage list', () async {
      final client = _FakeHttpClient((request) async {
        return _jsonResponse(
          statusCode: 200,
          body: {
            'status': 'success',
            'filename': 'clean_road.jpg',
            'detections': [],
          },
        );
      });

      final api = ApiService(client: client);
      final result = await api.detectDamage(imageBytes: Uint8List.fromList([10, 20]));

      expect(result, isA<DetectionSuccess>());
      final success = result as DetectionSuccess;
      expect(success.response.hasDamage, isFalse);
      expect(success.response.damageCount, isZero);
    });

    test('HTTP 503 model unavailable returns user-friendly DetectionFailure',
        () async {
      final client = _FakeHttpClient((request) async {
        return _jsonResponse(
          statusCode: 503,
          body: {'detail': 'Road-damage model is unavailable.'},
        );
      });

      final api = ApiService(client: client);
      final result = await api.detectDamage(imageBytes: Uint8List.fromList([1, 2, 3]));

      expect(result, isA<DetectionFailure>());
      final failure = result as DetectionFailure;
      expect(failure.isBackendUnavailable, isTrue);
      expect(failure.userMessage, contains('unavailable'));
      expect(failure.userMessage, isNot(contains('Exception')));
      expect(failure.userMessage, isNot(contains('Traceback')));
    });

    test('HTTP 500 inference failure returns user-friendly DetectionFailure without raw traces',
        () async {
      final client = _FakeHttpClient((request) async {
        return _jsonResponse(
          statusCode: 500,
          body: {'detail': 'Internal Server Error: YOLO inference failed'},
        );
      });

      final api = ApiService(client: client);
      final result = await api.detectDamage(imageBytes: Uint8List.fromList([1, 2, 3]));

      expect(result, isA<DetectionFailure>());
      final failure = result as DetectionFailure;
      expect(failure.userMessage, contains('failed on the server'));
      expect(failure.userMessage, isNot(contains('Internal Server Error')));
    });

    test('Network/Socket error returns backend unavailable DetectionFailure without raw trace',
        () async {
      final client = _FakeHttpClient((request) async {
        throw http.ClientException('Connection refused: errno = 111');
      });

      final api = ApiService(client: client);
      final result = await api.detectDamage(imageBytes: Uint8List.fromList([1, 2, 3]));

      expect(result, isA<DetectionFailure>());
      final failure = result as DetectionFailure;
      expect(failure.isBackendUnavailable, isTrue);
      expect(failure.userMessage, contains('Unable to connect to the UrbanEye backend'));
      expect(failure.userMessage, isNot(contains('errno')));
      expect(failure.userMessage, isNot(contains('ClientException')));
    });

    test('empty image bytes returns immediate validation failure', () async {
      final client = _FakeHttpClient((request) async {
        fail('Should not make HTTP request for empty image bytes');
      });

      final api = ApiService(client: client);
      final result = await api.detectDamage(imageBytes: Uint8List(0));

      expect(result, isA<DetectionFailure>());
      expect((result as DetectionFailure).userMessage, contains('No image data captured'));
      expect(client.callCount, isZero);
    });
  });
}
