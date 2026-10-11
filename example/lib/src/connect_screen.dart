import 'package:flutter/material.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';

import 'harness.dart';

/// Chooses who to connect as, and how tokens are refreshed (B1–B6).
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final Harness _harness = HarnessScope.of(context);
  late final _server = TextEditingController(text: _harness.settings.tokenServer);
  late final _identity = TextEditingController(text: _harness.settings.identity);
  late final _ttl = TextEditingController(text: '${_harness.settings.ttlSeconds}');
  bool _busy = false;
  String? _error;

  Future<void> _connect({bool badToken = false}) async {
    _harness.settings
      ..tokenServer = _server.text.trim()
      ..identity = _identity.text.trim()
      ..ttlSeconds = int.tryParse(_ttl.text) ?? 3600;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _harness.connect(badToken: badToken);
    } catch (e) {
      _harness.addLog('connect failed: $e');
      setState(() => _error = '$e (${e.runtimeType})');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _harness.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Connect')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _server,
            decoration: const InputDecoration(labelText: 'Token server', helperText: 'tool/token_server.py'),
          ),
          TextField(
            controller: _identity,
            decoration: const InputDecoration(labelText: 'Identity'),
          ),
          TextField(
            controller: _ttl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Token lifetime, seconds',
              helperText: '180 tests refresh every few minutes (B3)',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Automatic token refresh'),
            subtitle: const Text('Off: manual mode, apply new tokens from the Tools tab (B4)'),
            value: settings.automaticRefresh,
            onChanged: (value) => setState(() => settings.automaticRefresh = value),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _connect, child: const Text('Connect')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _connect(badToken: true),
            child: const Text('Connect with a bad token (B2)'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => TwilioConversationsClient.setLogLevel(LogLevel.debug),
            child: const Text('Native SDK logs: debug'),
          ),
        ],
      ),
    );
  }
}
