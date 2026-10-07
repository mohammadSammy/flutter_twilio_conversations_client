// Drives the native code straight through the generated bridge, against a real Twilio
// account. The public Dart API gets its own tests; this one checks the native layer.
//
// Run from example/ on a device, with a token from ../tool/test_token.py:
//   flutter test integration_test/native_api_test.dart -d <device> \
//     --dart-define=TWILIO_TOKEN=$(python3 ../tool/test_token.py plugin-test-a)
//
// Or build it yourself and read its output from the device, without Flutter's debugger:
//   flutter build ios --config-only --profile -t integration_test/native_api_test.dart \
//     --dart-define=TWILIO_TOKEN=...
//   then xcodebuild the Runner scheme (Profile), and
//   xcrun devicectl device install app / device process launch --console <bundle id>
//   The last stdout line is "integration_test results: {...: success}".

// The public API doesn't exist yet, so the test imports the generated bridge directly.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_twilio_conversations_client/src/generated/conversations_api.g.dart';
import 'package:integration_test/integration_test.dart';

const token = String.fromEnvironment('TWILIO_TOKEN');

Matcher failsWith(String code) =>
    throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Profile builds on iOS log only to the system log. Writing to stdout as well lets
  // `xcrun devicectl device process launch --console` show failures and results.
  debugPrint = (message, {wrapWidth}) => stdout.writeln(message);

  final api = ConversationsHostApi();
  final received = <PlatformEvent>[];
  late StreamSubscription<PlatformEvent> subscription;

  /// Waits until an event matching [test] has arrived, including ones that came earlier.
  Future<T> waitFor<T extends PlatformEvent>(bool Function(T) test) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final match = received.whereType<T>().where(test);
      if (match.isNotEmpty) return match.first;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('no $T within 30 s; received: $received');
  }

  setUpAll(() => subscription = events().listen(received.add));
  tearDownAll(() async {
    await api.shutdown();
    await subscription.cancel();
    stdout.writeln('integration_test results: ${binding.results}');
  });

  testWidgets('native calls against Twilio', (tester) async {
    expect(token, isNotEmpty, reason: 'pass --dart-define=TWILIO_TOKEN=...');
    await api.setLogLevel(PlatformLogLevel.warning);

    // Client
    await expectLater(api.myConversations(), failsWith('not_connected'));
    final client = await api.connect(token, 'us1');
    expect(client.myIdentity, isNotEmpty);
    await expectLater(api.connect(token, 'us1'), failsWith('already_connected'));
    await waitFor<ConnectionStateEvent>((e) => e.state == PlatformConnectionState.connected);
    await waitFor<SyncStatusEvent>((e) => e.status == PlatformSyncStatus.completed);

    // Conversations
    final name = 'plugin-test-${DateTime.now().millisecondsSinceEpoch}';
    final created = await api.createConversation(name, 'Plugin test', '{"purpose":"test"}');
    expect(created.uniqueName, name);
    expect(jsonDecode(created.attributesJson!), {'purpose': 'test'});
    final joined = await api.join(created.sid);
    expect(joined.status, PlatformConversationStatus.joined);
    expect((await api.getConversation(name)).sid, created.sid);
    expect((await api.myConversations()).map((c) => c.sid), contains(created.sid));
    final me = await api.getParticipantByIdentity(created.sid, client.myIdentity);
    expect(me?.identity, client.myIdentity);
    expect(await api.getParticipantByIdentity(created.sid, 'nobody-$name'), isNull);

    // Never read: null, not 0. Asked first, because Twilio caches this count for 5 s.
    expect(await api.getUnreadMessagesCount(created.sid), isNull);

    // Messages and read state
    final first = await api.sendText(created.sid, 'hello');
    expect(first.body, 'hello');
    expect(first.author, client.myIdentity);
    final added = await waitFor<MessageAddedEvent>((e) => e.message.sid == first.sid);
    expect(added.conversation.sid, created.sid);
    final second = await api.sendText(created.sid, 'second');
    expect(await api.getMessagesCount(created.sid), 2);
    expect((await api.getLastMessages(created.sid, 10)).map((m) => m.body), ['hello', 'second']);
    expect((await api.getMessagesBefore(created.sid, second.index, 2)).map((m) => m.sid), [
      first.sid,
      second.sid,
    ]);
    expect(await api.setLastReadMessageIndex(created.sid, second.index), 0);
    await api.typing(created.sid);

    // Media
    final file = File('${Directory.systemTemp.path}/plugin-test.txt')
      ..writeAsStringSync('media body\n' * 20000);
    final withMedia = await api.sendMedia(
      created.sid,
      'upload-1',
      file.path,
      'text/plain',
      'plugin-test.txt',
    );
    final media = withMedia.media.single;
    expect(media.filename, 'plugin-test.txt');
    expect(media.size, file.lengthSync());
    final progress = received.whereType<UploadProgressEvent>().where((e) => e.uploadId == 'upload-1');
    expect(progress, isNotEmpty);
    expect(progress.last.totalBytes, file.lengthSync());
    final url = await api.getMediaTemporaryUrl(created.sid, withMedia.index, media.sid);
    expect(Uri.parse(url).isScheme('https'), isTrue);
    await expectLater(
      api.sendMedia(created.sid, 'upload-2', '/no/such/file', 'text/plain', null),
      failsWith('media_upload'),
    );

    await api.updateToken(token);

    // Records what Twilio answers for a missing conversation, for the error mapping.
    try {
      await api.getConversation('CH00000000000000000000000000000000');
      fail('a missing conversation was found');
    } on PlatformException catch (e) {
      debugPrint('missing conversation -> code ${e.code}, Twilio ${e.details}: ${e.message}');
    }

    await api.shutdown();
    await expectLater(api.myConversations(), failsWith('not_connected'));
  });
}
