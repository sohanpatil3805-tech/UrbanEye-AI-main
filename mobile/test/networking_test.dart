import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbaneye_mobile/config/api_config.dart';
import 'package:urbaneye_mobile/screens/home_screen.dart';
import 'package:urbaneye_mobile/screens/settings_screen.dart';
import 'package:urbaneye_mobile/services/api_service.dart';
import 'package:urbaneye_mobile/services/detection_result_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'api_base_url': 'http://192.168.1.10:8000',
    });
    await ApiConfig.initialize();
  });

  test('saved URL survives reload and normalizes whitespace and trailing slash',
      () async {
    await ApiConfig.saveBaseUrl(' https://backend.example/api/ ');
    expect(ApiConfig.baseUrl, 'https://backend.example/api');
    await ApiConfig.initialize();
    expect(ApiConfig.baseUrl, 'https://backend.example/api');
  });

  test('rejects device-local addresses and malformed URLs without saving',
      () async {
    for (final value in [
      '',
      '192.168.1.10:8000',
      'ftp://backend.example',
      'http://localhost:8000',
      'http://127.0.0.1:8000',
      'http://10.0.2.2:8000',
      'http://0.0.0.0:8000',
      'http://[::1]:8000',
      'https://user:secret@backend.example',
      'https://backend.example?q=1',
      'https://backend.example#fragment',
      'http://bad host:8000',
      'http://backend.example:99999',
    ]) {
      await expectLater(ApiConfig.saveBaseUrl(value), throwsFormatException);
    }
    expect(ApiConfig.baseUrl, 'http://192.168.1.10:8000');
  });

  test('existing services use saved URL for ping, GPS and multipart detection',
      () async {
    final urls = <Uri>[];
    final client = MockClient.streaming((request, stream) async {
      urls.add(request.url);
      if (request.url.path.endsWith('/detect')) {
        expect(request.method, 'POST');
        final multipart = request as http.MultipartRequest;
        expect(multipart.files.single.field, 'file');
        expect(multipart.files.single.filename, 'gallery.jpg');
        expect(multipart.fields, {'latitude': '12.0', 'longitude': '76.0'});
      }
      await stream.drain<void>();
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"status":"success","detections":[]}')),
        200,
      );
    });
    final api = ApiService(client: client);
    final detection = DetectionResultService(client: client);
    addTearDown(api.dispose);
    addTearDown(detection.dispose);
    expect(await api.checkHealth(), isTrue);
    await ApiConfig.saveBaseUrl('https://backend.example/api/');
    expect(await api.checkHealth(), isTrue);
    expect(
        await api.sendLocation(
          vehicleId: 'UE-1024',
          latitude: 12,
          longitude: 76,
          speed: 0,
          accuracy: 1,
          timestamp: DateTime.utc(2026),
        ),
        isTrue);
    expect(
        await detection.uploadDetectionImage(
          imageBytes: Uint8List.fromList([1, 2, 3]),
          filename: 'gallery.jpg',
          latitude: 12,
          longitude: 76,
        ),
        isTrue);
    expect(urls.map((url) => url.toString()), [
      'http://192.168.1.10:8000/ping',
      'https://backend.example/api/ping',
      'https://backend.example/api/location',
      'https://backend.example/api/detect',
    ]);
  });

  test('missing ping falls back to the detection OpenAPI document', () async {
    final paths = <String>[];
    final api = ApiService(client: MockClient((request) async {
      paths.add(request.url.path);
      return request.url.path == '/ping'
          ? http.Response('{}', 404)
          : http.Response('{"openapi":"3.1.0","paths":{"/detect":{}}}', 200);
    }));
    addTearDown(api.dispose);
    expect(await api.checkHealth(), isTrue);
    expect(paths, ['/ping', '/openapi.json']);
  });

  test('does not hide a failing ping behind a working OpenAPI document',
      () async {
    var calls = 0;
    final api = ApiService(client: MockClient((_) async {
      calls++;
      return http.Response('{}', 503);
    }));
    addTearDown(api.dispose);
    final result = await api.testConnection();
    expect(result.isConnected, isFalse);
    expect(result.message, contains('503'));
    expect(calls, 1);
  });

  test('unrelated OpenAPI server is not reported as connected', () async {
    final api = ApiService(
        client: MockClient((request) async => request.url.path == '/ping'
            ? http.Response('{}', 404)
            : http.Response('{"openapi":"3.1.0","paths":{}}', 200)));
    addTearDown(api.dispose);
    expect(await api.checkHealth(), isFalse);
  });

  test('connection timeout returns an actionable diagnostic', () async {
    final api = ApiService(client: MockClient((_) async {
      throw TimeoutException('offline');
    }));
    addTearDown(api.dispose);
    final result = await api.testConnection();
    expect(result.isConnected, isFalse);
    expect(result.message, contains('firewall'));
  });

  testWidgets('Test Connection checks draft URL without saving it',
      (tester) async {
    String? tested;
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(
      connectionTester: (url) async {
        tested = url;
        return const BackendConnectionResult(true, 'Connected.');
      },
    )));
    await tester.enterText(
        find.byType(TextFormField), 'http://192.168.1.20:8000');
    await tester.tap(find.text('Test Connection'));
    await tester.pumpAndSettle();
    expect(tested, 'http://192.168.1.20:8000');
    expect(ApiConfig.baseUrl, 'http://192.168.1.10:8000');
    expect(find.text('Connected.'), findsOneWidget);
  });

  testWidgets('saving a reachable URL updates the existing offline dashboard',
      (tester) async {
    final api = ApiService(
        client: MockClient((request) async => http.Response(
              '{}',
              request.url.host == '192.168.1.20' ? 200 : 503,
            )));
    addTearDown(api.dispose);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(apiService: api),
      routes: {
        '/settings': (_) => SettingsScreen(
            connectionTester: (_) async =>
                const BackendConnectionResult(true, 'Connected.')),
      },
    ));
    await tester.pumpAndSettle();
    expect(find.text('Backend Offline'), findsOneWidget);
    await tester.tap(find.text('Backend Settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField), 'http://192.168.1.20:8000');
    await tester.tap(find.text('Save URL'));
    await tester.pumpAndSettle();
    expect(find.text('Address saved. Connected.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Backend Online'), findsOneWidget);
    expect(find.text('Backend Offline'), findsNothing);
    await ApiConfig.initialize();
    expect(ApiConfig.baseUrl, 'http://192.168.1.20:8000');
  });
}
