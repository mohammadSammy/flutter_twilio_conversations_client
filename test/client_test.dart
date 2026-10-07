import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';
import 'package:flutter_twilio_conversations_client/src/generated/conversations_api.g.dart';
import 'package:flutter_twilio_conversations_client/src/platform/conversations_platform.dart';

void main() {
  late FakePlatform platform;
  final clients = <TwilioConversationsClient>[];

  Future<TwilioConversationsClient> connect({TokenProvider? tokenProvider, String token = 'token'}) async {
    final client = await TwilioConversationsClient.connect(token: token, tokenProvider: tokenProvider);
    clients.add(client);
    return client;
  }

  setUp(() {
    platform = FakePlatform();
    ConversationsPlatform.instance = platform;
  });

  tearDown(() async {
    for (final client in clients) {
      await client.shutdown();
    }
    clients.clear();
  });

  group('connect', () {
    test('returns the native state, keeping events that arrived while connecting', () async {
      platform.onConnect = () => platform.emit(SyncStatusEvent(status: PlatformSyncStatus.started));
      final client = await connect();
      expect(client.myIdentity, 'alice');
      expect(client.connectionState, ConnectionState.connecting);
      expect(client.syncStatus, SyncStatus.started);
    });

    test('refuses a second client without touching the platform', () async {
      await connect();
      await expectLater(connect(), throwsA(isA<ClientAlreadyConnectedException>()));
      expect(platform.calls.where((c) => c == 'connect'), hasLength(1));
    });

    test('allows a new client after shutdown, and after a failed connect', () async {
      final first = await connect();
      await first.shutdown();
      platform.failNext = PlatformException(code: 'twilio', message: 'bad token', details: 20101);
      await expectLater(connect(), throwsA(isA<TwilioException>().having((e) => e.twilioCode, 'twilioCode', 20101)));
      expect((await connect()).myIdentity, 'alice');
    });
  });

  group('errors', () {
    test('map bridge codes and known Twilio codes to exception types', () async {
      final client = await connect();
      Future<void> expectError(PlatformException error, Matcher matcher) async {
        platform.failNext = error;
        await expectLater(client.getConversation('x'), throwsA(matcher));
      }

      await expectError(
        PlatformException(code: 'twilio', message: 'Conversation not found', details: 50350),
        isA<ConversationNotFoundException>().having((e) => e.twilioCode, 'twilioCode', 50350),
      );
      await expectError(PlatformException(code: 'media_upload', message: 'm'), isA<MediaUploadException>());
      await expectError(PlatformException(code: 'not_connected', message: 'm'), isA<NotConnectedException>());
      await expectError(PlatformException(code: 'twilio', message: 'm', details: 1), isA<TwilioException>());
    });

    test('every call fails after shutdown', () async {
      final client = await connect();
      await client.shutdown();
      // Through the Future, never thrown synchronously, so catchError and await both see it.
      await expectLater(client.myConversations(), throwsA(isA<NotConnectedException>()));
      expect(
        () => client.sendMedia('CH1', const MediaUpload(filePath: 'f', contentType: 'text/plain')),
        throwsA(isA<NotConnectedException>()),
      );
    });
  });

  group('events', () {
    test('arrive as typed events with decoded snapshots', () async {
      final client = await connect();
      final events = <ConversationsEvent>[];
      client.events.listen(events.add);

      platform.emit(MessageAddedEvent(message: messageData(), conversation: conversationData()));
      platform.emit(
        TypingEvent(
          conversationSid: 'CH1',
          participant: ParticipantData(sid: 'MB1'),
          started: false,
        ),
      );
      platform.emit(ClientErrorEvent(code: 'twilio', message: 'boom', twilioCode: 42));
      await pumpEventQueue();

      final added = events[0] as MessageAdded;
      expect(added.message.attributes, {'kind': 'note'});
      expect(added.message.dateCreated, DateTime.utc(2026, 10, 7));
      expect(added.conversation.status, ConversationStatus.joined);
      expect(events[1], isA<TypingEnded>().having((e) => e.participant.sid, 'participant', 'MB1'));
      expect((events[2] as ClientErrorOccurred).error.twilioCode, 42);
    });

    test('waitUntilSynced completes on completed and throws on failed', () async {
      final client = await connect();
      final synced = client.waitUntilSynced();
      platform.emit(SyncStatusEvent(status: PlatformSyncStatus.completed));
      await synced;
      expect(client.syncStatus, SyncStatus.completed);

      await client.shutdown();
      final failing = await connect();
      final wait = failing.waitUntilSynced();
      platform.emit(SyncStatusEvent(status: PlatformSyncStatus.failed));
      await expectLater(wait, throwsA(isA<TwilioException>()));
    });

    test('waitUntilSynced throws when the client shuts down while waiting', () async {
      final client = await connect();
      final wait = expectLater(client.waitUntilSynced(), throwsA(isA<NotConnectedException>()));
      await client.shutdown();
      await wait;
    });
  });

  group('tokens', () {
    test('tokenExpiresAt is read from the token', () async {
      final client = await connect(token: jwt(exp: 1791380000));
      expect(client.tokenExpiresAt, DateTime.fromMillisecondsSinceEpoch(1791380000 * 1000, isUtc: true));
      await client.updateToken('not a jwt');
      expect(client.tokenExpiresAt, isNull);
    });

    test('automatic refresh retries after 2 s, then 5 s, and applies the new token', () {
      fakeAsync((async) {
        var calls = 0;
        late TwilioConversationsClient client;
        connect(
          tokenProvider: () async {
            calls++;
            if (calls < 3) throw StateError('backend down');
            return jwt(exp: 1791390000);
          },
        ).then((c) => client = c);
        async.flushMicrotasks();
        final events = <ConversationsEvent>[];
        client.events.listen(events.add);

        platform.emit(TokenEvent(type: PlatformTokenEventType.aboutToExpire));
        async.flushMicrotasks();
        expect(calls, 1);
        async.elapse(const Duration(seconds: 2));
        expect(calls, 2);
        async.elapse(const Duration(seconds: 4));
        expect(calls, 2);
        async.elapse(const Duration(seconds: 1));
        expect(calls, 3);

        expect(platform.updatedTokens, [jwt(exp: 1791390000)]);
        expect(events.whereType<TokenRefreshFailed>(), hasLength(2));
        expect(events.last, isA<TokenRefreshed>());
        expect(client.tokenExpiresAt, DateTime.fromMillisecondsSinceEpoch(1791390000 * 1000, isUtc: true));
        client.shutdown();
        async.flushMicrotasks();
        clients.clear();
      });
    });

    test('refreshToken needs a token provider', () async {
      final client = await connect();
      await expectLater(client.refreshToken(), throwsA(isA<TokenException>()));
    });

    test('refreshToken reports a failing provider as TokenException with the cause', () async {
      final client = await connect(tokenProvider: () async => throw StateError('offline'));
      await expectLater(
        client.refreshToken(),
        throwsA(isA<TokenException>().having((e) => e.cause, 'cause', isA<StateError>())),
      );
    });
  });

  group('sendMedia', () {
    test('routes progress to its upload and closes it when sent', () async {
      final file = File('${Directory.systemTemp.createTempSync().path}/photo.jpg')
        ..writeAsBytesSync(List.filled(300, 1));
      final client = await connect();
      platform.onSendMedia = (uploadId) async {
        platform.emit(UploadProgressEvent(uploadId: uploadId, bytesSent: 100, totalBytes: 300));
        platform.emit(UploadProgressEvent(uploadId: 'someone-else', bytesSent: 1, totalBytes: 1));
        platform.emit(UploadProgressEvent(uploadId: uploadId, bytesSent: 300, totalBytes: 300));
        await pumpEventQueue();
        return messageData();
      };

      final send = client.sendMedia('CH1', MediaUpload(filePath: file.path, contentType: 'image/jpeg'));
      final progress = send.bytesSent.toList();
      expect(send.totalBytes, 300);
      expect((await send.message).sid, 'IM1');
      expect(await progress, [100, 300]);
      expect(platform.sentFilenames, ['photo.jpg']);
    });
  });

  test('createConversation sends attributes as JSON', () async {
    final client = await connect();
    await client.createConversation(uniqueName: 'u', attributes: {'vip': true});
    expect(platform.createdAttributes, ['{"vip":true}']);
  });

  test('models compare by value', () {
    expect(Message.fromPlatform(messageData()), Message.fromPlatform(messageData()));
    expect(
      Conversation.fromPlatform(conversationData()).hashCode,
      Conversation.fromPlatform(conversationData()).hashCode,
    );
  });
}

