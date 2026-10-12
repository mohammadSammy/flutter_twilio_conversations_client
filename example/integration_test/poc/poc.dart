// Shared helpers for the proof-of-concept tests (docs/poc-success-criteria.md).
// Each result is printed as one line, `POC {json}`, which the report collects.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';
import 'package:integration_test/integration_test.dart';

/// The dev token server (tool/token_server.py). Android over USB: `adb reverse tcp:8787 tcp:8787`.
const tokenServer = String.fromEnvironment('TOKEN_SERVER', defaultValue: 'http://localhost:8787');

/// Sets up the binding, and copies debug output to stdout on iOS, where profile builds
/// started by devicectl would otherwise log only to the system log.
IntegrationTestWidgetsFlutterBinding setUpPoc() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final flutterPrint = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    flutterPrint(message, wrapWidth: wrapWidth);
    if (Platform.isIOS) stdout.writeln(message);
  };
  // Release builds print no exception details, so print the failure itself too.
  final defaultReporter = reportTestException;
  reportTestException = (details, description) {
    debugPrint('POC-FAILED $description: ${details.exception}');
    defaultReporter(details, description);
  };
  tearDownAll(() => stdout.writeln('integration_test results: ${binding.results}'));
  return binding;
}

/// Records one criterion's outcome with its raw numbers.
void report(String id, {required bool pass, Map<String, Object?> data = const {}}) {
  debugPrint('POC ${jsonEncode({'id': id, 'platform': Platform.operatingSystem, 'pass': pass, ...data})}');
}

/// A token from the dev token server. [ttl] in seconds; negative gives an expired token.
Future<String> fetchToken(String identity, {int ttl = 3600}) async {
  final uri = Uri.parse(tokenServer).replace(path: '/token', queryParameters: {'identity': identity, 'ttl': '$ttl'});
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final response = await (await http.getUrl(uri)).close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) throw HttpException('token server: ${response.statusCode} $body');
    return body.trim();
  } finally {
    http.close();
  }
}

/// A unique name for this run, so runs never share conversations.
String runName(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch}';

/// Collects a client's events so a test can wait for one that already happened.
class EventLog {
  EventLog(TwilioConversationsClient client) : _subscription = client.events.listen(null) {
    _subscription.onData(events.add);
  }

  final events = <ConversationsEvent>[];
  final StreamSubscription<ConversationsEvent> _subscription;

  Future<T> waitFor<T extends ConversationsEvent>(
    bool Function(T) test, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final match = events.whereType<T>().where(test);
      if (match.isNotEmpty) return match.first;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw TimeoutException('no $T within $timeout');
  }

  Future<void> cancel() => _subscription.cancel();
}

double median(List<num> values) => percentile(values, 50);

double percentile(List<num> values, int p) {
  if (values.isEmpty) return double.nan;
  final sorted = [...values]..sort();
  return sorted[(p / 100 * (sorted.length - 1)).round()].toDouble();
}

/// Shows a step on the phone's screen for the person holding it, and logs it for the Mac.
Future<void> instruct(WidgetTester tester, String id, String text) async {
  debugPrint('POC-STEP $id $text');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$id\n\n$text', style: const TextStyle(fontSize: 26), textAlign: TextAlign.center),
          ),
        ),
      ),
    ),
  );
}

/// Records app lifecycle changes, so a test can wait for the app to leave and come back.
class LifecycleLog {
  LifecycleLog() {
    _listener = AppLifecycleListener(onStateChange: (state) => _states.add((state, DateTime.now())));
  }

  final _states = <(AppLifecycleState, DateTime)>[];
  late final AppLifecycleListener _listener;

  /// When [state] was first reached after [after].
  Future<DateTime> waitFor(AppLifecycleState state, Duration timeout, {DateTime? after}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final (s, at) in _states) {
        if (s == state && (after == null || at.isAfter(after))) return at;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw TimeoutException('app not ${state.name} within $timeout');
  }

  void dispose() => _listener.dispose();
}
