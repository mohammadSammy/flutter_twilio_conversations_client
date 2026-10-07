# API design (draft)

Status: **draft for review**. No code exists yet. This document is the contract the Dart, Swift and Kotlin code will be written against, so it should be agreed before step C4 (generating the Pigeon bindings).

Tier markers:
- **T1**: in the first release.
- **T2/T3**: planned later. Listed here only so T1 names don't block them.

---

## 1. Principles

1. **Thin wrapper over the official SDKs.** iOS `TwilioConversationsClient` 4.x and Android `com.twilio:conversations-android` 6.x do the real work: connection, sync, reconnection, uploads. The plugin translates; it doesn't reimplement.
2. **One Dart API, same behaviour on both platforms.** Where the SDKs differ, the plugin hides the difference (see §11).
3. **No business logic, no UI, no backend calls.** The plugin never fetches tokens itself, never shows notifications, never filters messages. Those are app decisions.
4. **Typed everywhere.** No `Map<String, dynamic>` or `dynamic` results. The one exception is Twilio *attributes*, which really are free-form JSON (see §9).
5. **Snapshots, not live objects.** Every model is an immutable value. Changes arrive as events carrying a fresh snapshot. Dart never holds a reference to a native object, so nothing can go stale or leak.
6. **Optional features stay optional.** Token auto-refresh (§4) and Twilio push (§8) can be used, or ignored with no cost.
7. **Secrets never touch the device.** Twilio access tokens are minted by a server that holds the API key secret. The plugin consumes tokens; it can't create them, by design.

## 2. Package layout

```
flutter_twilio_conversations_client/
  lib/
    flutter_twilio_conversations_client.dart   ← exports the public API only
    src/
      client.dart                ← TwilioConversationsClient
      models/                    ← Conversation, Message, Media, Participant, enums
      events.dart                ← ConversationsEvent (sealed)
      errors.dart                ← ConversationsException (sealed)
      token.dart                 ← TokenProvider, token refresh logic
      push.dart                  ← PushToken, TwilioPushPayload
      platform/
        conversations_platform.dart   ← internal interface (what a platform must provide)
        pigeon_platform.dart          ← implementation backed by Pigeon
      generated/                 ← Pigeon output, never exported
  pigeons/conversations_api.dart ← Pigeon input (the native contract)
  ios/
    flutter_twilio_conversations_client/Package.swift     ← Swift Package Manager
    flutter_twilio_conversations_client/Sources/…         ← Swift code (shared with CocoaPods)
    flutter_twilio_conversations_client.podspec           ← CocoaPods
  android/src/main/kotlin/…      ← Kotlin code
  example/                       ← test app
  docs/
```

**Why `src/` plus one export file:** anything under `lib/src/` is private by Dart convention. The public API is exactly what the top file exports. Pigeon's generated classes stay internal, so we can change the native bridge (or add a web version using Twilio's JS SDK) without breaking apps.

**Why an internal `ConversationsPlatform` interface:** Dart unit tests use a fake platform, so the token refresh, error mapping and event logic can be tested without a device.

## 3. The client: lifecycle

```dart
final class TwilioConversationsClient {
  /// Creates the native client and starts connecting. Completes once the client
  /// exists, before sync has finished; use [waitUntilSynced] for that.
  /// Only one client may be connected at a time.                               T1
  static Future<TwilioConversationsClient> connect({
    required String token,
    TokenProvider? tokenProvider,               // §4: enables automatic refresh
    ClientOptions options = const ClientOptions(),
  });

  String get myIdentity;                        // identity from the token        T1
  ConnectionState get connectionState;          // latest known value             T1
  SyncStatus get syncStatus;                    // latest known value             T1
  DateTime? get tokenExpiresAt;                 // §4                             T1

  /// Completes when sync reaches `completed`; throws if sync fails.              T1
  Future<void> waitUntilSynced();

  /// Everything that happens on the client, as one broadcast stream (§7).       T1
  Stream<ConversationsEvent> get events;

  Future<void> updateToken(String token);       // §4                             T1
  Future<void> refreshToken();                  // §4, needs a TokenProvider      T1

  /// Disconnects and releases the native client. The object can't be reused.   T1
  Future<void> shutdown();

  static Future<void> setLogLevel(LogLevel level); // native SDK verbosity        T1
}

final class ClientOptions {
  const ClientOptions({this.region = 'us1'});   // T1
  final String region;
  // T3: commandTimeout, useProxy, deferCertificateTrustToPlatform
}

enum ConnectionState { unknown, connecting, connected, disconnected, denied, error, fatalError }
enum SyncStatus { started, conversationsListCompleted, completed, failed }
enum LogLevel { silent, fatal, error, warning, info, debug, trace }
```

