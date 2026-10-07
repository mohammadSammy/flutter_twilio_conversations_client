import '../generated/conversations_api.g.dart';
import '../generated/conversations_api.g.dart' as pigeon show events;
import 'conversations_platform.dart';

/// The real platform: the Pigeon-generated host API already has every call, so only
/// the event stream is added here.
final class PigeonConversationsPlatform extends ConversationsHostApi implements ConversationsPlatform {
  @override
  Stream<PlatformEvent> get events => pigeon.events();
}
