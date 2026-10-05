# flutter_twilio_conversations_client

An **unofficial** Flutter plugin for [Twilio Conversations](https://www.twilio.com/docs/conversations-classic), wrapping Twilio's native iOS and Android Conversations SDKs behind a typed Dart API.

> **Status: in development.** The plugin scaffold builds on iOS and Android; the API isn't implemented yet. See [docs/](docs/) for the design.

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