**State over time:**

```
connect() ─▶ connecting ─▶ connected ─▶ sync: started ─▶ conversationsListCompleted ─▶ completed (ready)
                  ▲              │
                  └─ SDK retries ┘  disconnected / error (temporary)      denied / fatalError (needs a new token)
```

**Why a static `connect` and not a constructor:** creating the native client is async and can fail (for example, a bad token). A constructor can't be awaited or throw cleanly.

**Why `waitUntilSynced`:** most calls aren't reliable before sync completes. Chat screens typically wait for it before loading anything. Exposing it as a Future saves every app writing the same stream filter.

**Why only one client:** both SDKs are designed around one client per identity. A second `connect` while one is active throws `ClientAlreadyConnectedException`.

## 4. Tokens: automatic or manual

Two modes; the app picks one.

**Manual mode** (no `tokenProvider`): the plugin only *reports*. It emits `TokenAboutToExpire` and `TokenExpired`, and the app fetches a new token and calls `updateToken`.

**Automatic mode** (with a `tokenProvider`):

```dart
typedef TokenProvider = Future<String> Function();
```

1. Twilio fires "about to expire" (about 3 minutes before). The plugin calls `tokenProvider()` and passes the result to `updateToken`, then emits `TokenRefreshed`.
2. If the provider throws or returns an empty string, the plugin retries with backoff (2 s, 5 s, 15 s, then every 60 s until the token expires) and emits `TokenRefreshFailed(error)` on each failure.
3. On "expired" the same flow runs immediately.
4. The `TokenAboutToExpire` and `TokenExpired` events are still emitted, for logging.

**`refreshToken()`** runs the same path on demand: after a re-login, after a role change, or to test refresh without waiting for a real expiry. It throws `TokenException` if no provider was given.

**`tokenExpiresAt`** is read from the token's `exp` field. A Twilio token is a signed JWT whose payload is plain base64, so reading it needs no secret. It is useful for diagnostics and for confirming that short-lived test tokens really are short.

**Why both modes:** automatic suits most apps; the provider is usually one line that calls your backend. Some apps already have their own token refresh pipeline and need the plugin to stay out of the way.

**Why the plugin never mints tokens:** minting needs the Twilio API key *secret*. Any secret shipped in an app can be extracted, which would let anyone impersonate any user. To test expiry, use tokens with a short time-to-live from your backend, or `refreshToken()`.

## 5. Conversations

```dart
extension on TwilioConversationsClient {   // shown as methods on the client
  Future<List<Conversation>> myConversations();                              // T1
  Future<Conversation> getConversation(String sidOrUniqueName);              // T1
  Future<Conversation> createConversation({                                  // T1
    String? uniqueName, String? friendlyName, Object? attributes,
  });
  Future<Conversation> join(String conversationSid);                         // T1
  Future<Participant?> getParticipantByIdentity(String conversationSid, String identity); // T1

  // T2: leave, destroy, setFriendlyName, setAttributes, setNotificationLevel,
  //     getParticipants, addParticipantByIdentity, removeParticipant
}
```

**Why methods take a `conversationSid` instead of returning a live `Conversation` object with methods:** it keeps Dart free of native object lifetimes, and it maps one-to-one onto the Pigeon bridge. The native side keeps the SDK objects in a registry keyed by SID. A fluent `client.conversation(sid).send(...)` wrapper can be layered on later without breaking anything.