String jwt({required int exp}) {
  String part(Map<String, Object> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'exp': exp, 'grants': {}})}.signature';
}

ConversationData conversationData() =>
    ConversationData(sid: 'CH1', status: PlatformConversationStatus.joined, attributesJson: '{}');

MessageData messageData() => MessageData(
  conversationSid: 'CH1',
  sid: 'IM1',
  index: 0,
  media: [MediaData(sid: 'ME1', category: PlatformMediaCategory.media, contentType: 'image/jpeg', size: 300)],
  author: 'alice',
  dateCreatedMillis: DateTime.utc(2026, 10, 7).millisecondsSinceEpoch,
  attributesJson: '{"kind":"note"}',
);

/// Answers like the native side, from memory, and records what it was asked.
final class FakePlatform implements ConversationsPlatform {
  final _events = StreamController<PlatformEvent>.broadcast();
  final calls = <String>[];
  final updatedTokens = <String>[];
  final sentFilenames = <String?>[];
  final createdAttributes = <String?>[];
  PlatformException? failNext;
  void Function()? onConnect;
  Future<MessageData> Function(String uploadId)? onSendMedia;

  void emit(PlatformEvent event) => _events.add(event);

  Future<T> _answer<T>(String call, FutureOr<T> Function() value) async {
    calls.add(call);
    final error = failNext;
    failNext = null;
    if (error != null) throw error;
    return value();
  }

