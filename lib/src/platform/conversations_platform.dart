import '../generated/conversations_api.g.dart';
import 'pigeon_platform.dart';

/// What a platform must provide: the native calls and the native event stream.
///
/// The client talks only to this interface, so unit tests can swap in a fake and
/// check token refresh, error mapping and events without a device (api-design §2).
abstract interface class ConversationsPlatform {
  /// The platform the client uses. Tests replace it with a fake.
  static ConversationsPlatform instance = PigeonConversationsPlatform();

  /// Everything native code reports on its own. Listen before calling [connect],
  /// so the first connection and sync events aren't missed.
  Stream<PlatformEvent> get events;

  Future<ClientData> connect(String token, String region);
  Future<void> updateToken(String token);
  Future<void> shutdown();
  Future<void> setLogLevel(PlatformLogLevel level);

  Future<List<ConversationData>> myConversations();
  Future<ConversationData> getConversation(String sidOrUniqueName);
  Future<ConversationData> createConversation(String? uniqueName, String? friendlyName, String? attributesJson);
  Future<ConversationData> join(String conversationSid);
  Future<ParticipantData?> getParticipantByIdentity(String conversationSid, String identity);

  Future<int> getMessagesCount(String conversationSid);
  Future<List<MessageData>> getMessagesBefore(String conversationSid, int index, int count);
  Future<List<MessageData>> getLastMessages(String conversationSid, int count);
  Future<int?> getUnreadMessagesCount(String conversationSid);
  Future<int?> setLastReadMessageIndex(String conversationSid, int index);
  Future<MessageData> sendText(String conversationSid, String body);
  Future<MessageData> sendMedia(
    String conversationSid,
    String uploadId,
    String filePath,
    String contentType,
    String? filename,
  );
  Future<void> typing(String conversationSid);
  Future<String> getMediaTemporaryUrl(String conversationSid, int messageIndex, String mediaSid);

  Future<void> registerPushToken(PlatformPushTokenType type, String token);
  Future<void> unregisterPushToken(PlatformPushTokenType type, String token);
}
