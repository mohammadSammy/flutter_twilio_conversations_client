// Drives the harness screens end to end: connect, create a conversation, send text
// and a test file, log out. Needs tool/token_server.py running (see the example README).
//
//   adb reverse tcp:8787 tcp:8787        # Android over USB
//   flutter test integration_test/harness_smoke_test.dart -d <device> \
//     [--dart-define=TOKEN_SERVER=http://<address>:8787]

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_twilio_conversations_client_example/harness_app.dart';
import 'package:flutter_twilio_conversations_client_example/src/harness.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Profile builds on iOS log only to the system log; stdout also reaches devicectl --console.
  final flutterPrint = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    flutterPrint(message, wrapWidth: wrapWidth);
    if (Platform.isIOS) stdout.writeln(message);
  };
  tearDownAll(() => stdout.writeln('integration_test results: ${binding.results}'));

  /// Pumps until [finder] shows up: the screens wait on Twilio, not on animations.
  Future<void> waitFor(WidgetTester tester, Finder finder, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('not found within $seconds s: $finder');
  }

  /// Puts text straight into a field's controller. Simulated typing (enterText) didn't
  /// reach the fields in an iOS profile build launched without Flutter's tooling.
  void setText(WidgetTester tester, Finder field, String text) {
    tester.widget<TextField>(field).controller!.text = text;
  }

  testWidgets('harness: connect, chat, upload, log out', (tester) async {
    final harness = Harness();
    await tester.pumpWidget(HarnessScope(harness: harness, child: const ExampleApp()));
    final identity = 'plugin-harness-${DateTime.now().millisecondsSinceEpoch % 100000}';

    // Connect screen
    setText(tester, find.widgetWithText(TextField, 'Identity'), identity);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await waitFor(tester, find.text(identity));
    await waitFor(tester, find.textContaining('sync completed'));

    // Conversations tab: create and join (C8), then open it
    final name = 'harness-${DateTime.now().millisecondsSinceEpoch}';
    await tester.tap(find.byTooltip('Create and join (C8)'));
    await tester.pumpAndSettle();
    setText(tester, find.widgetWithText(TextField, 'Unique name'), name);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle(); // the dialog's text field also shows the name until it closes
    await waitFor(tester, find.widgetWithText(ListTile, name));
    await tester.tap(find.widgetWithText(ListTile, name));
    await waitFor(tester, find.byKey(const Key('composer')));
    await tester.pumpAndSettle(); // iOS slides the new screen in; tapping mid-slide misses
    expect(find.text('unread null'), findsOneWidget); // never read: null, not 0 (C6)

    // Send text, see it arrive through the events stream
    setText(tester, find.byKey(const Key('composer')), 'hello from the harness');
    await tester.tap(find.byIcon(Icons.send));
    await waitFor(tester, find.text('hello from the harness'));

    // Send the 3 MB test file and wait for the upload to finish
    await tester.tap(find.byTooltip('Send a test file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 MB JPEG'));
    await waitFor(tester, find.text('1 media'), seconds: 60);
    final upload = harness.uploads.single;
    for (var i = 0; i < 100 && !upload.done && upload.error == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(upload.error, isNull);
    expect(upload.done, isTrue);
    expect(upload.send.totalBytes, 3 * 1024 * 1024);
    expect(upload.bytesSent, greaterThan(0));

    // Read state (C6)
    await tester.tap(find.byTooltip('Mark all read (C6)'));
    await waitFor(tester, find.text('unread 0'));

    // Back, log out
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Log out'));
    await waitFor(tester, find.text('Connect with a bad token (B2)'));
    expect(harness.client, isNull);
  });
}
