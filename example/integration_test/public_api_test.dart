// Uses the plugin the way an app does, through its public API, against a real Twilio
// account. native_api_test.dart checks the native layer underneath.
//
// Run from example/ on a device, with a token from ../tool/test_token.py:
//   flutter test integration_test/public_api_test.dart -d <device> \
//     --dart-define=TWILIO_TOKEN=$(python3 ../tool/test_token.py plugin-test-a)
// On iOS, see native_api_test.dart for running without Flutter's debugger.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';
import 'package:integration_test/integration_test.dart';

const token = String.fromEnvironment('TWILIO_TOKEN');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Profile builds on iOS log only to the system log; stdout also reaches devicectl --console.
  final flutterPrint = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    flutterPrint(message, wrapWidth: wrapWidth);
    if (Platform.isIOS) stdout.writeln(message);
  };
  tearDownAll(() => stdout.writeln('integration_test results: ${binding.results}'));

  testWidgets('public API against Twilio', (tester) async {
    expect(token, isNotEmpty, reason: 'pass --dart-define=TWILIO_TOKEN=...');
    await TwilioConversationsClient.setLogLevel(LogLevel.warning);

    var providerCalls = 0;
    final client = await TwilioConversationsClient.connect(
      token: token,
      tokenProvider: () async {
        providerCalls++;
        return token;
      },
    );
    final events = <ConversationsEvent>[];
    final subscription = client.events.listen(events.add);

    try {
      expect(client.myIdentity, isNotEmpty);
      expect(client.tokenExpiresAt, isNotNull);
      await expectLater(
        TwilioConversationsClient.connect(token: token),
        throwsA(isA<ClientAlreadyConnectedException>()),
      );
      await client.waitUntilSynced();
      expect(client.syncStatus, SyncStatus.completed);

      // Conversations
      final name = 'plugin-api-test-${DateTime.now().millisecondsSinceEpoch}';
      final created = await client.createConversation(uniqueName: name, attributes: {'purpose': 'test', 'n': 1});
      expect(created.attributes, {'purpose': 'test', 'n': 1});
      expect((await client.join(created.sid)).status, ConversationStatus.joined);
      expect((await client.getConversation(name)).sid, created.sid);
      expect((await client.getParticipantByIdentity(created.sid, client.myIdentity))?.identity, client.myIdentity);
      expect(await client.getUnreadMessagesCount(created.sid), isNull);

      // Messages, as an app sees them
      final sent = await client.sendText(created.sid, 'hello');
      final added = await _waitFor<MessageAdded>(events, (e) => e.message.sid == sent.sid);
      expect(added.conversation.sid, created.sid);
      expect(added.message.dateCreated?.isUtc, isTrue);
      final last = await client.getLastMessages(created.sid, count: 10);
      expect(last.single, sent);
      expect(await client.getMessagesBefore(created.sid, index: sent.index, count: 5), [sent]);
      expect(await client.setLastReadMessageIndex(created.sid, sent.index), 0);

      // Media through MediaSend
      final file = File('${Directory.systemTemp.path}/plugin-api-test.txt')..writeAsStringSync('body\n' * 40000);
      final upload = client.sendMedia(created.sid, MediaUpload(filePath: file.path, contentType: 'text/plain'));
      final progress = upload.bytesSent.toList();
      final withMedia = await upload.message;
      expect(upload.totalBytes, file.lengthSync());
      expect(await progress, isNotEmpty);
      expect(withMedia.media.single.filename, 'plugin-api-test.txt');
      final url = await client.getMediaTemporaryUrl(
        conversationSid: created.sid,
        messageIndex: withMedia.index,
        mediaSid: withMedia.media.single.sid,
      );
      expect(url.scheme, 'https');

      // Errors as typed exceptions
      await expectLater(
        client.getConversation('CH00000000000000000000000000000000'),
        throwsA(isA<ConversationNotFoundException>().having((e) => e.twilioCode, 'twilioCode', 50350)),
      );
      await expectLater(
        client.sendMedia(created.sid, const MediaUpload(filePath: '/no/such/file', contentType: 'text/plain')).message,
        throwsA(isA<MediaUploadException>()),
      );

      // Tokens: refresh on demand through the provider
      await client.refreshToken();
      expect(providerCalls, 1);
      // Events are delivered asynchronously, so wait for it rather than check at once.
      await _waitFor<TokenRefreshed>(events, (_) => true);
    } finally {
      await subscription.cancel();
      await client.shutdown();
    }

    await expectLater(client.myConversations(), throwsA(isA<NotConnectedException>()));
    // A new client can connect after shutdown, as after a logout and login.
    final again = await TwilioConversationsClient.connect(token: token);
    await again.waitUntilSynced();
    await again.shutdown();
  });
}

Future<T> _waitFor<T extends ConversationsEvent>(List<ConversationsEvent> events, bool Function(T) test) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final match = events.whereType<T>().where(test);
    if (match.isNotEmpty) return match.first;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('no $T within 30 s');
}
