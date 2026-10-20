import 'errors.dart';
import 'models.dart';

enum ClientConnectionState { unknown, connecting, connected, disconnected, denied, error, fatalError }

enum SyncStatus { started, conversationsListCompleted, completed, failed }

/// What changed in [ConversationUpdated].
enum ConversationUpdateReason {
  /// This identity's status changed, for example it left or was removed (also see [ConversationDeleted]).
  status,

  /// This identity's last read message changed, also when it read on another device.
  lastReadMessageIndex,
  uniqueName,
  friendlyName,
  attributes,

  /// A message was added or the last message was deleted.
  lastMessage,
  notificationLevel,

  /// The conversation became active, inactive or closed.
  state,
}

/// What changed in [ParticipantUpdated].
enum ParticipantUpdateReason { lastReadMessageIndex, lastReadTimestamp, attributes }

/// Everything that happens on the client, delivered on [TwilioConversationsClient.events]
/// in the order the SDK reports it. `sealed`, so a `switch` must handle every case
/// (api-design §7).
sealed class ConversationsEvent {
  const ConversationsEvent();
}

final class ConnectionStateChanged extends ConversationsEvent {
  const ConnectionStateChanged(this.state);
  final ClientConnectionState state;
}

final class SyncStatusChanged extends ConversationsEvent {
  const SyncStatusChanged(this.status);
  final SyncStatus status;
}

/// Twilio says the token expires in about 3 minutes.
final class TokenAboutToExpire extends ConversationsEvent {
  const TokenAboutToExpire();
}

final class TokenExpired extends ConversationsEvent {
  const TokenExpired();
}

/// Automatic mode: a new token from the token provider was accepted.
final class TokenRefreshed extends ConversationsEvent {
  const TokenRefreshed(this.expiresAt);
  final DateTime? expiresAt;
}

/// Automatic mode: getting or applying a new token failed; the plugin retries.
final class TokenRefreshFailed extends ConversationsEvent {
  const TokenRefreshFailed(this.error);
  final Object error;
}

final class ConversationAdded extends ConversationsEvent {
  const ConversationAdded(this.conversation);
  final Conversation conversation;
}

/// One of this identity's conversations changed, with the conversation as it is now.
/// Use it to keep read state and unread badges current without fetching again.
final class ConversationUpdated extends ConversationsEvent {
  const ConversationUpdated(this.conversation, this.reason);
  final Conversation conversation;
  final ConversationUpdateReason reason;
}

/// This identity left or was removed from the conversation, or it was closed or deleted.
/// It's gone from `myConversations`; further calls on it fail with `ConversationNotFoundException`.
final class ConversationDeleted extends ConversationsEvent {
  const ConversationDeleted(this.conversationSid);
  final String conversationSid;
}

/// A participant changed, typically someone read messages: the basis for read receipts.
final class ParticipantUpdated extends ConversationsEvent {
  const ParticipantUpdated(this.conversationSid, this.participant, this.reason);
  final String conversationSid;
  final Participant participant;
  final ParticipantUpdateReason reason;
}

/// A message arrived in any conversation, with the conversation as it is now.
///
/// When many messages are sent at once, these can arrive out of index order (each still exactly
/// once), so place messages by [Message.index], not by arrival.
final class MessageAdded extends ConversationsEvent {
  const MessageAdded(this.message, this.conversation);
  final Message message;
  final Conversation conversation;
}

final class MessageUpdated extends ConversationsEvent {
  const MessageUpdated(this.message);
  final Message message;
}

final class TypingStarted extends ConversationsEvent {
  const TypingStarted(this.conversationSid, this.participant);
  final String conversationSid;
  final Participant participant;
}

final class TypingEnded extends ConversationsEvent {
  const TypingEnded(this.conversationSid, this.participant);
  final String conversationSid;
  final Participant participant;
}

/// An error the SDK reported on its own, outside any call.
final class ClientErrorOccurred extends ConversationsEvent {
  const ClientErrorOccurred(this.error);
  final ConversationsException error;
}
