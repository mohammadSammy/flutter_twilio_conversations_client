import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';

import 'measurements.dart';

/// Connection settings, chosen on the connect screen.
class HarnessSettings {
  String tokenServer = const String.fromEnvironment('TOKEN_SERVER', defaultValue: 'http://localhost:8787');
  String identity = 'plugin-test-a';
  int ttlSeconds = 3600;

  /// Automatic mode passes a token provider to connect; manual mode doesn't.
  bool automaticRefresh = true;
  String region = 'us1';
}

/// One line in the event log.
class LogEntry {
  LogEntry(this.text) : time = DateTime.now();
  final DateTime time;
  final String text;
}

/// An upload the app keeps after the screen that started it closes.
class TrackedUpload {
  TrackedUpload(this.label, this.send) {
    send.bytesSent.listen((sent) => bytesSent = sent);
    send.message.then(
      (_) {
        done = true;
      },
      onError: (Object e) {
        error = e;
      },
    );
  }

  final String label;
  final MediaSend send;
  int bytesSent = 0;
  bool done = false;
  Object? error;
}

/// The whole harness state: the client, the event log, uploads and measurements.
class Harness extends ChangeNotifier {
  final settings = HarnessSettings();
  final log = <LogEntry>[];
  final uploads = <TrackedUpload>[];
  late final measurements = Measurements(this);

  TwilioConversationsClient? client;
  StreamSubscription<ConversationsEvent>? _subscription;

  /// B5: the next N token provider calls fail on purpose.
  int providerFailuresLeft = 0;

  /// Asks the dev token server (tool/token_server.py) for a token.
  Future<String> fetchToken() async {
    final uri = Uri.parse(
      settings.tokenServer,
    ).replace(path: '/token', queryParameters: {'identity': settings.identity, 'ttl': '${settings.ttlSeconds}'});
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final response = await (await http.getUrl(uri)).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) throw HttpException('token server answered ${response.statusCode}: $body');
      return body.trim();
    } finally {
      http.close();
    }
  }

  Future<String> _tokenProvider() async {
    if (providerFailuresLeft > 0) {
      providerFailuresLeft--;
      notifyListeners();
      throw StateError('simulated token provider failure');
    }
    return fetchToken();
  }

  /// Connects as [HarnessSettings.identity]. [badToken] sends a malformed token (B2).
  Future<void> connect({bool badToken = false}) async {
    final stopwatch = Stopwatch()..start();
    final token = badToken ? 'not-a-valid-token' : await fetchToken();
    final client = await TwilioConversationsClient.connect(
      token: token,
      tokenProvider: settings.automaticRefresh ? _tokenProvider : null,
      options: ClientOptions(region: settings.region),
    );
    this.client = client;
    _subscription = client.events.listen(_onEvent);
    addLog(
      'connected as ${client.myIdentity} in ${stopwatch.elapsedMilliseconds} ms '
      '(${settings.automaticRefresh ? 'automatic' : 'manual'} refresh, token expires ${client.tokenExpiresAt})',
    );
    unawaited(
      client.waitUntilSynced().then(
        (_) => addLog('synced ${stopwatch.elapsedMilliseconds} ms after connect started'),
        onError: (Object e) => addLog('sync: $e'),
      ),
    );
  }

  /// B4: fetches a new token and applies it, as an app in manual mode would.
  Future<void> applyNewToken() async {
    final client = this.client!;
    await client.updateToken(await fetchToken());
    addLog('new token applied; expires ${client.tokenExpiresAt}');
  }

  /// B6: logout. The client can't be used again; connect creates a new one.
  Future<void> shutdown() async {
    await _subscription?.cancel();
    _subscription = null;
    await client?.shutdown();
    client = null;
    addLog('shut down');
  }

  TrackedUpload trackUpload(String label, MediaSend send) {
    final upload = TrackedUpload(label, send);
    uploads.insert(0, upload);
    send.bytesSent.listen((_) => notifyListeners(), onDone: notifyListeners);
    send.message.then(
      (message) => addLog('upload $label sent as message ${message.index}'),
      onError: (Object e) => addLog('upload $label failed: $e'),
    );
    notifyListeners();
    return upload;
  }

  void addLog(String text) {
    log.insert(0, LogEntry(text));
    if (log.length > 2000) log.removeLast();
    debugPrint('[harness] $text');
    notifyListeners();
  }

  void _onEvent(ConversationsEvent event) {
    measurements.onEvent(event);
    addLog(switch (event) {
      ConnectionStateChanged(:final state) => 'connection: ${state.name}',
      SyncStatusChanged(:final status) => 'sync: ${status.name}',
      TokenAboutToExpire() => 'token about to expire',
      TokenExpired() => 'token expired',
      TokenRefreshed(:final expiresAt) => 'token refreshed; expires $expiresAt',
      TokenRefreshFailed(:final error) => 'token refresh failed: $error',
      ConversationAdded(:final conversation) => 'conversation added: ${_name(conversation)}',
      MessageAdded(:final message, :final conversation) =>
        'message #${message.index} in ${_name(conversation)} from ${message.author}: '
            '${message.body ?? '${message.media.length} media'}',
      MessageUpdated(:final message) => 'message #${message.index} updated',
      TypingStarted(:final conversationSid, :final participant) =>
        '${participant.identity} started typing in $conversationSid',
      TypingEnded(:final conversationSid, :final participant) =>
        '${participant.identity} stopped typing in $conversationSid',
      ClientErrorOccurred(:final error) => 'client error: $error',
    });
  }

  static String _name(Conversation c) => c.uniqueName ?? c.friendlyName ?? c.sid;
}

/// Gives every screen the same [Harness].
class HarnessScope extends InheritedNotifier<Harness> {
  const HarnessScope({super.key, required Harness harness, required super.child}) : super(notifier: harness);

  static Harness of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HarnessScope>()!.notifier!;
}
