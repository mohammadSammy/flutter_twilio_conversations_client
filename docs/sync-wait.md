# Waiting for a conversation's sync (0.1.4)

## Status

- Released in v0.1.4: commit `1657545`, tag `v0.1.4`, pushed to `main` on 2026-10-23.
- Tested on a Samsung S23 Ultra (Android 16) and the iOS 18 simulator, inside an app that uses the plugin. Not tested on a physical iPhone.

## The problem

A conversation created moments ago is joined at once, but it is still loading its messages and participants (its sync status hasn't reached ALL yet).

- Android: `getMessages()` and `getParticipants()` throw `IllegalStateException` ("Participants are not available at the moment. Synchronize the conversation first.") until it has. The first open of a brand-new one-to-one failed with that error, and worked when reopened.
- iOS: the same calls return nil instead, for example no participant and no read index.

## How it works

`syncedConversation(sid)` replaces `conversation(sid)` in the calls that need a loaded conversation:

- `getParticipantByIdentity`;
- `getMessagesBefore` and `getLastMessages`;
- `setLastReadMessageIndex`, `advanceLastReadMessageIndex` and `setAllMessagesRead`;
- `sendText`, `sendMedia` and `getMediaTemporaryUrl`.

It returns at once if the conversation has synced or failed, or if this identity hasn't joined it. Otherwise it waits.

- Android, in `ConversationsHostApiImpl.kt`:
  - Waits with Twilio's own `conversation.waitForSynchronization()` from `com.twilio.conversations.extensions`.
  - That helper attaches a listener to the conversation itself and waits for `onSynchronizationChanged`. A failed sync makes it throw Twilio's error.
  - `syncWaits` holds one `CompletableDeferred` per waiting call. Failing it cancels Twilio's wait: `shutdown` fails it as `not_connected`, and `onConversationDeleted` fails it as "removed while it was loading".
- iOS, in `ConversationsHostApiImpl.swift`:
  - Each waiting call parks a `CheckedContinuation` in `syncWaiters`.
  - The client delegate's `conversation:synchronizationStatusUpdated:` resumes them once the status is ALL or FAILED.
  - `shutdown` and `conversationDeleted` resume them with an error.
  - After a failed sync the call goes ahead, and returns Twilio's own result.

Not gated, because they work before sync: `getConversation`, `join`, `getMessagesCount`, `getUnreadMessagesCount` and `typing`.

## Decisions

- **The wait is in the plugin, not in each app.** It hides a difference between the two SDKs, and the nil that iOS returns before sync is wrong data.
- **There is no time limit.**
  - A first version waited up to 10 s. A slow sync would then fail even though it would have finished.
  - Twilio's own wait has no deadline either. When offline, the sync resumes on reconnect.
  - An app that wants a limit adds `.timeout()` to the call.
- **On Android, Twilio's `waitForSynchronization()` is used rather than the client-wide `onConversationSynchronizationChange`.**
  - A version that waited for the client-wide callback hung forever on a device: the callback never came for a conversation created moments ago, although the conversation did sync.
  - Twilio's Android demo app (`twilio-conversations-demo-android-kotlin`) calls `waitForSynchronization()` before reading participants or messages.
- **On iOS, the client delegate callback is used.** The iOS SDK has no such helper. Twilio's iOS demo app (`twilio-conversations-demo-ios-swift`) treats a conversation as ready when that callback reports `.all`.
- **Conversations the user hasn't joined don't wait.** They never sync, so the wait would never end.
- **Shutdown and deletes end the wait.** Neither SDK ends it in those cases, so a call could otherwise be left pending forever.

## How to test it

There is no automated test: it needs a conversation created moments before it is opened.

1. Create a conversation that includes the identity, through the REST API or a backend.
2. Within a second, call `getParticipantByIdentity` or `getLastMessages` on it.
3. Expect the call to return after the sync, roughly 1.5–2 s on Android, with no error.

Results from the 2026-10-23 test in an app:

| Platform | Case | `getParticipantByIdentity` | Outcome |
|---|---|---|---|
| Android (Samsung) | Brand-new one-to-one, 2 tries | 1463 and 1841 ms | Opened the first time, message sent |
| Android (Samsung) | Existing conversation (76 messages) | 129 ms | No wait |
| iOS simulator | Brand-new one-to-one, 2 tries | Not measured | Usable within about 8 s, message sent |

Each time is counted from the start of opening the room.

## Open items

- Physical iPhone not tested, and no per-step timings on iOS.
- Not tested while waiting:
  - being offline;
  - a failed sync;
  - the user leaving the conversation;
  - shutdown.
- `getConversation` still reports `lastReadMessageIndex` as null for a conversation that hasn't synced yet. That is the 0.1.3 workaround.
