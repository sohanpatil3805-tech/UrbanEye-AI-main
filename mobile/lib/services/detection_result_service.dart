import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/detection_result.dart';
import 'api_service.dart';

/// Parses results from the same client and multipart method used by ApiService.
class DetectionResultService extends ApiService {
  DetectionResultService({
    super.client,
    super.baseUrl,
    super.detectionUploadTimeout,
  });

  DetectionResult? _result;
  DetectionResult? get result => _result;

  @override
  void handleDetectionResponse(http.Response response) {
    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Expected a detection response object.');
    }
    _result = DetectionResult.fromJson(payload, timestamp: DateTime.now());
  }

  @override
  Future<bool> uploadDetectionImage({
    required Uint8List imageBytes,
    String filename = 'capture.jpg',
    double? latitude,
    double? longitude,
    Future<void>? abortTrigger,
  }) async {
    _result = null;
    final succeeded = await super.uploadDetectionImage(
      imageBytes: imageBytes,
      filename: filename,
      latitude: latitude,
      longitude: longitude,
      abortTrigger: abortTrigger,
    );
    if (!succeeded) _result = null;
    return succeeded && _result != null;
  }

  @override
  void dispose() {
    _result = null;
    super.dispose();
  }
}
