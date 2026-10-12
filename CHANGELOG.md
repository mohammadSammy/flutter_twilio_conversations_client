## 0.1.0 (unreleased)

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
