# flutter_twilio_conversations_client

An **unofficial** Flutter plugin for [Twilio Conversations](https://www.twilio.com/docs/conversations-classic), wrapping Twilio's native iOS and Android Conversations SDKs behind a typed Dart API.

> **Status: in development, not published.** The first-release API works on iOS and Android and is tested on real devices. Push payload parsing and the example app are still to come. See [docs/](docs/) for the design.

## Usage

```dart
final client = await TwilioConversationsClient.connect(
  token: await myBackend.fetchTwilioToken(),
  tokenProvider: myBackend.fetchTwilioToken, // optional: refreshes the token by itself
);
await client.waitUntilSynced();

client.events.listen((event) => switch (event) {
  MessageAdded(:final message) => print('${message.author}: ${message.body}'),
  _ => null,
});

final conversation = await client.getConversation('my-conversation');
await client.sendText(conversation.sid, 'Hello');

final upload = client.sendMedia(conversation.sid, MediaUpload(filePath: path, contentType: 'image/jpeg'));
upload.bytesSent.listen((sent) => print('$sent of ${upload.totalBytes} bytes'));
await upload.message;

await client.shutdown(); // on logout
```

Access tokens come from your own backend: minting one needs the Twilio API key secret, which must never ship in an app.

## Goals

- Wrap the official native SDKs (iOS `TwilioConversationsClient` 4.x, Android `conversations-android` 6.x) instead of reimplementing Twilio's realtime protocol.
- Type-safe Dart ↔ native communication generated with [Pigeon](https://pub.dev/packages/pigeon), with no `Map`/`dynamic` results.
- General-purpose: no app-specific business logic, no UI. Access tokens come from your own backend through a token provider callback.
- Realtime events (messages, typing, read state, connection, token expiry) exposed as Dart streams.
- Media attachments sent by file path, with upload progress.
- Optional Twilio push registration (APNs / FCM) for apps that use Twilio's native push.
- iOS support through Swift Package Manager (see [technical parameters](docs/technical-parameters.md) for why not CocoaPods).

## Requirements

- Flutter 3.44 or later (Dart 3.12+)
- iOS 15.0+, with Swift Package Manager enabled
- Android 7.0+ (API 24)

## Disclaimer

This project is not affiliated with, endorsed by, or supported by Twilio Inc. "Twilio" is a trademark of Twilio Inc.
