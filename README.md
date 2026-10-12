# flutter_twilio_conversations_client

An **unofficial** Flutter plugin for [Twilio Conversations](https://www.twilio.com/docs/conversations-classic), wrapping Twilio's native iOS and Android Conversations SDKs behind a typed Dart API.

> **Status: 0.1.1, not on pub.dev yet.** The first-release API works on iOS and Android. It is tested on real phones against the proof-of-concept criteria; see [the results](docs/poc-results.md).

## Installation

Until it's on pub.dev, depend on it from GitHub, pinned to a tag or commit:

```yaml
dependencies:
  flutter_twilio_conversations_client:
    git:
      url: https://github.com/mohammadSammy/flutter_twilio_conversations_client.git
      ref: v0.1.1
```

iOS needs Swift Package Manager. Twilio stopped publishing its SDK through CocoaPods, so this plugin supports Swift Package Manager only. Turn it on for your app in `pubspec.yaml`:

```yaml
flutter:
  config:
    enable-swift-package-manager: true
```

Nothing else needs setting up. Android release builds get their R8 keep rules from the plugin.

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

### Push through Twilio (optional)

Only if Twilio sends your pushes. Register after connecting; the plugin waits for sync itself:

```dart
await client.registerPushToken(Platform.isIOS ? PushToken.apns(apnsHex) : PushToken.fcm(fcmToken));
```

In a push handler, even a background one where no client exists:

```dart
final push = TwilioPushPayload.tryParse(message.data);   // null if it isn't from Twilio
if (push?.type == TwilioPushType.newMessage) showConversation(push!.conversationSid);
```

The Twilio Conversations service needs an APNs and/or FCM credential with push turned on, and the access token's chat grant must name that credential.

## Good to know

- **Token lifetime:** with a `tokenProvider`, the client renews the token when Twilio warns it's about to expire, which is 3 minutes before. Use tokens that last well over 5 minutes; an hour is typical. Shorter tokens are renewed too late, and the connection drops at each expiry.
- **Place messages by `index`:** when many messages are sent at once, `MessageAdded` events can arrive out of index order. Each still arrives exactly once. `getLastMessages` and `getMessagesBefore` always return index order.
- **After a network drop,** the connection state can be `error` (Android) or `fatalError` (iOS). The client still reconnects on its own when the network returns.
- **Android can cut a background app's network,** for example during a phone call or with the screen off. An upload in progress then fails with `MediaUploadException`, and the client reconnects when the app comes back.
- **Errors** are `ConversationsException` subclasses: `TokenException`, `ConversationNotFoundException` (missing, left or removed), `MediaUploadException`, `NotConnectedException`, `ClientAlreadyConnectedException`, or `TwilioException` with Twilio's own code.
- **Media files** go by path and are streamed natively, so memory stays flat. Files over Twilio's 150 MB limit fail right away. On iOS an upload keeps going for about 30 s after the user leaves the app.
- **Testing your app:** `TwilioConversationsClient` and `MediaSend` are interface classes, so your tests can implement them with a fake or a mocking package.

## Example

[`example/lib/main.dart`](example/lib/main.dart) is a minimal chat screen. The example folder also holds the test harness and the device tests; see [example/README.md](example/README.md).

## Documentation

- [API design](docs/api-design.md): the public API and the reasons behind it
- [Technical parameters](docs/technical-parameters.md): pinned versions and platform minimums
- [Proof-of-concept criteria](docs/poc-success-criteria.md) and [results](docs/poc-results.md)
- [CHANGELOG](CHANGELOG.md)

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

## License

No license has been chosen yet. Until one is added, the usual copyright rules apply.

## Disclaimer

This project is not affiliated with, endorsed by, or supported by Twilio Inc. "Twilio" is a trademark of Twilio Inc.
