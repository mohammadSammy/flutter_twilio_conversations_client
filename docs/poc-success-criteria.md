# Proof-of-concept success criteria

The tests that decide whether the first version (`0.1.0`) works. They were agreed before building, so "done" is measured, not argued.

Each criterion is pass/fail.
- **Must:** the proof of concept fails if this fails.
- **Should:** failing it adds a backlog item and doesn't block.

## Test setup

- **Devices:** one physical iPhone, one physical Android phone, an Android 7.0 emulator (API 24, the minimum) and an iOS simulator. Push and some background behaviour only work on physical devices.
- **Builds:** debug and release. Android release builds use R8/obfuscation, which is where missing keep rules show up.
- **Accounts:** three test identities that share at least one conversation, plus a conversation with 500+ messages for the paging tests.
- **Measuring delay:** the example app has an *echo mode*: the receiving device replies automatically to every message, and the sender halves the round-trip time. Both timestamps come from the same clock, so device clocks being out of sync doesn't matter.
- **Medians and percentiles** are taken over the stated number of runs. Record the raw numbers, not just pass/fail.

## A. Building

| # | Criterion | Pass when | Priority |
|---|---|---|---|
| A1 | Builds on both platforms | The example app runs on iOS and Android, on Flutter 3.44 and the latest stable, with no native setup beyond the README | Must |
| A2 | Android release build works | A release build with obfuscation runs every scenario in this document without crashing | Must |
| A3 | App size cost is known | Size of the example app with and without the plugin recorded per platform (Android per ABI, iOS IPA) | Must (measure only) |

## B. Connection and tokens

| # | Criterion | Pass when | Priority |
|---|---|---|---|
| B1 | Connects and syncs | Sync completes in under 5 s on Wi-Fi for an identity with about 20 conversations (median of 5 cold starts) | Must |
| B2 | Bad token handled | An invalid token produces `TokenException`, with no crash | Must |
| B3 | Automatic refresh works | With 3-minute tokens, the app chats for 15 minutes with no visible disconnect, and a `TokenRefreshed` event at each renewal | Must |
| B4 | Manual mode works | Without a token provider, `TokenAboutToExpire` and `TokenExpired` arrive, and `updateToken` keeps the session alive | Must |
| B5 | Refresh failure recovers | When the token provider fails 3 times in a row: a `TokenRefreshFailed` event each time, retries with backoff, recovery once it succeeds | Should |
| B6 | Logout and login | After `shutdown()`, connecting as a different identity works with no events or data from the first one. A second `connect` while connected throws `ClientAlreadyConnectedException` | Must |

## C. Realtime messaging

| # | Criterion | Pass when | Priority |
|---|---|---|---|
| C1 | Text both ways | Android ↔ iOS: median delivery under 1 s, 95th percentile under 2 s, over 20 messages | Must |
| C2 | Events for every conversation | A message in a conversation the app isn't looking at still raises `MessageAdded`, on Android as well as iOS | Must |
| C3 | Order, no duplicates | 50 messages sent in quick succession arrive in index order, none missing or doubled | Must |
| C4 | History paging | In a 500+ message conversation, pages of 30 via `getMessagesBefore` reach index 0 with no gaps or duplicates; the first page loads in under 1.5 s | Must |
| C5 | Typing indicator | `TypingStarted` reaches the other device in under 1 s, and `TypingEnded` follows after typing stops | Should |
| C6 | Read state | `setLastReadMessageIndex` updates unread counts; a conversation never read returns `null` from `getUnreadMessagesCount`, not 0 | Must |
| C7 | Removed from a conversation | `getConversation` on a conversation the identity was removed from throws `ConversationNotFoundException` on both platforms, with Twilio's error codes recorded | Must |
| C8 | Create and join | `createConversation`, then `join`, then sending a message works | Should |

## D. Media

| # | Criterion | Pass when | Priority |
|---|---|---|---|
| D1 | Image, video, PDF | A 3 MB JPEG, a 50 MB / 60 s MP4 and a PDF arrive with the right content type, file name and size; progress only increases and ends at the total size | Must |
| D2 | No memory spike | Sending the 50 MB video raises app memory by less than 30 MB (shows the file is streamed, not loaded) | Must |
| D3 | Upload outlives the screen | Closing the screen that started an upload doesn't stop it. On iOS, backgrounding the app keeps the upload going about 25 s, after which it either finishes or fails with `MediaUploadException`, never hangs | Should |
| D4 | Bad file handled | A missing or unreadable file path throws `MediaUploadException` immediately | Must |
| D5 | Downloading | `getMediaTemporaryUrl` returns a URL that downloads the file; after it expires, a fresh one can be fetched | Must |

## E. Real-world conditions

| # | Criterion | Pass when | Priority |
|---|---|---|---|
| E1 | Network drop | Airplane mode for 30 s, then back: `ConnectionStateChanged` reports the drop and the recovery; messages sent meanwhile appear exactly once | Must |
| E2 | Background and back | 10 minutes in the background, then foreground: reconnected within 5 s and new messages appear | Must |
| E3 | Killed and relaunched | After a force-quit, the app connects again normally | Must |
| E4 | Soak test | 30 minutes of continuous scripted traffic: no crash, memory stays flat | Should |

## F. Push through Twilio (optional feature)

These need a Twilio Conversations service with APNs/FCM push credentials enabled.

| # | Criterion | Pass when | Priority |
|---|---|---|---|
| F1 | Push arrives | After `registerPushToken`, a new message produces a push while the app is backgrounded or killed, on both platforms | Should |
| F2 | Parsable in the background | `TwilioPushPayload.tryParse` reads the push inside a background message handler (background isolate) | Should |
| F3 | Wrong token type rejected | Registering an FCM token on iOS, or an APNs token on Android, fails with a clear error | Should |

## G. Quality

| # | Criterion | Pass when | Priority |
|---|---|---|---|
| G1 | API matches the design | The public API equals tier 1 of [api-design.md](api-design.md); no Pigeon-generated type is visible to apps | Must |
| G2 | Logic tested without devices | Dart unit tests cover token refresh, error mapping and event handling using a fake platform | Must |
| G3 | Clean CI | `flutter analyze` is clean and CI passes on both Flutter versions | Must |
| G4 | Verification list done | Every item in §15 of the API design is checked | Must |
| G5 | Easy to adopt | Someone new to the plugin follows only the README and sends a first message from a fresh app in under an hour | Should |

## Outcome

- **Every Must passes:** the proof of concept succeeds, and integration into a real app can start.
- **A Must fails:** record why, then either fix it or reconsider the approach.
- **A Should fails:** it becomes a backlog item.

The result is a short report: the measured numbers, the recorded Twilio error codes, the outcome, and open issues.
