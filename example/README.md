# Example app: the proof-of-concept harness

The example app runs every scenario in [docs/poc-success-criteria.md](../docs/poc-success-criteria.md) against a real Twilio account. It's a test tool, not a sample chat UI.

## Setup

1. A Twilio account with a Conversations Service you can use for tests. Put its values in `tool/twilio-test.env` (git-ignored), as described at the top of `tool/test_token.py`.
2. Start the development token server on your computer:
   ```bash
   python3 tool/token_server.py
   ```
   It prints its address. Use it only with a test account: anyone who can reach it gets a token for any identity.
3. Point the app at it:
   - **Android over USB:** `adb reverse tcp:8787 tcp:8787`, then the default `http://localhost:8787` works.
   - **iOS, or Android over Wi-Fi:** use the printed address, either typed on the connect screen or at build time with `--dart-define=TOKEN_SERVER=http://<address>:8787`. iOS asks for local network access the first time; allow it.
4. Run the app: `flutter run` from this folder.

## Where each criterion is run

| Criterion | In the app |
|---|---|
| B1 connect and sync time | Connect; the Events tab logs the connect and sync times |
| B2 bad token | Connect screen: *Connect with a bad token* |
| B3 automatic refresh | Token lifetime 180, automatic refresh on; watch for `token refreshed` in Events |
| B4 manual mode | Automatic refresh off; on `token about to expire`, Tools: *Fetch and apply* |
| B5 refresh failures | Tools: *Fail provider 3×* before the token expires |
| B6 logout and login | The logout button, then connect as another identity |
| C1 delivery time | Second device: Tools, *Echo mode* on. This device: Tools, *Latency ×20* |
| C2 events everywhere | Events tab, while another device writes in a conversation you haven't opened |
| C3 order and duplicates | Sender: *Burst ×50*. Receiver: *Bursts received* |
| C4 paging | *Seed 500 messages* once, then *Page to start* |
| C5 typing | Type in a conversation on one device; the other shows "… typing" |
| C6 read state | The *unread* count and *Mark all read* in a conversation |
| C7 removed from a conversation | Remove the identity in the Twilio Console, then open the conversation by SID |
| C8 create and join | Conversations tab: the + button |
| D1, D2 media and memory | Tools: *Start memory sampling*; in a conversation, send the test files from the paperclip menu; then *Stop and report* |
| D3 upload outlives the screen | Start the 50 MB upload, leave the conversation; Tools still shows its progress |
| D4 bad file | Paperclip menu: *A missing file* |
| D5 download | The download button on a message with media |

Results with raw numbers appear under Tools, *Results*, and in the Events tab, which can be copied as text.

## Tests

`integration_test/` holds device tests that run against the same Twilio account:

- `native_api_test.dart`: the native layer, through the generated bridge.
- `public_api_test.dart`: the public API, as an app uses it.
- `harness_smoke_test.dart`: this app's screens, driven end to end.
