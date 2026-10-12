# AGENTS.md

A general-purpose Flutter plugin wrapping Twilio's native Conversations SDKs (iOS 4.x, Android 6.x) behind a typed Dart API, bridged with Pigeon. Not published yet.

## Rules

- General-purpose only: no app-specific business logic, names or examples. Use generic examples such as `myBackend.fetchTwilioToken`.
- Never commit credentials. Test credentials live in the git-ignored `tool/twilio-test.env`.
- Commit messages: `add: …`, lower case, one line.

## Docs

| File | What |
|---|---|
| [docs/api-design.md](docs/api-design.md) | The public API and the reasons behind it |
| [docs/technical-parameters.md](docs/technical-parameters.md) | Pinned versions (Flutter, Twilio SDKs, Pigeon), platform minimums, why Swift Package Manager only |
| [docs/poc-success-criteria.md](docs/poc-success-criteria.md) | Criteria A1–G, tested on real devices |
| [docs/poc-results.md](docs/poc-results.md) | Measured results for the Must criteria, Twilio error codes, fixes found by testing |
| [example/README.md](example/README.md) | The example app as the test harness: setup and which control checks which criterion |

## Layout

- `pigeons/conversations_api.dart`: the Dart ↔ native contract. Regenerate with `dart run pigeon --input pigeons/conversations_api.dart`; never edit `lib/src/generated` or the generated native files by hand.
- `lib/src/`: the public API.
  - `client.dart`: `TwilioConversationsClient`. It handles connect, a second connect being refused, sync, token refresh with backoff, and media uploads.
  - `errors.dart`: native error codes to Dart exceptions. Twilio codes join a specific exception only after they have been seen on a real device.
  - `models.dart`, `events.dart`, `media.dart`, `push.dart`, `push_payload.dart`, `token.dart`.
  - `platform/`: a platform interface, and its Pigeon implementation.
- `ios/flutter_twilio_conversations_client/Sources/…`: `ConversationsHostApiImpl.swift`, `ConversationsMapping.swift`.
- `android/src/main/kotlin/com/identity_solutions/twilio_conversations/`: `ConversationsHostApiImpl.kt`, `ConversationsMapping.kt`. Keep `android/consumer-rules.pro`; release builds with R8 need it.
- `example/`: the test harness app, plus `integration_test/` device tests.
- `tool/`:
  - `test_token.py`: makes access tokens.
  - `token_server.py`: development token server on port 8787.
  - `twilio_rest.py`: REST setup for the two-phone and removed-participant tests.

## Checks

These are the same checks CI runs (`.github/workflows/`):

```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib/src/*.dart lib/src/platform test example/lib example/integration_test lib/flutter_twilio_conversations_client.dart
flutter test
```

- Line width is 120 (`analysis_options.yaml`).
- Don't run `dart format lib`; it reformats the generated files.

## Device tests

Device tests need a Twilio test account (see `example/README.md`) and a real phone:

- `native_api_test.dart`: the generated bridge, called directly.
- `public_api_test.dart`: the public API, used as an app uses it.
- `harness_smoke_test.dart`: the example app's screens, end to end.
- `poc_single_test.dart`: the one-phone criteria. `--dart-define=ONLY=B4,D1` runs a subset; B3, D3, E1, E2 and E3 (long or hands-on) run only when named.
- `poc_pair_test.dart`: the two-phone criteria (C1, C2, C3, C5).
  1. Run `python3 tool/twilio_rest.py pair <id>` first.
  2. Start the responder (`ROLE=responder`), then the measurer (`ROLE=measurer`), with the same `PAIR`.

Every proof-of-concept result is printed as a `POC {json}` line.
