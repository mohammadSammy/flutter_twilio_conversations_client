/// What a push sent by Twilio Conversations is about (api-design §8).
enum TwilioPushType { newMessage, addedToConversation, removedFromConversation }

/// A push notification sent by Twilio Conversations, read from its raw data.
///
/// Pure Dart with no client and no plugin call, so it works in a background message
/// handler (a background isolate), where no client exists.
///
/// Key names are the ones Twilio's own SDKs read: `twi_message_type`,
/// `conversation_sid`, `message_index` and so on (Twilio's JavaScript SDK 3.0.1 and
/// Android SDK 6.2.1).
final class TwilioPushPayload {
  const TwilioPushPayload({
    required this.type,
    required this.conversationSid,
    this.conversationTitle,
    this.messageSid,
    this.messageIndex,
    this.author,
    this.title,
    this.body,
    this.mediaCount = 0,
  });

  /// Reads a push's data. Null when it isn't a Twilio Conversations push.
  ///
  /// Accepts what a Flutter app is handed:
  /// - Android: `RemoteMessage.data` from firebase_messaging, or a whole FCM message
  ///   with the fields under `data`.
  /// - iOS: the APNs payload (`userInfo`), with an `aps` dictionary.
  static TwilioPushPayload? tryParse(Map<String, dynamic> data) {
    final fields = data['twi_message_type'] == null && data['data'] is Map ? _stringKeys(data['data'] as Map) : data;
    final type = switch (fields['twi_message_type']) {
      'twilio.conversations.new_message' => TwilioPushType.newMessage,
      'twilio.conversations.added_to_conversation' => TwilioPushType.addedToConversation,
      'twilio.conversations.removed_from_conversation' => TwilioPushType.removedFromConversation,
      _ => null,
    };
    final conversationSid = _string(fields['conversation_sid']);
    if (type == null || conversationSid == null) return null;

    // APNs keeps the text in aps.alert, a string or {title, body}; FCM in twi_title/twi_body.
    final aps = fields['aps'];
    final alert = aps is Map ? aps['alert'] : null;
    return TwilioPushPayload(
      type: type,
      conversationSid: conversationSid,
      conversationTitle: _string(fields['conversation_title']),
      messageSid: _string(fields['message_sid']),
      messageIndex: _int(fields['message_index']),
      author: _string(fields['author']),
      title: alert is Map ? _string(alert['title']) : _string(fields['twi_title']),
      body: alert is Map ? _string(alert['body']) : _string(alert) ?? _string(fields['twi_body']),
      mediaCount: _int(fields['media_count']) ?? 0,
    );
  }

  final TwilioPushType type;
  final String conversationSid;
  final String? conversationTitle;

  /// Set for [TwilioPushType.newMessage].
  final String? messageSid;
  final int? messageIndex;

  /// The sender's identity, when Twilio includes it.
  final String? author;

  /// The notification text Twilio built from the service's push templates.
  final String? title;
  final String? body;
  final int mediaCount;

  @override
  String toString() => 'TwilioPushPayload(${type.name}, $conversationSid, #${messageIndex ?? '-'})';
}

Map<String, dynamic> _stringKeys(Map map) => {for (final e in map.entries) '${e.key}': e.value};

String? _string(Object? value) => value is String && value.isNotEmpty ? value : null;

/// Twilio sends numbers as JSON numbers on APNs and as strings in FCM data.
int? _int(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};
