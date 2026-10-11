import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_twilio_conversations_client/flutter_twilio_conversations_client.dart';

// Payload shapes follow the keys Twilio's own SDKs read (JavaScript SDK 3.0.1,
// Android SDK 6.2.1): numbers arrive as strings in FCM data and as numbers on APNs.
void main() {
  test('FCM data from firebase_messaging (RemoteMessage.data)', () {
    final push = TwilioPushPayload.tryParse({
      'twi_message_type': 'twilio.conversations.new_message',
      'twi_title': 'Team',
      'twi_body': 'alice: hello',
      'conversation_sid': 'CH1',
      'conversation_title': 'Team',
      'message_sid': 'IM1',
      'message_index': '42',
      'author': 'alice',
      'media_count': '2',
    })!;
    expect(push.type, TwilioPushType.newMessage);
    expect(push.conversationSid, 'CH1');
    expect(push.conversationTitle, 'Team');
    expect(push.messageSid, 'IM1');
    expect(push.messageIndex, 42);
    expect(push.author, 'alice');
    expect(push.title, 'Team');
    expect(push.body, 'alice: hello');
    expect(push.mediaCount, 2);
  });

  test('a whole FCM message with the fields under data', () {
    final push = TwilioPushPayload.tryParse({
      'data': {'twi_message_type': 'twilio.conversations.added_to_conversation', 'conversation_sid': 'CH2'},
    })!;
    expect(push.type, TwilioPushType.addedToConversation);
    expect(push.conversationSid, 'CH2');
    expect(push.messageIndex, isNull);
    expect(push.mediaCount, 0);
  });

  test('APNs payload with an alert dictionary', () {
    final push = TwilioPushPayload.tryParse({
      'aps': {
        'alert': {'title': 'Team', 'body': 'alice: hello'},
        'badge': 3,
      },
      'twi_message_type': 'twilio.conversations.new_message',
      'conversation_sid': 'CH1',
      'message_index': 7,
    })!;
    expect(push.messageIndex, 7);
    expect(push.title, 'Team');
    expect(push.body, 'alice: hello');
  });

  test('APNs payload with a plain alert string', () {
    final push = TwilioPushPayload.tryParse({
      'aps': {'alert': 'You were removed from Team'},
      'twi_message_type': 'twilio.conversations.removed_from_conversation',
      'conversation_sid': 'CH3',
    })!;
    expect(push.type, TwilioPushType.removedFromConversation);
    expect(push.body, 'You were removed from Team');
    expect(push.title, isNull);
  });

  test('parses in a separate isolate, as in a background message handler (F2)', () async {
    final sid = await Isolate.run(
      () => TwilioPushPayload.tryParse({
        'twi_message_type': 'twilio.conversations.new_message',
        'conversation_sid': 'CH9',
      })?.conversationSid,
    );
    expect(sid, 'CH9');
  });

  test('anything else is not a Twilio push', () {
    expect(TwilioPushPayload.tryParse({'title': 'Sale', 'body': '50% off'}), isNull);
    expect(TwilioPushPayload.tryParse({'twi_message_type': 'something.else', 'conversation_sid': 'CH1'}), isNull);
    expect(TwilioPushPayload.tryParse({'twi_message_type': 'twilio.conversations.new_message'}), isNull);
    expect(TwilioPushPayload.tryParse({}), isNull);
  });
}
