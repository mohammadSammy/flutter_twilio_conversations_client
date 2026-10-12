# Proof-of-concept results

The Must criteria from [poc-success-criteria.md](poc-success-criteria.md), measured on 2026-10-11 and 2026-10-12. Should criteria come later; see [Not yet tested](#not-yet-tested).

## Setup

- **Phones:** iPhone XS on iOS 18.7 and Samsung Galaxy S23 Ultra (SM-S918B) on Android 16, both on Wi-Fi.
- **Software:** Flutter 3.47.6, Twilio iOS SDK 4.0.9 and Android SDK 6.2.1, against a trial Twilio account.
- **Builds:**
  - iOS: profile builds.
  - Android:
    - Debug builds on 2026-10-11.
    - On 2026-10-12, every Android run used a release build with R8. Those runs count towards A2.
- **How tests run:** the tests live in `example/integration_test/` (`poc_single_test.dart` and `poc_pair_test.dart`). Each result is printed as a `POC {json}` line, and the numbers below come from those lines.
- **Two-phone tests:** each phone took the receiving role once.

## Outcome

**Every Must criterion that can be tested on the phones passes on both platforms.** **The exception is B3** (automatic refresh with 3-minute tokens), which fails on both platforms; see [B3](#b3-token-refresh-with-short-tokens). A1 and G3 depend on CI runs on Flutter 3.44 and stable, which haven't happened yet.

## Results

| # | Criterion | iOS | Android | Notes |
|---|---|---|---|---|
| A1 | Builds on both platforms | Pass on 3.47.6 | Pass on 3.47.6 | Flutter 3.44 and the latest stable are covered by the CI `build` job, which hasn't run yet |
| A2 | Release build works | n/a | **Pass** | A release build with R8 ran every one-phone, two-phone and real-world scenario without a crash |
| A3 | App size cost | **+10.7 MB** app bundle, **+2.4 MB** zipped IPA | **+6.0 MB** arm64, **+3.6 MB** armv7, **+4.8 MB** x86_64 | Measured with a new `flutter create` app built with and without the plugin. The iOS bundle grows from 14.2 to 24.9 MB, and the zipped IPA from 6.2 to 8.6 MB |
| B1 | Connects and syncs | **Pass:** median 3.3 s | **Pass:** median 3.7 s | Identity with 20 conversations. Raw times: iOS 3346, 2617, 3124, 3354, 3259 ms; Android 3654, 3490, 3958, 4301, 3328 ms. All five connects ran in one app process |
| B2 | Bad token | Pass | Pass | Both a malformed and an expired token raise `TokenException` (Twilio code 5, "UNAUTHORIZED") |
| B3 | Automatic refresh | **Fail** | **Fail** | 3-minute tokens for 15 minutes, sending a message every 30 s. All 30 messages were sent, but the token ran out about every 4 minutes and the connection went `denied`, then `disconnected`, then reconnected. iOS also refreshed about 50 times in the first 10 s. See [B3](#b3-token-refresh-with-short-tokens) |
| B4 | Manual mode | Pass | Pass | `TokenAboutToExpire`, then `TokenExpired` about 56 s after expiry. `updateToken` reconnects |
| B6 | Logout and login | Pass | Pass | A second `connect` raises `ClientAlreadyConnectedException`. Nothing from the first identity leaks |
| C1 | Text both ways | **Pass:** median 440 ms, 95th percentile 524 ms | **Pass:** median 454 ms, 95th percentile 493 ms | 20 messages, half of each round trip. Earlier runs gave 411–436 ms |
| C2 | Events for every conversation | Pass | Pass | Needed a fix on Android; see below |
| C3 | Order, no duplicates | Pass | Pass | All 50 arrive exactly once, and history returns index order. **Arrival order is shuffled** on both platforms; see below |
| C4 | History paging | Pass: first page in 444 ms | Pass: first page in 642–962 ms | 520 messages, no gaps and no duplicates |
| C6 | Read state | Pass | Pass | Unread count is `null` before anything is read, and 510 after reading up to index 9 |
| C7 | Removed from a conversation | Pass | Pass | `ConversationNotFoundException`, Twilio code 50430 |
| D1 | Image, video, PDF | Pass | Pass | 50 MB MP4 took 338 s on iOS and 31–272 s on Android, depending on the Wi-Fi. Progress only increases and ends at the file size |
| D2 | No memory spike | Pass: +1.7 MB | Pass: +2.0 to 20.9 MB | Peak memory growth during the 50 MB upload. The limit is 30 MB |
| D4 | Bad file | Pass | Pass | `MediaUploadException` within 10 ms |
| D5 | Downloading | Pass | Pass | A fresh URL still downloads after 60 s |
| E1 | Network drop | Pass | Pass | About 90 s in airplane mode. All three messages sent meanwhile arrived exactly once. The drop is reported as `fatalError` on iOS and `error` on Android, and both recover on their own |
| E2 | Background and back | Pass | Pass | 10.3 minutes in the background. iOS reconnected 0.6 s after reopening, and the messages showed after 1.0 s. On Android the connection never dropped, and the messages showed after 0.17 s |
| E3 | Killed and relaunched | Pass | Pass | After a forced kill, connect and sync took 2.3 s on iOS and 3.6 s on Android, both including the token fetch. The conversation and the last message were there |
| G1 | API matches the design | Pass | Pass | Needed a fix; see below |
| G2 | Logic tested without devices | Pass | Pass | 25 Dart unit tests with a fake platform cover token refresh, error mapping, events and uploads |
| G3 | Clean CI | Pending | Pending | `flutter analyze`, the format check and the unit tests are clean locally. The CI workflow hasn't run yet |
| G4 | Verification list done | Pass | Pass | Every item in [api-design.md](api-design.md) §15 is checked |

## B3: token refresh with short tokens

The client refreshes when Twilio sends `TokenAboutToExpire`, and Twilio sends that warning 3 minutes before expiry. A 3-minute token is "about to expire" as soon as it's issued:

- **iOS** warns again right after each refresh, which gave about 50 refreshes in 10 s.
- **Both platforms** then had nothing to trigger a refresh before the token expired. The refresh came only after `TokenExpired`, about 56 s too late, so the connection dropped every cycle.

Raw refresh times in seconds:
- iOS: 50 refreshes between 3 and 13, then bursts at 253–256, 496–500 and 740–744.
- Android: 240, 243, 482, 485, 724 and 726.

With 1-hour tokens the warning arrives at 57 minutes, and this doesn't happen. The first app to use the plugin gets tokens of about an hour, so B3 is left as a known limit for now. The proposed fix: the client schedules its own refresh from the token's expiry, at most 3 minutes ahead and a quarter of the lifetime ahead for short tokens, and uses Twilio's warning only as a fallback.

## Twilio error codes recorded

These codes are the same on both platforms:

| Situation | Twilio code | Plugin exception |
|---|---|---|
| Malformed or expired token on connect | 5, "UNAUTHORIZED" | `TokenException` |
| Missing conversation | 50350 | `ConversationNotFoundException` |
| Left or removed from the conversation | 50430 | `ConversationNotFoundException` |
| Media upload failed after losing the network | 0 (Android: `MediaUploadError`, empty message) | `MediaUploadException` |

## Fixes found by testing

- **Android missed events in unopened conversations after a reconnect or relaunch (C2).**
  - Cause: the Twilio SDK restores conversations from its local cache without calling `onConversationAdded`, so the plugin never attached a listener.
  - Fix: the plugin now attaches a listener to every conversation when the client is created and again when sync completes.
- **Bad tokens surfaced as a plain `TwilioException` (B2).** Code 5 "UNAUTHORIZED" now maps to `TokenException`.
- **Pigeon types were visible to apps (G1).** The four `fromPlatform` factories took generated types. They are now internal functions that the package's public export hides.
- **Removed participants surfaced as `TwilioException` (C7).** Code 50430 now maps to `ConversationNotFoundException`.
- **Upload progress was too chatty, or overshot the file size.**
  - Progress is now limited to about 100 events per upload.
  - Android's count goes a little past the file size, so Dart caps it at the total.
- **Android error messages could be empty (seen on a failed media upload).** They now fall back to Twilio's description.
- **Files over 150 MB uploaded in full and then failed (§15).** `sendMedia` now refuses them before uploading, using Twilio's documented limit.

## Things apps need to know

- **Burst order.** When many messages are sent at once, `MessageAdded` can arrive out of index order on both platforms, up to about 25 places late. Every message still arrives exactly once. Normal chatting doesn't show this. Apps should place messages by `message.index`.
- **The connection state after a drop.** iOS reports a network drop as `fatalError` and Android as `error`, but both reconnect on their own. Neither state means the client is finished.
- **Android stops networking in the background.** A phone call, the screen turning off, or the app going to the background can cut the app's network:
  - an upload in progress then fails with `MediaUploadException`;
  - the client reconnects when the app comes back.

## Not yet tested

Should criteria:
- **B5, C5 and C8:** tested and passing on both platforms.
- **D3** (upload outlives the screen).
- **E4** (soak test).
- **F1–F3** (push):
  - F1 needs push credentials on the Twilio service, and a paid Apple team for APNs.
  - F2 and F3 pass in unit tests and in `public_api_test`.
- **G5** (adopting the plugin from the README alone).

Also not tested:
- **The Android 7.0 emulator and the iOS simulator** from the test setup. Only the two physical phones were used.
- **A real push payload,** to confirm `TwilioPushPayload` (§15).
