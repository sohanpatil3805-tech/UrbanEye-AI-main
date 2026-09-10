import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One backend address for every service, loaded before the app starts.
class ApiConfig {
  ApiConfig._();

  static const String _buildBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _preferenceKey = 'api_base_url';
  static final _url = ValueNotifier<String>('');

  static String get baseUrl => _url.value;
  static ValueListenable<String> get changes => _url;

  /// Saved settings override the build address. If neither is set, use Settings.
  static Future<void> initialize() async {
    String? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getString(_preferenceKey);
    } catch (error) {
      debugPrint('Unable to load backend settings: $error');
    }
    for (final candidate in [saved, _buildBaseUrl]) {
      if (candidate == null || candidate.isEmpty) continue;
      try {
        _url.value = normalize(candidate);
        return;
      } on FormatException {
        // Ignore obsolete device-local addresses from older installations.
      }
    }
    _url.value = '';
  }

  static String normalize(String value) {
    final text = value.trim();
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        RegExp(r'\s').hasMatch(text) ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException(
        'Enter an HTTP or HTTPS backend URL, including its port if needed.',
      );
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.startsWith('127.') ||
        ['0.0.0.0', '::', '::1', '[::]', '[::1]', '10.0.2.2', '10.0.3.2']
            .contains(host)) {
      throw const FormatException(
        'Use the backend computer\'s Wi-Fi or hotspot address.',
      );
    }
    return uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }

  static Future<void> saveBaseUrl(String value) async {
    final normalized = normalize(value);
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_preferenceKey, normalized)) {
      throw StateError('Unable to save backend settings.');
    }
    _url.value = normalized;
  }
}