**`getConversation` failure:** a conversation the user can't access (left, removed, never a member) throws `ConversationNotFoundException`. That's how an app detects that the user has left or been removed from a group.

## 6. Messages, read state, typing, media

```dart
  // History                                                                  T1
  Future<int> getMessagesCount(String conversationSid);
  Future<List<Message>> getMessagesBefore(String conversationSid, {required int index, required int count});
  Future<List<Message>> getLastMessages(String conversationSid, {required int count});
  // T2: getMessagesAfter, getMessageByIndex

  // Read state                                                               T1
  Future<int?> getUnreadMessagesCount(String conversationSid);   // null = never read anything
  Future<int?> setLastReadMessageIndex(String conversationSid, int index); // returns new unread count
  // T2: advanceLastReadMessageIndex, setAllMessagesRead, setAllMessagesUnread

  // Sending                                                                  T1
  Future<Message> sendText(String conversationSid, String body);
  MediaSend sendMedia(String conversationSid, MediaUpload upload);
  // T2: message attributes on send, updateBody, remove message

  // Typing                                                                   T1
  Future<void> typing(String conversationSid);

  // Media download                                                           T1
  Future<Uri> getMediaTemporaryUrl({
    required String conversationSid, required int messageIndex, required String mediaSid,
  });
```

```dart
final class MediaUpload {
  const MediaUpload({required this.filePath, required this.contentType, this.filename});
  final String filePath;      // read and streamed natively, never copied into Dart
  final String contentType;   // e.g. image/jpeg, video/mp4, application/pdf
  final String? filename;     // defaults to the file's name
}

final class MediaSend {
  String get uploadId;
  Stream<int> get bytesSent;  // progress; closes when the upload ends
  int get totalBytes;
  Future<Message> get message; // completes when sent; MediaUploadException on failure
}
```

Design notes:
- **`getUnreadMessagesCount` returns `int?`.** Twilio returns nothing until the user has read at least one message. An app typically treats that as "everything is unread" and falls back to the total message count. Turning null into 0 would hide that case and under-count the badge.
- **`setLastReadMessageIndex` returns the new unread count,** because both SDKs already give it back. That saves a second call.
- **Media goes by file path.** Bytes crossing the platform channel are copied, and a large video would freeze the app. The native side opens the file as a stream, so memory use stays flat whatever the file size.
- **`MediaSend` is per upload, not a global event,** so an app-level upload store can own each upload and show its progress, even after the chat screen closes.
- **iOS background time:** while any upload is running, the plugin asks iOS for background time, so a picture keeps uploading briefly after the user leaves the app. It's released when the last upload ends.
- **Why `getMediaTemporaryUrl` needs the message index:** in both SDKs a media item is reached through its message, and messages are fetched by index. Temporary URLs expire after a few minutes, so fetch one right before use and don't store it.

## 7. Events

One broadcast stream, `client.events`, delivered on the main isolate in the order the SDK reports them.

```dart
sealed class ConversationsEvent {}

final class ConnectionStateChanged extends ConversationsEvent { final ConnectionState state; }       // T1
final class SyncStatusChanged      extends ConversationsEvent { final SyncStatus status; }            // T1
final class TokenAboutToExpire     extends ConversationsEvent {}                                       // T1
final class TokenExpired           extends ConversationsEvent {}                                       // T1
final class TokenRefreshed         extends ConversationsEvent { final DateTime? expiresAt; }          // T1, automatic mode
final class TokenRefreshFailed     extends ConversationsEvent { final Object error; }                 // T1, automatic mode
final class ConversationAdded      extends ConversationsEvent { final Conversation conversation; }    // T1
final class MessageAdded           extends ConversationsEvent { final Message message; final Conversation conversation; } // T1
final class MessageUpdated         extends ConversationsEvent { final Message message; }              // T1
final class TypingStarted          extends ConversationsEvent { final String conversationSid; final Participant participant; } // T1
final class TypingEnded            extends ConversationsEvent { final String conversationSid; final Participant participant; } // T1
final class ClientErrorOccurred    extends ConversationsEvent { final ConversationsException error; } // T1
// T2: ConversationUpdated, ConversationDeleted, MessageDeleted,
//     ParticipantAdded/Updated/Removed, UserUpdated
```

