import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/detection_result.dart';
import 'api_service.dart';

/// Retains the detection response through ApiService's existing client hook.
/// Request construction, cancellation and timeouts stay in ApiService.
class DetectionResultService extends ApiService {
  factory DetectionResultService({
    http.Client? client,
    String? baseUrl,
    Duration detectionUploadTimeout = const Duration(seconds: 15),
  }) {
    return DetectionResultService._(
      _DetectionResponseClient(client ?? http.Client(),
          ownsClient: client == null),
      baseUrl: baseUrl,
      detectionUploadTimeout: detectionUploadTimeout,
    );
  }

  DetectionResultService._(
    this._responseClient, {
    super.baseUrl,
    required super.detectionUploadTimeout,
  }) : super(client: _responseClient);

  final _DetectionResponseClient _responseClient;

  DetectionResult? get result => _responseClient.result;

  @override
  Future<bool> uploadDetectionImage({
    required Uint8List imageBytes,
    String filename = 'capture.jpg',
    Future<void>? abortTrigger,
  }) async {
    _responseClient.reset();
    final succeeded = await super.uploadDetectionImage(
      imageBytes: imageBytes,
      filename: filename,
      abortTrigger: abortTrigger,
    );
    if (!succeeded) {
      // A timed-out response must not become the next capture's result.
      _responseClient.reset();
    }
    return succeeded && result != null;
  }

  @override
  void dispose() {
    _responseClient.reset();
    _responseClient.close();
    super.dispose();
  }
}

class _DetectionResponseClient extends http.BaseClient {
  _DetectionResponseClient(this._inner, {required this.ownsClient});

  final http.Client _inner;
  final bool ownsClient;
  DetectionResult? result;
  int _generation = 0;

  void reset() {
    _generation += 1;
    result = null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final generation = _generation;
    final response = await _inner.send(request);
    if (request.method != 'POST' ||
        request.url.pathSegments.lastOrNull != 'detect' ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      return response;
    }

    final bytes = await response.stream.toBytes();
    final payload = jsonDecode(utf8.decode(bytes));
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('Expected a detection response object.');
    }
    final parsed = DetectionResult.fromJson(payload, timestamp: DateTime.now());
    if (generation == _generation) {
      result = parsed;
    }

    // Replay the same response so ApiService can finish its existing flow.
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    if (ownsClient) {
      _inner.close();
    }
  }
}
