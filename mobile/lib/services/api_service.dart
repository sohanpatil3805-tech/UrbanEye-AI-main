import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugPrint, debugPrintStack, kDebugMode, protected;
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Lightweight client for the UrbanEye AI backend.
///
/// Uses the current saved configuration on each request. An explicit [baseUrl]
/// override is retained for connection tests and injected clients.
class ApiService {
  ApiService({
    http.Client? client,
    String? baseUrl,
    Duration healthCheckTimeout = const Duration(seconds: 5),
    Duration locationUpdateTimeout = const Duration(seconds: 4),
    Duration detectionUploadTimeout = defaultDetectionUploadTimeout,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrlOverride = baseUrl,
        _healthCheckTimeout = healthCheckTimeout,
        _locationUpdateTimeout = locationUpdateTimeout,
        _detectionUploadTimeout = detectionUploadTimeout;

  static String get defaultBaseUrl => ApiConfig.baseUrl;

  // /detect responds only after inference, which can exceed 15 seconds on CPU.
  static const defaultDetectionUploadTimeout = Duration(seconds: 60);

  final http.Client _client;
  final bool _ownsClient;
  final String? _baseUrlOverride;
  String get baseUrl => _baseUrlOverride ?? ApiConfig.baseUrl;
  final Duration _healthCheckTimeout;
  final Duration _locationUpdateTimeout;
  final Duration _detectionUploadTimeout;

  Future<bool> checkHealth() async => (await testConnection()).isConnected;

  /// Older backends without /ping are checked through their OpenAPI document.
  Future<BackendConnectionResult> testConnection() async {
    final target = baseUrl;
    try {
      final normalized = ApiConfig.normalize(target);
      for (final endpoint in ['ping', 'openapi.json']) {
        final uri = Uri.parse('$normalized/').resolve(endpoint);
        final response = await _client.get(uri, headers: const {
          'Accept': 'application/json',
        }).timeout(_healthCheckTimeout);
        if (endpoint == 'ping' && response.statusCode == 404) continue;
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return BackendConnectionResult(false,
              'Backend responded with HTTP ${response.statusCode} at $uri.');
        }
        if (endpoint == 'openapi.json') {
          final document = jsonDecode(response.body);
          if (document is! Map<String, dynamic> ||
              document['openapi'] is! String ||
              document['paths'] is! Map ||
              !(document['paths'] as Map).containsKey('/detect')) {
            return const BackendConnectionResult(
                false, 'This server does not expose the detection API.');
          }
        }
        return BackendConnectionResult(true, 'Connected to $normalized.');
      }
    } on TimeoutException {
      return BackendConnectionResult(false,
          'Connection timed out. Check Wi-Fi and the PC firewall for $target.');
    } on FormatException catch (error) {
      return BackendConnectionResult(false, error.message);
    } catch (_) {
      return BackendConnectionResult(false,
          'Cannot reach $target. Check the address, Wi-Fi and backend server.');
    }
    return const BackendConnectionResult(false, 'Backend is unavailable.');
  }

  /// Sends a GPS update to the backend.
  ///
  /// Failures are returned as `false` rather than thrown so callers can retry
  /// on their next scheduled tracking update without interrupting the UI.
  /// Supplying [abortTrigger] cancels an upload that is no longer relevant.
  Future<bool> sendLocation({
    required String vehicleId,
    required double latitude,
    required double longitude,
    required double speed,
    required double accuracy,
    required DateTime timestamp,
    Future<void>? abortTrigger,
  }) async {
    if (vehicleId.trim().isEmpty ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        !speed.isFinite ||
        speed < 0 ||
        !accuracy.isFinite ||
        accuracy < 0) {
      return false;
    }

    try {
      final request = http.AbortableRequest(
        'POST',
        _locationUri,
        abortTrigger: abortTrigger,
      )
        ..headers.addAll(const <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode(<String, Object>{
          'vehicle_id': vehicleId,
          'latitude': latitude,
          'longitude': longitude,
          'speed': speed,
          'accuracy': accuracy,
          'timestamp': timestamp.toUtc().toIso8601String(),
        });
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_locationUpdateTimeout);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Uploads a captured image to the detection endpoint as multipart data.
  /// Coordinates are optional for existing callers and must be supplied together.
  Future<bool> uploadDetectionImage({
    required Uint8List imageBytes,
    String filename = 'capture.jpg',
    double? latitude,
    double? longitude,
    Future<void>? abortTrigger,
  }) async {
    if (imageBytes.isEmpty ||
        (latitude == null) != (longitude == null) ||
        (latitude != null &&
            (!latitude.isFinite || latitude < -90 || latitude > 90)) ||
        (longitude != null &&
            (!longitude.isFinite || longitude < -180 || longitude > 180))) {
      return false;
    }

    final uploadFilename = filename.trim().isEmpty ? 'capture.jpg' : filename;
    try {
      final request = http.AbortableMultipartRequest(
        'POST',
        _detectUri,
        abortTrigger: abortTrigger,
      )
        ..headers['Accept'] = 'application/json'
        ..fields.addAll({
          if (latitude != null) 'latitude': latitude.toString(),
          if (longitude != null) 'longitude': longitude.toString(),
        })
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            imageBytes,
            filename: uploadFilename,
          ),
        );
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_detectionUploadTimeout);

      final succeeded = response.statusCode >= 200 && response.statusCode < 300;
      if (succeeded) handleDetectionResponse(response);
      if (!succeeded && kDebugMode) {
        // Include FastAPI's detail (including validation errors) without
        // exposing backend diagnostics in the user-facing snackbar.
        debugPrint(
          'POST $_detectUri failed (${response.statusCode}): ${response.body}',
        );
      }
      return succeeded;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('POST $_detectUri failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return false;
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Local inference already confirmed this incident; do not run /detect again.
  Future<bool> uploadConfirmedEvent({
    required double confidence,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    Future<void>? abortTrigger,
  }) async {
    if (!confidence.isFinite ||
        confidence < 0 ||
        confidence > 1 ||
        !latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180) {
      return false;
    }
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 8), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      final request = http.AbortableRequest(
          'POST', Uri.parse(base).resolve('events'),
          abortTrigger: abortTrigger == null
              ? abort.future
              : Future.any([abort.future, abortTrigger]))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'event_type': 'pothole',
          'confidence': confidence,
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': timestamp.toUtc().toIso8601String(),
          'source': 'camera',
        });
      final response =
          await _client.send(request).timeout(const Duration(seconds: 8));
      await response.stream.drain<void>().timeout(const Duration(seconds: 8));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      timer.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  /// Subclasses can retain a result without another HTTP client or upload path.
  @protected
  void handleDetectionResponse(http.Response response) {}

  Uri get _locationUri {
    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(normalizedBaseUrl).resolve('location');
  }

  Uri get _detectUri {
    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(normalizedBaseUrl).resolve('detect');
  }
}

class BackendConnectionResult {
  const BackendConnectionResult(this.isConnected, this.message);

  final bool isConnected;
  final String message;
}