Design notes:
- **`sealed` means `switch` must handle every case.** The compiler catches a missing case, and adding an event in a later version shows up as a compile warning, not a silent gap.
- **`MessageAdded` carries the conversation snapshot,** because apps need the conversation's attributes at that moment to update their lists. The native side already has it, so it's free.
- **Events cover all conversations automatically.** The plugin listens on every joined conversation after sync, and on new ones as they're added. That gives Android the same "every message, everywhere" behaviour iOS has natively, with no per-conversation `subscribe` call for apps to manage.
- **No replay.** A late listener doesn't get past events, which is why the latest state is also available as getters (`connectionState`, `syncStatus`).

## 8. Push notifications via Twilio (optional)

Use this only if Twilio sends your pushes. Apps whose own backend sends pushes skip this section entirely.

```dart
sealed class PushToken {
  const factory PushToken.apns(String hexDeviceToken) = ApnsPushToken; // iOS
  const factory PushToken.fcm(String token)           = FcmPushToken;  // Android
}

  Future<void> registerPushToken(PushToken token);     // T1
  Future<void> unregisterPushToken(PushToken token);   // T1

final class TwilioPushPayload {                         // T1, pure Dart
  static TwilioPushPayload? tryParse(Map<String, dynamic> data); // null if not a Twilio push
  final TwilioPushType type;    // newMessage, addedToConversation, removedFromConversation
  final String conversationSid;
  final String? messageSid;
  final int? messageIndex;
  final String? author;
  final String? body;
  final int mediaCount;
}
```

Design notes:
- **Why `PushToken` is two separate types:** Twilio wants the **APNs** device token on iOS and the **FCM** token on Android. Passing the FCM token on iOS is the classic mistake: it registers fine and then no push ever arrives. With two types, a mismatch fails immediately with a clear error. (With `firebase_messaging`, the iOS value comes from `getAPNSToken()`.)
- **Why the parser is pure Dart:** push handlers often run in a background isolate (`FirebaseMessaging.onBackgroundMessage`), where the Twilio client doesn't exist. A pure function works there.
- **What the plugin doesn't do:** obtain push tokens, ask for permission, or show notifications. That's `firebase_messaging` and `flutter_local_notifications`, which the app already uses.
- **Server-side prerequisites, documented in the README:** the Twilio Conversations service needs an APNs and/or FCM credential with push turned on, and the token's chat grant must reference that credential.
- **Register after sync completes.** The plugin queues a registration made earlier and sends it once sync completes, so apps don't need to coordinate this.

## 9. Models

All immutable, with `==` and `hashCode` implemented.

```dart
final class Conversation {
  final String sid;
  final String? uniqueName;
  final String? friendlyName;
  final Object? attributes;          // decoded JSON: Map, List, String, num, bool or null
  final ConversationStatus status;   // joined | notParticipating
  final int? lastMessageIndex;
  final DateTime? lastMessageDate;
  final int? lastReadMessageIndex;   // mine
  final DateTime? dateCreated;
  final String? createdBy;
}

final class Message {
  final String conversationSid;
  final String sid;
  final int index;
  final String? author;              // identity of the sender
  final String? body;
  final DateTime? dateCreated;
  final Object? attributes;
  final List<Media> media;
  final String? participantSid;
}

final class Media {
  final String sid;
  final MediaCategory category;      // media | body | history
  final String contentType;
  final String? filename;
  final int size;                    // bytes
}

final class Participant {
  final String sid;
  final String? identity;
  final DateTime? dateCreated;       // when they joined
  final int? lastReadMessageIndex;
  final Object? attributes;
}
```