  @override
  Stream<PlatformEvent> get events => _events.stream;

  @override
  Future<ClientData> connect(String token, String region) => _answer('connect', () {
    onConnect?.call();
    return ClientData(myIdentity: 'alice', connectionState: PlatformConnectionState.connecting);
  });

  @override
  Future<void> updateToken(String token) => _answer('updateToken', () => updatedTokens.add(token));

  @override
  Future<void> shutdown() => _answer('shutdown', () {});

  @override
  Future<void> setLogLevel(PlatformLogLevel level) => _answer('setLogLevel', () {});

  @override
  Future<List<ConversationData>> myConversations() => _answer('myConversations', () => [conversationData()]);

  @override
  Future<ConversationData> getConversation(String sidOrUniqueName) => _answer('getConversation', conversationData);

  @override
  Future<ConversationData> createConversation(String? uniqueName, String? friendlyName, String? attributesJson) =>
      _answer('createConversation', () {
        createdAttributes.add(attributesJson);
        return conversationData();
      });

  @override
  Future<ConversationData> join(String conversationSid) => _answer('join', conversationData);

  @override
  Future<ParticipantData?> getParticipantByIdentity(String conversationSid, String identity) =>
      _answer('getParticipantByIdentity', () => null);

  @override
  Future<int> getMessagesCount(String conversationSid) => _answer('getMessagesCount', () => 0);

  @override
  Future<List<MessageData>> getMessagesBefore(String conversationSid, int index, int count) =>
      _answer('getMessagesBefore', () => []);

  @override
  Future<List<MessageData>> getLastMessages(String conversationSid, int count) => _answer('getLastMessages', () => []);

  @override
  Future<int?> getUnreadMessagesCount(String conversationSid) => _answer('getUnreadMessagesCount', () => null);

  @override
  Future<int?> setLastReadMessageIndex(String conversationSid, int index) =>
      _answer('setLastReadMessageIndex', () => 0);

  @override
  Future<MessageData> sendText(String conversationSid, String body) => _answer('sendText', messageData);

  @override
  Future<MessageData> sendMedia(
    String conversationSid,
    String uploadId,
    String filePath,
    String contentType,
    String? filename,
  ) => _answer('sendMedia', () {
    sentFilenames.add(filename);
    return onSendMedia?.call(uploadId) ?? messageData();
  });

  @override
  Future<void> typing(String conversationSid) => _answer('typing', () {});

  @override
  Future<String> getMediaTemporaryUrl(String conversationSid, int messageIndex, String mediaSid) =>
      _answer('getMediaTemporaryUrl', () => 'https://example.com/media');

  @override
  Future<void> registerPushToken(PlatformPushTokenType type, String token) => _answer('registerPushToken', () {});

  @override
  Future<void> unregisterPushToken(PlatformPushTokenType type, String token) => _answer('unregisterPushToken', () {});
}
