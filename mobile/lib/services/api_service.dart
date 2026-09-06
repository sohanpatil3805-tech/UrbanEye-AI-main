import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/detection_response.dart';

/// Lightweight client for the UrbanEye AI backend.
///
/// Override [baseUrl] in code or pass the URBANEYE_API_BASE_URL dart define
/// when launching the app.
class ApiService {
  ApiService({
    http.Client? client,
    String? baseUrl,
    Duration healthCheckTimeout = const Duration(seconds: 5),
    Duration locationUpdateTimeout = const Duration(seconds: 4),
    Duration detectionUploadTimeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        baseUrl = baseUrl ?? defaultBaseUrl,
        _healthCheckTimeout = healthCheckTimeout,
        _locationUpdateTimeout = locationUpdateTimeout,
        _detectionUploadTimeout = detectionUploadTimeout;

  static const defaultBaseUrl = String.fromEnvironment(
    'URBANEYE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;
  final Duration _healthCheckTimeout;
  final Duration _locationUpdateTimeout;
  final Duration _detectionUploadTimeout;

  /// Returns true only when the backend responds to GET /health with 2xx.
  Future<bool> checkHealth() async {
    try {
      final response = await _client.get(
        _healthUri,
        headers: const <String, String>{
          'Accept': 'application/json',
        },
      ).timeout(_healthCheckTimeout);

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
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
  Future<DetectionUploadResult> uploadDetectionImage({
    required Uint8List imageBytes,
    String filename = 'capture.jpg',
    Future<void>? abortTrigger,
  }) async {
    if (imageBytes.isEmpty) {
      return const DetectionUploadResult.failure('The captured image is empty.');
    }

    final uploadFilename = filename.trim().isEmpty ? 'capture.jpg' : filename;
    try {
      final request = http.AbortableMultipartRequest(
        'POST',
        _detectUri,
        abortTrigger: abortTrigger,
      )
        ..headers['Accept'] = 'application/json'
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

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          return DetectionUploadResult.success(
            DetectionResponse.fromJson(jsonDecode(response.body)),
          );
        } on FormatException {
          return const DetectionUploadResult.failure(
            'The server returned an invalid detection result. Please try again.',
          );
        }
      }
      if (response.statusCode == 500 || response.statusCode == 503) {
        return const DetectionUploadResult.failure(
          'Road-damage analysis is temporarily unavailable. Please try again.',
        );
      }
      return const DetectionUploadResult.failure(
        'Unable to analyze this image. Please try again.',
      );
    } on TimeoutException {
      return const DetectionUploadResult.failure(
        'Analysis timed out. Check your connection and try again.',
      );
    } on http.ClientException {
      return const DetectionUploadResult.failure(
        'Unable to reach the analysis service. Check your connection.',
      );
    } catch (_) {
      return const DetectionUploadResult.failure(
        'Unable to analyze this image. Please try again.',
      );
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Uri get _healthUri {
    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(normalizedBaseUrl).resolve('health');
  }

  Uri get _locationUri {
    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(normalizedBaseUrl).resolve('location');
  }

  Uri get _detectUri {
    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(normalizedBaseUrl).resolve('detect');
  }
}