- **Attributes are `Object?`**, because Twilio allows any JSON value there, not only objects. They cross the bridge as a JSON string and are decoded once in Dart, so iOS and Android can't disagree on types.
- **Dates cross the bridge as epoch milliseconds (UTC)** and become `DateTime` in Dart. That avoids timezone and date-format mismatches between the platforms.
- **Indexes are `int`.** Dart's 64-bit int holds Twilio's indexes on both platforms.

## 10. Errors

```dart
sealed class ConversationsException implements Exception {
  final String message;
  final int? twilioCode;                     // Twilio's numeric error code when there is one
}
final class NotConnectedException             extends ConversationsException {} // no client, or after shutdown
final class ClientAlreadyConnectedException   extends ConversationsException {}
final class ConversationNotFoundException     extends ConversationsException {} // missing, or not accessible to me
final class TokenException                    extends ConversationsException {} // invalid or expired token, provider failure
final class MediaUploadException              extends ConversationsException {} // file missing or unreadable, upload failed
final class TwilioException                   extends ConversationsException {} // anything else, code + message kept
```

**Why a few specific types plus a catch-all:** apps branch on a small number of situations: left the group, token problem, upload failed. Everything else keeps Twilio's own code and message for logs, without us guessing at hundreds of codes. The exact code-to-type mapping is pinned down during implementation by triggering each case on both platforms.

## 11. Native mapping (what each call becomes)

| Dart | iOS (`TwilioConversationsClient` 4.x) | Android (`conversations-android` 6.x) |
|---|---|---|
| `connect` | `TwilioConversationsClient.conversationsClient(withToken:properties:delegate:completion:)` | `ConversationsClient.create(context, token, properties, callback)` |
| `updateToken` | `client.updateToken(_:completion:)` | `client.updateToken(token, listener)` |
| `shutdown` | `client.shutdown()` | `client.shutdown()` |
| `myConversations` | `client.myConversations()` | `client.myConversations` |
| `getConversation` | `client.conversation(withSidOrUniqueName:completion:)` | `client.getConversation(sidOrUniqueName, callback)` |
| `createConversation` | `client.createConversation(options:completion:)` | `client.conversationBuilder()…build(callback)` |
| `join` | `conversation.join(completion:)` | `conversation.join(listener)` |
| `getParticipantByIdentity` | `conversation.participant(withIdentity:)` | `conversation.getParticipantByIdentity(identity)` |
| `getMessagesCount` | `conversation.getMessagesCount(completion:)` | `conversation.getMessagesCount(callback)` |
| `getMessagesBefore` | `conversation.getMessagesBefore(_:withCount:completion:)` | `conversation.getMessagesBefore(index, count, callback)` |
| `getLastMessages` | `conversation.getLastMessages(withCount:completion:)` | `conversation.getLastMessages(count, callback)` |
| `getUnreadMessagesCount` | `conversation.getUnreadMessagesCount(completion:)` | `conversation.getUnreadMessagesCount(callback)` |
| `setLastReadMessageIndex` | `conversation.setLastReadMessageIndex(_:completion:)` | `conversation.setLastReadMessageIndex(index, callback)` |
| `sendText` | `prepareMessage().setBody(_:).buildAndSend(completion:)` | `prepareMessage().setBody().buildAndSend` |
| `sendMedia` | `prepareMessage().addMedia(inputStream:contentType:filename:listener:)` | `prepareMessage().addMedia(inputStream, …, MediaUploadListener)` |
| `typing` | `conversation.typing()` | `conversation.typing()` |
| `getMediaTemporaryUrl` | `conversation.message(withIndex:completion:)` → `media.getTemporaryContentUrl(completion:)` | message by index → `media.getTemporaryContentUrl` |
| `registerPushToken` | `client.register(withNotificationToken:completion:)` (APNs `Data`) | `client.registerFCMToken(FCMToken(token), listener)` |
| `MessageAdded` (all conversations) | client delegate `conversationsClient(_:conversation:messageAdded:)` | a `ConversationListener` added to each conversation by the plugin |
| `TypingStarted/Ended` | client delegate `typingStartedOn` / `typingEndedOn` | `ConversationListener.onTypingStarted/Ended` |
| token events | `conversationsClientTokenWillExpire` / `TokenExpired` | `onTokenAboutToExpire` / `onTokenExpired` |

