import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import 'errors.dart';
import 'events.dart';
import 'generated/conversations_api.g.dart';
import 'media.dart';
import 'models.dart';
import 'platform/conversations_platform.dart';
import 'push.dart';
import 'token.dart';

enum LogLevel { silent, fatal, error, warning, info, debug, trace }

final class ClientOptions {
  const ClientOptions({this.region = 'us1'});

  /// Twilio's region for this account, for example `us1` or `ie1`.
  final String region;
}

/// A connection to Twilio Conversations for one identity (api-design §3).
///
/// Create one with [connect]. Only one client can be connected at a time; call
/// [shutdown] before connecting again, for example after a logout.
final class TwilioConversationsClient {
  TwilioConversationsClient._(this._platform, this._tokenProvider, String token) : _tokenExpiresAt = tokenExpiry(token);

  /// The client that is connecting or connected. The native side has one event sink,
  /// so a second client must be refused before it touches the platform.
  static TwilioConversationsClient? _active;

  final ConversationsPlatform _platform;
  final TokenProvider? _tokenProvider;
  final _events = StreamController<ConversationsEvent>.broadcast();
  final _syncChanges = StreamController<SyncStatus>.broadcast();
  final _uploads = <String, StreamController<int>>{};
  StreamSubscription<PlatformEvent>? _subscription;

  String _myIdentity = '';
  ConnectionState _connectionState = ConnectionState.unknown;
  SyncStatus? _syncStatus;
  DateTime? _tokenExpiresAt;
  bool _closed = false;
  int _uploadCount = 0;
  int _refreshGeneration = 0;
  Future<void>? _refreshInFlight;

  /// Creates the native client and starts connecting. Completes once the client
  /// exists, before sync has finished; use [waitUntilSynced] for that.
  ///
  /// With a [tokenProvider], the client fetches and applies a new token by itself
  /// whenever Twilio says the current one is about to expire (api-design §4).
  static Future<TwilioConversationsClient> connect({
    required String token,
    TokenProvider? tokenProvider,
    ClientOptions options = const ClientOptions(),
  }) async {
    if (_active != null) {
      throw const ClientAlreadyConnectedException('a client is already connected; call shutdown first');
    }
    final platform = ConversationsPlatform.instance;
    final client = TwilioConversationsClient._(platform, tokenProvider, token);
    _active = client;
    // Listen first: the native client reports its first states while connecting.
    client._subscription = platform.events.listen(client._onPlatformEvent);
    try {
      final data = await guardPlatform(() => platform.connect(token, options.region));
      client._myIdentity = data.myIdentity;
      client._connectionState = ConnectionState.values.byName(data.connectionState.name);
      client._syncStatus = _toSyncStatus(data.syncStatus) ?? client._syncStatus;
      return client;
    } catch (_) {
      _active = null;
      client._closed = true;
      await client._subscription?.cancel();
      rethrow;
    }
  }

  /// Sets how much the native SDKs log. Works with or without a client.
  static Future<void> setLogLevel(LogLevel level) =>
      guardPlatform(() => ConversationsPlatform.instance.setLogLevel(PlatformLogLevel.values.byName(level.name)));

  /// The identity in the token.
  String get myIdentity => _myIdentity;

  /// The latest known connection state.
  ConnectionState get connectionState => _connectionState;

  /// The latest known sync status; null until Twilio reports the first one.
  SyncStatus? get syncStatus => _syncStatus;

  /// When the current token expires, read from the token itself; null if unreadable.
  DateTime? get tokenExpiresAt => _tokenExpiresAt;

  /// Everything that happens on the client. Broadcast, with no replay: the getters
  /// above hold the latest state for listeners that start late (api-design §7).
  Stream<ConversationsEvent> get events => _events.stream;

  /// Completes when sync reaches `completed`. Throws [TwilioException] if sync fails,
  /// and [NotConnectedException] if the client is shut down while waiting.
  Future<void> waitUntilSynced() async {
    _checkOpen();
    var status = _syncStatus;
    if (status != SyncStatus.completed && status != SyncStatus.failed) {
      status = await _syncChanges.stream.firstWhere(
        (s) => s == SyncStatus.completed || s == SyncStatus.failed,
        orElse: () => throw const NotConnectedException('the client was shut down while waiting for sync'),
      );
    }
    if (status == SyncStatus.failed) throw const TwilioException('sync failed');
  }

