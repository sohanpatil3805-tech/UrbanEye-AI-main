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
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        baseUrl = baseUrl ?? defaultBaseUrl,
        _healthCheckTimeout = healthCheckTimeout;

  static const defaultBaseUrl = String.fromEnvironment(
    'URBANEYE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  final http.Client _client;
  final bool _ownsClient;
  final String baseUrl;
  final Duration _healthCheckTimeout;

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

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Uri get _healthUri {
    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse(normalizedBaseUrl).resolve('health');
  }
}