The iOS column compiles against `TwilioConversationsClient` 4.0.9 (C5). The Android column is still the plan until C6.

## 12. The native bridge (internal, for C4)

The Pigeon input mirrors §3–§9 with plain data classes:

```dart
@HostApi()
abstract class ConversationsHostApi {
  @async ClientData connect(String token, String region);
  @async void updateToken(String token);
  @async void shutdown();
  @async List<ConversationData> myConversations();
  @async ConversationData getConversation(String sidOrUniqueName);
  @async List<MessageData> getMessagesBefore(String conversationSid, int index, int count);
  @async MessageData sendMedia(String conversationSid, String uploadId, String filePath,
                               String contentType, String? filename);
  // … one method per public call
}

@EventChannelApi()
abstract class ConversationsEventApi {
  PlatformEvent events();          // sealed PlatformEvent subclasses, one per event type
}
```

- `@async` lets native code answer later, which matches the SDKs' completion callbacks.
- Upload progress travels as `UploadProgressEvent(uploadId, bytesSent)` on the event channel. `MediaSend` filters by its `uploadId`.
- Sealed event classes are supported (verified in C4), so each event is its own class. The two token events share one `TokenEvent` with a type enum.
- Pigeon 29 generates `suspend` functions in Kotlin (run on the main dispatcher) and `async throws` in Swift.

## 13. Threading and app lifecycle

- **Main isolate only.** The client and its events live in the main isolate. Only `TwilioPushPayload.tryParse` is safe in background isolates.
- **Native callbacks are moved to the platform main thread** before reaching Flutter, which Flutter requires.
- **The plugin doesn't react to app lifecycle.** The SDKs reconnect on their own when the app returns to the foreground. Apps watch `ConnectionStateChanged` if they want to show an offline state.

## 14. How an app uses it (example: backend sends pushes)

```dart
final client = await TwilioConversationsClient.connect(
  token: await myBackend.fetchTwilioToken(),
  tokenProvider: myBackend.fetchTwilioToken,   // Future<String> Function()
);
await client.waitUntilSynced();

client.events.listen((event) => switch (event) {
  MessageAdded(:final message, :final conversation) => chatList.apply(message, conversation),
  TypingStarted(:final conversationSid) => typing.show(conversationSid),
  TypingEnded(:final conversationSid) => typing.hide(conversationSid),
  _ => null,
});

final convo = await client.getConversation(sid);          // throws ConversationNotFoundException if the user left
final history = await client.getMessagesBefore(sid, index: count, count: 30);
final upload = client.sendMedia(sid, MediaUpload(filePath: path, contentType: 'image/jpeg'));
upload.bytesSent.listen((sent) => progress.value = sent / upload.totalBytes);

// No registerPushToken: the backend sends pushes through FCM.
await client.shutdown();                                   // on logout
```

## 15. Still to verify

- [x] Each iOS mapping in §11 against the 4.0.9 SDK (C5).
- [ ] Each Android mapping in §11 against the 6.2.1 SDK (C6).
- [x] Pigeon sealed classes over event channels: supported in Pigeon 29 for Swift, Kotlin and Dart, including empty subclasses. Used in `pigeons/conversations_api.dart`.
- [ ] Twilio's push payload keys for `TwilioPushPayload` on both platforms (C9).
- [ ] Which Twilio error codes map to `ConversationNotFoundException` and `TokenException` on each platform (C10). Seen so far: iOS answers a missing conversation with 50350 "Conversation not found" (C5).
- [ ] Twilio's media size limit, so `sendMedia` can fail early with a clear `MediaUploadException`.
- [x] Whether Twilio's Android library ships its own R8 keep rules. It does (`com.twilio.**`), but its Tink dependency still breaks release builds, so the plugin ships `consumer-rules.pro` (see technical parameters).