  /// Applies a new token, for example after a `TokenAboutToExpire` event in manual mode.
  Future<void> updateToken(String token) async {
    _checkOpen();
    await guardPlatform(() => _platform.updateToken(token));
    _tokenExpiresAt = tokenExpiry(token);
  }

  /// Fetches a token from the token provider and applies it now, once. Throws
  /// [TokenException] when there's no provider or it fails.
  Future<void> refreshToken() async {
    _checkOpen();
    if (_tokenProvider == null) {
      throw const TokenException('refreshToken needs a tokenProvider passed to connect');
    }
    try {
      await _refreshOnce();
    } on ConversationsException {
      rethrow;
    } catch (e) {
      throw TokenException('the token provider failed: $e', cause: e);
    }
  }

  /// Disconnects and releases the native client. This object can't be used again.
  Future<void> shutdown() async {
    if (_closed) return;
    _closed = true;
    _refreshGeneration++;
    try {
      await guardPlatform(_platform.shutdown);
    } finally {
      if (identical(_active, this)) _active = null;
      await _subscription?.cancel();
      for (final upload in _uploads.values) {
        await upload.close();
      }
      _uploads.clear();
      await _syncChanges.close();
      await _events.close();
    }
  }

  // Conversations (api-design §5)

  Future<List<Conversation>> myConversations() =>
      _call(() async => (await _platform.myConversations()).map(Conversation.fromPlatform).toList());

  /// Throws [ConversationNotFoundException] if the conversation doesn't exist or this
  /// identity left it or was removed from it.
  Future<Conversation> getConversation(String sidOrUniqueName) =>
      _call(() async => Conversation.fromPlatform(await _platform.getConversation(sidOrUniqueName)));

  /// [attributes] is any JSON value: a Map, List, String, num, bool or null.
  Future<Conversation> createConversation({String? uniqueName, String? friendlyName, Object? attributes}) => _call(
    () async => Conversation.fromPlatform(
      await _platform.createConversation(uniqueName, friendlyName, attributes == null ? null : jsonEncode(attributes)),
    ),
  );

  Future<Conversation> join(String conversationSid) =>
      _call(() async => Conversation.fromPlatform(await _platform.join(conversationSid)));

  Future<Participant?> getParticipantByIdentity(String conversationSid, String identity) => _call(() async {
    final data = await _platform.getParticipantByIdentity(conversationSid, identity);
    return data == null ? null : Participant.fromPlatform(data);
  });

  // Messages, read state, typing, media (api-design §6)

  Future<int> getMessagesCount(String conversationSid) => _call(() => _platform.getMessagesCount(conversationSid));

  /// Up to [count] messages up to and including [index], oldest first.
  Future<List<Message>> getMessagesBefore(String conversationSid, {required int index, required int count}) => _call(
    () async => (await _platform.getMessagesBefore(conversationSid, index, count)).map(Message.fromPlatform).toList(),
  );

  /// The newest [count] messages, oldest first.
  Future<List<Message>> getLastMessages(String conversationSid, {required int count}) =>
      _call(() async => (await _platform.getLastMessages(conversationSid, count)).map(Message.fromPlatform).toList());

  /// Null until this identity has read something in the conversation; apps usually
  /// treat that as "everything is unread", not as 0.
  Future<int?> getUnreadMessagesCount(String conversationSid) =>
      _call(() => _platform.getUnreadMessagesCount(conversationSid));

  /// Returns the unread count after the change.
  Future<int?> setLastReadMessageIndex(String conversationSid, int index) =>
      _call(() => _platform.setLastReadMessageIndex(conversationSid, index));

  Future<Message> sendText(String conversationSid, String body) =>
      _call(() async => Message.fromPlatform(await _platform.sendText(conversationSid, body)));

  /// Starts sending a file. Progress and the result arrive on the returned [MediaSend].
  MediaSend sendMedia(String conversationSid, MediaUpload upload) {
    _checkOpen();
    final uploadId = 'upload-${++_uploadCount}-${DateTime.now().microsecondsSinceEpoch}';
    final progress = StreamController<int>.broadcast();
    _uploads[uploadId] = progress;
    final file = File(upload.filePath);
    final totalBytes = file.existsSync() ? file.lengthSync() : 0;
    final filename = upload.filename ?? file.uri.pathSegments.last;
    final message =
        _call(
          () async => Message.fromPlatform(
            await _platform.sendMedia(conversationSid, uploadId, upload.filePath, upload.contentType, filename),
          ),
        ).whenComplete(() {
          _uploads.remove(uploadId);
          progress.close();
        });
    return MediaSend.internal(uploadId, totalBytes, progress, message);
  }

