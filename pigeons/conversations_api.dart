// The native contract. Apps never see these types: the public API in lib/
// wraps them (docs/api-design.md §2, §12).
//
// Regenerate after any change:
//   dart run pigeon --input pigeons/conversations_api.dart

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/conversations_api.g.dart',
    dartPackageName: 'flutter_twilio_conversations_client',
    kotlinOut:
        'android/src/main/kotlin/com/identity_solutions/twilio_conversations/ConversationsApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.identity_solutions.twilio_conversations'),
    swiftOut:
        'ios/flutter_twilio_conversations_client/Sources/flutter_twilio_conversations_client/ConversationsApi.g.swift',
  ),
)
// Errors: native code fails a call with FlutterError(code, message, details).
// `code` is one of the values below; `details` is Twilio's numeric error code
// when there is one. The Dart layer maps each code to a ConversationsException.
//   not_connected | already_connected | conversation_not_found | token |
//   media_upload | twilio
//
// Dates cross as epoch milliseconds (UTC). Attributes cross as JSON strings and
// are decoded once in Dart (api-design §9).
enum PlatformConnectionState {
  unknown,
  connecting,
  connected,
  disconnected,
  denied,
  error,
  fatalError,
}

enum PlatformSyncStatus { started, conversationsListCompleted, completed, failed }

enum PlatformLogLevel { silent, fatal, error, warning, info, debug, trace }

enum PlatformConversationStatus { joined, notParticipating }

enum PlatformMediaCategory { media, body, history }

enum PlatformPushTokenType { apns, fcm }

enum PlatformTokenEventType { aboutToExpire, expired }

class ClientData {
  ClientData({required this.myIdentity, required this.connectionState, required this.syncStatus});

  final String myIdentity;
  final PlatformConnectionState connectionState;
  final PlatformSyncStatus? syncStatus;
}

class ConversationData {
  ConversationData({
    required this.sid,
    required this.status,
    this.uniqueName,
    this.friendlyName,
    this.attributesJson,
    this.lastMessageIndex,
    this.lastMessageDateMillis,
    this.lastReadMessageIndex,
    this.dateCreatedMillis,
    this.createdBy,
  });

  final String sid;
  final PlatformConversationStatus status;
  final String? uniqueName;
  final String? friendlyName;
  final String? attributesJson;
  final int? lastMessageIndex;
  final int? lastMessageDateMillis;
  final int? lastReadMessageIndex;
  final int? dateCreatedMillis;
  final String? createdBy;
}

class MediaData {
  MediaData({
    required this.sid,
    required this.category,
    required this.contentType,
    required this.size,
    this.filename,
  });

  final String sid;
  final PlatformMediaCategory category;
  final String contentType;
  final int size;
  final String? filename;
}

class MessageData {
  MessageData({
    required this.conversationSid,
    required this.sid,
    required this.index,
    required this.media,
    this.author,
    this.body,
    this.dateCreatedMillis,
    this.attributesJson,
    this.participantSid,
  });

  final String conversationSid;
  final String sid;
  final int index;
  final List<MediaData> media;
  final String? author;
  final String? body;
  final int? dateCreatedMillis;
  final String? attributesJson;
  final String? participantSid;
}

class ParticipantData {
  ParticipantData({
    required this.sid,
    this.identity,
    this.dateCreatedMillis,
    this.lastReadMessageIndex,
    this.attributesJson,
  });

  final String sid;
  final String? identity;
  final int? dateCreatedMillis;
  final int? lastReadMessageIndex;
  final String? attributesJson;
}

/// Calls from Dart into native code. Everything that waits on Twilio is @async.
@HostApi()
abstract class ConversationsHostApi {
  // Client (api-design §3, §4)
  @async
  ClientData connect(String token, String region);
  @async
  void updateToken(String token);
  @async
  void shutdown();
  void setLogLevel(PlatformLogLevel level);

  // Conversations (§5)
  @async
  List<ConversationData> myConversations();
  @async
  ConversationData getConversation(String sidOrUniqueName);
  @async
  ConversationData createConversation(
    String? uniqueName,
    String? friendlyName,
    String? attributesJson,
  );
  @async
  ConversationData join(String conversationSid);
  @async
  ParticipantData? getParticipantByIdentity(String conversationSid, String identity);

  // Messages and read state (§6)
  @async
  int getMessagesCount(String conversationSid);
  @async
  List<MessageData> getMessagesBefore(String conversationSid, int index, int count);
  @async
  List<MessageData> getLastMessages(String conversationSid, int count);
  @async
  int? getUnreadMessagesCount(String conversationSid);
  @async
  int? setLastReadMessageIndex(String conversationSid, int index);
  @async
  MessageData sendText(String conversationSid, String body);

  /// Progress arrives as [UploadProgressEvent]s carrying [uploadId].
  @async
  MessageData sendMedia(
    String conversationSid,
    String uploadId,
    String filePath,
    String contentType,
    String? filename,
  );
  @async
  void typing(String conversationSid);
  @async
  String getMediaTemporaryUrl(String conversationSid, int messageIndex, String mediaSid);

  // Push through Twilio, optional (§8)
  @async
  void registerPushToken(PlatformPushTokenType type, String token);
  @async
  void unregisterPushToken(PlatformPushTokenType type, String token);
}

/// Everything native code reports on its own (api-design §7).
sealed class PlatformEvent {}

class ConnectionStateEvent extends PlatformEvent {
  ConnectionStateEvent(this.state);
  final PlatformConnectionState state;
}

class SyncStatusEvent extends PlatformEvent {
  SyncStatusEvent(this.status);
  final PlatformSyncStatus status;
}

class TokenEvent extends PlatformEvent {
  TokenEvent(this.type);
  final PlatformTokenEventType type;
}

class ConversationAddedEvent extends PlatformEvent {
  ConversationAddedEvent(this.conversation);
  final ConversationData conversation;
}

class MessageAddedEvent extends PlatformEvent {
  MessageAddedEvent(this.message, this.conversation);
  final MessageData message;
  final ConversationData conversation;
}

class MessageUpdatedEvent extends PlatformEvent {
  MessageUpdatedEvent(this.message);
  final MessageData message;
}

class TypingEvent extends PlatformEvent {
  TypingEvent(this.conversationSid, this.participant, this.started);
  final String conversationSid;
  final ParticipantData participant;
  final bool started;
}

class UploadProgressEvent extends PlatformEvent {
  UploadProgressEvent(this.uploadId, this.bytesSent, this.totalBytes);
  final String uploadId;
  final int bytesSent;
  final int totalBytes;
}

class ClientErrorEvent extends PlatformEvent {
  ClientErrorEvent(this.code, this.message, this.twilioCode);
  final String code;
  final String message;
  final int? twilioCode;
}

@EventChannelApi()
abstract class ConversationsEventApi {
  PlatformEvent events();
}
