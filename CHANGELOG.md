## 0.1.2 (2026-10-13)

* Fixed: after a Flutter hot restart, `connect` failed with `ClientAlreadyConnectedException` and left the app without a connection. A hot restart resets Dart but keeps the native client, which Dart could no longer shut down. Native `connect` now replaces a client left over like this. Dart still refuses a real second `connect`.
* iOS: `shutdown` detaches the plugin from the old client, so none of its events reach a later session. Android already did this.

## 0.1.1 (2026-10-12)

* iOS: an upload now keeps going for about 30 s after the user leaves the app. Before, it stopped at once. After that time it fails with `MediaUploadException` when the app comes back, instead of hanging.
* iOS: the plugin now ships its privacy manifest. It no longer uses `FileManager.attributesOfItem`, one of Apple's required-reason APIs, so apps don't need to declare a reason for it.
* iOS: the Twilio SDK is pinned to exactly 4.0.9, like the Android SDK, so a new Twilio release only reaches apps through a plugin release.
* iOS: upload progress is throttled on the main queue, so its counter is only ever touched from one thread.

## 0.1.0 (2026-10-12)

First release. It works on iOS and Android, and is tested on real phones against the Must criteria in [docs/poc-results.md](docs/poc-results.md).

* `TwilioConversationsClient`:
  * connect, with only one client at a time;
  * wait for sync;
  * automatic token refresh through a `tokenProvider`, with retries; or manual `updateToken`.
* Conversations: list, get, create, join, and look up a participant.
* Messages:
  * history paging;
  * read state and unread counts;
  * sending text;
  * typing indicators;
  * temporary media download URLs.
* Media upload by file path, streamed natively, with upload progress. Files over Twilio's 150 MB limit are refused before uploading.
* One stream of events covering every joined conversation: connection, sync, token, messages, typing and errors.
* Typed exceptions for bad tokens, missing or left conversations, failed uploads, and other Twilio errors.
* Optional push through Twilio:
  * register and unregister an APNs or FCM token;
  * `TwilioPushPayload.tryParse` reads a Twilio push, including in a background isolate.
* Example app: a minimal chat screen, plus the test harness and device tests.

Known limits:
* Tokens should last well over 5 minutes; see the README.
* `MessageAdded` events can arrive out of index order when many messages are sent at once.
