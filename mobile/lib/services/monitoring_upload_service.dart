import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/live_detection.dart';

class MonitoringUploadResult {
  const MonitoringUploadResult(this.success, this.message,
      {this.incidents = 0});
  final bool success;
  final String message;
  final int incidents;
}

/// Monitoring-only multipart client. Camera Ready/Gallery's ApiService and
/// FastAPI /detect are untouched. One confirmed frame produces one request.
class MonitoringUploadService {
  MonitoringUploadService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl;
  final http.Client _client;
  final String? _baseUrl;

  Future<MonitoringUploadResult> upload({
    required Uint8List image,
    required List<LiveDetection> detections,
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime timestamp,
    required DateTime gpsTimestamp,
    required Future<void> abortTrigger,
  }) async {
    if (image.isEmpty ||
        detections.isEmpty ||
        !latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180) {
      return const MonitoringUploadResult(false, 'Invalid confirmed detection');
    }
    final deadline = Completer<void>();
    final timer = Timer(const Duration(seconds: 60), () => deadline.complete());
    try {
      final base = ApiConfig.normalize(_baseUrl ?? ApiConfig.baseUrl);
      final first = detections.first;
      final request = http.AbortableMultipartRequest(
          'POST', Uri.parse('$base/detect'),
          abortTrigger: Future.any([abortTrigger, deadline.future]))
        ..headers['Accept'] = 'application/json'
        ..fields.addAll({
          'latitude': '$latitude',
          'longitude': '$longitude',
          'confidence': '${first.confidence}',
          'severity': first.severity.name,
          'timestamp': timestamp.toUtc().toIso8601String(),
          'gps_accuracy': '$accuracy',
          'gps_timestamp': gpsTimestamp.toUtc().toIso8601String(),
          'source': 'monitoring',
          'detections': jsonEncode(detections
              .map((d) => {
                    'label': d.label,
                    'confidence': d.confidence,
                    'severity': d.severity.name,
                    'bbox': d.box,
                  })
              .toList()),
        });
      request.files.add(http.MultipartFile.fromBytes(
          'file', jpegWithMetadata(image, request.fields),
          filename: 'monitoring_${timestamp.microsecondsSinceEpoch}.jpg'));
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return MonitoringUploadResult(
            false, 'Upload HTTP ${response.statusCode}');
      }
      final body = jsonDecode(response.body);
      final incidents = body is Map && body['incidents'] is List
          ? (body['incidents'] as List).length
          : 0;
      return MonitoringUploadResult(
          true,
          incidents > 0
              ? 'Backend accepted $incidents incident(s)'
              : 'Image accepted; backend returned no incidents',
          incidents: incidents);
    } catch (error) {
      return MonitoringUploadResult(false, 'Upload failed: $error');
    } finally {
      timer.cancel();
      if (!deadline.isCompleted) deadline.complete();
    }
  }

  void dispose() => _client.close();
}

/// Standard JPEG COM segment preserves local metadata in the image that the
/// unchanged backend already saves, even though /detect ignores extra forms.
Uint8List jpegWithMetadata(Uint8List jpeg, Map<String, String> metadata) {
  if (jpeg.length < 2 || jpeg[0] != 0xff || jpeg[1] != 0xd8) {
    throw const FormatException('Evidence is not JPEG');
  }
  final comment = utf8.encode(jsonEncode(metadata));
  if (comment.length > 65533) throw const FormatException('Metadata too large');
  final result = Uint8List(jpeg.length + comment.length + 4);
  result.setRange(0, 4, [0xff, 0xd8, 0xff, 0xfe]);
  ByteData.sublistView(result).setUint16(4, comment.length + 2);
  result.setRange(6, 6 + comment.length, comment);
  result.setRange(6 + comment.length, result.length, jpeg, 2);
  return result;
}
