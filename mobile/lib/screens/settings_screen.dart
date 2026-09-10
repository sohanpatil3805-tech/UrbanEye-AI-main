import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.connectionTester, super.key});

  final Future<BackendConnectionResult> Function(String)? connectionTester;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: ApiConfig.baseUrl);
  bool _busy = false;
  String? _message;
  bool _success = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<BackendConnectionResult> _test(String url) async {
    final tester = widget.connectionTester;
    if (tester != null) return tester(url);
    final service = ApiService(baseUrl: url);
    try {
      return await service.testConnection();
    } finally {
      service.dispose();
    }
  }

  Future<void> _submit({required bool save}) async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final url = ApiConfig.normalize(_controller.text);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (save) await ApiConfig.saveBaseUrl(url);
      final result = await _test(url);
      if (!mounted) return;
      setState(() {
        _controller.text = url;
        _success = result.isConnected;
        _message = '${save ? 'Address saved. ' : ''}${result.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = 'Unable to ${save ? 'save settings' : 'test connection'}. '
            'Please try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Backend Settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter the backend computer\'s Wi-Fi or hotspot address. '
                  'Your phone and computer must be on the same network.',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _controller,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Backend URL',
                    hintText: 'http://192.168.1.100:8000',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _message = null),
                  validator: (value) {
                    try {
                      ApiConfig.normalize(value ?? '');
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _submit(save: true),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save URL'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _submit(save: false),
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Test Connection'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: _success ? colors.primary : colors.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Save URL applies this address to health checks, GPS and '
                  'image uploads immediately, and remembers it after restart. '
                  'Test Connection checks the entered address without saving it.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
