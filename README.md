# flutter_twilio_conversations_client

An **unofficial** Flutter plugin for [Twilio Conversations](https://www.twilio.com/docs/conversations-classic), wrapping Twilio's native iOS and Android Conversations SDKs behind a typed Dart API.

> **Status: planning.** No code has been written yet; the API and architecture are still being designed.

## Goals

- Wrap the official native SDKs (iOS `TwilioConversationsClient` 4.x, Android `conversations-android` 6.x) instead of reimplementing Twilio's realtime protocol.
- Type-safe Dart ↔ native communication generated with [Pigeon](https://pub.dev/packages/pigeon), with no `Map`/`dynamic` results.
- General-purpose: no app-specific business logic, no UI. Access tokens come from your own backend through a token provider callback.
- Realtime events (messages, typing, read state, connection, token expiry) exposed as Dart streams.
- Media attachments sent by file path, with upload progress.
- Optional Twilio push registration (APNs / FCM) for apps that use Twilio's native push.
- iOS support through both Swift Package Manager and CocoaPods.

## Disclaimer

This project is not affiliated with, endorsed by, or supported by Twilio Inc. "Twilio" is a trademark of Twilio Inc.
