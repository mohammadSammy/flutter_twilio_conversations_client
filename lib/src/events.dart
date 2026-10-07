import 'errors.dart';
import 'models.dart';

enum ConnectionState { unknown, connecting, connected, disconnected, denied, error, fatalError }

enum SyncStatus { started, conversationsListCompleted, completed, failed }

/// Everything that happens on the client, delivered on [TwilioConversationsClient.events]
/// in the order the SDK reports it. `sealed`, so a `switch` must handle every case
/// (api-design §7).
sealed class ConversationsEvent {
  const ConversationsEvent();
}

final class ConnectionStateChanged extends ConversationsEvent {
  const ConnectionStateChanged(this.state);
  final ConnectionState state;
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

/// A message arrived in any conversation, with the conversation as it is now.
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