  /// Tells the other participants this identity is typing. Call it as the user types;
  /// Twilio limits how often it's actually sent.
  Future<void> typing(String conversationSid) => _call(() => _platform.typing(conversationSid));

  /// A short-lived download link for a message's media. Fetch it right before use;
  /// don't store it.
  Future<Uri> getMediaTemporaryUrl({
    required String conversationSid,
    required int messageIndex,
    required String mediaSid,
  }) => _call(() async => Uri.parse(await _platform.getMediaTemporaryUrl(conversationSid, messageIndex, mediaSid)));

  // Push through Twilio, optional (api-design §8)

  Future<void> registerPushToken(PushToken token) =>
      _call(() => _platform.registerPushToken(platformPushTokenType(token), token.token));

  Future<void> unregisterPushToken(PushToken token) =>
      _call(() => _platform.unregisterPushToken(platformPushTokenType(token), token.token));

  // Internals

  void _checkOpen() {
    if (_closed) throw const NotConnectedException('the client was shut down');
  }

  /// async, so a closed client fails through the returned Future, never by throwing.
  Future<T> _call<T>(Future<T> Function() call) async {
    _checkOpen();
    return guardPlatform(call);
  }

  void _emit(ConversationsEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _onPlatformEvent(PlatformEvent event) {
    if (_closed) return;
    switch (event) {
      case ConnectionStateEvent(:final state):
        _connectionState = ConnectionState.values.byName(state.name);
        _emit(ConnectionStateChanged(_connectionState));
      case SyncStatusEvent(:final status):
        final syncStatus = _toSyncStatus(status)!;
        _syncStatus = syncStatus;
        _syncChanges.add(syncStatus);
        _emit(SyncStatusChanged(syncStatus));
      case TokenEvent(:final type):
        _emit(type == PlatformTokenEventType.aboutToExpire ? const TokenAboutToExpire() : const TokenExpired());
        if (_tokenProvider != null) unawaited(_autoRefresh(++_refreshGeneration));
      case ConversationAddedEvent(:final conversation):
        _emit(ConversationAdded(Conversation.fromPlatform(conversation)));
      case MessageAddedEvent(:final message, :final conversation):
        _emit(MessageAdded(Message.fromPlatform(message), Conversation.fromPlatform(conversation)));
      case MessageUpdatedEvent(:final message):
        _emit(MessageUpdated(Message.fromPlatform(message)));
      case TypingEvent(:final conversationSid, :final participant, :final started):
        final p = Participant.fromPlatform(participant);
        _emit(started ? TypingStarted(conversationSid, p) : TypingEnded(conversationSid, p));
      case UploadProgressEvent(:final uploadId, :final bytesSent):
        final progress = _uploads[uploadId];
        if (progress != null && !progress.isClosed) progress.add(bytesSent);
      case ClientErrorEvent(:final code, :final message, :final twilioCode):
        _emit(
          ClientErrorOccurred(
            exceptionFromPlatform(PlatformException(code: code, message: message, details: twilioCode)),
          ),
        );
    }
  }

  /// Retries until a refresh succeeds, the client shuts down, or a newer token event
  /// starts its own round: 2 s, 5 s, 15 s, then every 60 s.
  Future<void> _autoRefresh(int generation) async {
    for (var attempt = 0; !_closed && generation == _refreshGeneration; attempt++) {
      try {
        await _refreshOnce();
        return;
      } catch (_) {
        // Already reported as TokenRefreshFailed.
      }
      await Future<void>.delayed(tokenRefreshDelays[min(attempt, tokenRefreshDelays.length - 1)]);
    }
  }

  /// One refresh at a time: a second request while one runs waits for the same one.
  Future<void> _refreshOnce() => _refreshInFlight ??= _refresh().whenComplete(() => _refreshInFlight = null);

  Future<void> _refresh() async {
    try {
      final token = await _tokenProvider!();
      if (token.isEmpty) throw const TokenException('the token provider returned an empty token');
      await updateToken(token);
      _emit(TokenRefreshed(_tokenExpiresAt));
    } catch (e) {
      _emit(TokenRefreshFailed(e));
      rethrow;
    }
  }
}

SyncStatus? _toSyncStatus(PlatformSyncStatus? status) => status == null ? null : SyncStatus.values.byName(status.name);
