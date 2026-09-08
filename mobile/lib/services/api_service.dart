import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
  ///
  /// Backwards-compatible convenience method that returns true on success.
  Future<bool> uploadDetectionImage({
    required Uint8List imageBytes,
    String filename = 'capture.jpg',
    Future<void>? abortTrigger,
  }) async {
    final result = await detectDamage(
      imageBytes: imageBytes,
      filename: filename,
      abortTrigger: abortTrigger,
    );
    return result is DetectionSuccess;
  }

  /// Sends a captured image to the /detect endpoint and returns structured
  /// detection results or user-friendly error details.
  Future<DetectionResult> detectDamage({
    required Uint8List imageBytes,
    String filename = 'capture.jpg',
    Future<void>? abortTrigger,
  }) async {
    if (imageBytes.isEmpty) {
      return const DetectionFailure(
        userMessage: 'No image data captured. Please take a photo to continue.',
      );
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
          final dynamic decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            return DetectionSuccess(DetectionResponse.fromJson(decoded));
          } else if (decoded is Map) {
            return DetectionSuccess(
              DetectionResponse.fromJson(Map<String, dynamic>.from(decoded)),
            );
          }
          return const DetectionFailure(
            userMessage: 'Unexpected response format received from the detection service.',
          );
        } catch (_) {
          return const DetectionFailure(
            userMessage: 'Unable to parse detection results from the server.',
          );
        }
      }

      if (response.statusCode == 503) {
        return const DetectionFailure(
          userMessage:
              'The AI road-damage detection model is currently unavailable on the backend.',
          isBackendUnavailable: true,
        );
      }

      return const DetectionFailure(
        userMessage:
            'Image analysis failed on the server. Please try capturing another photo.',
      );
    } on TimeoutException {
      return const DetectionFailure(
        userMessage:
            'Detection request timed out. The server took too long to process the image.',
        isBackendUnavailable: true,
      );
    } catch (_) {
      return const DetectionFailure(
        userMessage:
            'Unable to connect to the UrbanEye backend. Please check your connection and server status.',
        isBackendUnavailable: true,
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

/// A single detected road damage instance returned by the AI model.
class RoadDamageDetection {
  const RoadDamageDetection({
    required this.label,
    required this.confidence,
    required this.bbox,
    required this.severity,
  });

  /// The category of damage, e.g. "Pothole", "Alligator Crack", "Transverse Crack", "Longitudinal Crack".
  final String label;

  /// Detection confidence score in range 0.0 to 1.0.
  final double confidence;

  /// Bounding box in original image pixel coordinates: [x1, y1, x2, y2].
  final List<double> bbox;

  /// Categorical severity assessment: "Critical", "High", "Medium", or "Low".
  final String severity;

  /// Returns confidence formatted as a clean percentage string (e.g. "85%").
  String get confidencePercentage => '${(confidence * 100).toStringAsFixed(0)}%';

  factory RoadDamageDetection.fromJson(Map<String, dynamic> json) {
    final rawBbox = json['bbox'];
    final List<double> parsedBbox = [];
    if (rawBbox is List) {
      for (final value in rawBbox) {
        if (value is num) {
          parsedBbox.add(value.toDouble());
        }
      }
    }

    return RoadDamageDetection(
      label: json['label'] as String? ?? 'Road Damage',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      bbox: parsedBbox,
      severity: json['severity'] as String? ?? 'Medium',
    );
  }
}

/// Full response payload from the /detect endpoint.
class DetectionResponse {
  const DetectionResponse({
    required this.status,
    required this.filename,
    required this.detections,
  });

  final String status;
  final String filename;
  final List<RoadDamageDetection> detections;

  bool get hasDamage => detections.isNotEmpty;
  int get damageCount => detections.length;

  factory DetectionResponse.fromJson(Map<String, dynamic> json) {
    final rawDetections = json['detections'];
    final List<RoadDamageDetection> parsed = [];
    if (rawDetections is List) {
      for (final item in rawDetections) {
        if (item is Map<String, dynamic>) {
          parsed.add(RoadDamageDetection.fromJson(item));
        } else if (item is Map) {
          parsed.add(
            RoadDamageDetection.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return DetectionResponse(
      status: json['status'] as String? ?? 'success',
      filename: json['filename'] as String? ?? '',
      detections: parsed,
    );
  }
}

/// Sealed result returned by [ApiService.detectDamage].
sealed class DetectionResult {
  const DetectionResult();
}

/// Successful road damage detection result containing parsed model detections.
class DetectionSuccess extends DetectionResult {
  const DetectionSuccess(this.response);

  final DetectionResponse response;
}

/// Failure result with user-facing explanation and backend availability flag.
class DetectionFailure extends DetectionResult {
  const DetectionFailure({
    required this.userMessage,
    this.isBackendUnavailable = false,
  });

  /// Safe, human-friendly message suitable for direct display in the UI.
  final String userMessage;

  /// Whether failure was caused by backend unavailability (offline, 503, timeout).
  final bool isBackendUnavailable;
}
