# Device testing against the success criteria (phase C10)

Phase C10 tested the plugin on real phones against [poc-success-criteria.md](poc-success-criteria.md). The measured results, error codes and fixes are in [poc-results.md](poc-results.md). This record covers how the testing is set up, and what was decided.

## Status

- Done for the Must criteria. Every Must passes on both platforms except B3, which is a known limit.
- Commits, all pushed and part of v0.1.0:
  - `5a07d0b`: the device tests, `tool/twilio_rest.py`, and the first fixes they found.
  - `cc756d3`: the token mapping and Android event fixes, and the burst order documented.
  - `e95316b`: the Must results, more fixes, and the package set up for use from git.
- CI (`.github/workflows/`) runs on Flutter 3.44 and on stable. It covers A1 and G3; run 38242932260 was all green.
- Should criteria are deferred, except D3 (passes on iOS since 0.1.1) and B5, C5, C8 (pass on both).

## How it works

- `example/integration_test/poc/poc.dart` holds the shared helpers:
  - `setUpPoc`;
  - `report()`, which prints one `POC {json}` line per result;
  - token fetching from `tool/token_server.py`;
  - an event log with `waitFor`;
  - median and percentile.
- `poc_single_test.dart` holds the one-phone criteria.
  - `--dart-define=ONLY=B4,D1` runs a subset.
  - B3, D3, E1, E2, E3 and U1 run only when named.
  - `SDK_LOG=debug` turns on Twilio's logging.
- `poc_pair_test.dart` holds the two-phone criteria C1, C2, C3 and C5.
  - Run `python3 tool/twilio_rest.py pair <id>` first.
  - Then start `ROLE=responder` and `ROLE=measurer` with the same `PAIR`.
- `tool/twilio_rest.py` makes the REST changes a test needs from "another person":
  - `pair` and `removed-conversation`;
  - `send`, `read` and `remove`;
  - `conversations`.
- U1 uses the Mac as the other person. The test prints `POC-REST <args>` lines, and a small watcher runs each one as `python3 tool/twilio_rest.py <args>`. The watcher isn't in the repo.
- Hands-on tests (for example backgrounding the app) show their instructions on screen.

## Decisions

- **Only the Must criteria for now;** the Should items come later.
- **C3 checks what Twilio guarantees, not arrival order.**
  - When many messages are sent at once, `MessageAdded` can arrive out of index order, up to about 25 places late.
  - C3 now checks that all 50 messages arrive exactly once, and that `getLastMessages` returns them in index order. Arrival order is only recorded.
  - Apps place messages by `message.index`, as documented in api-design §7 and in the `MessageAdded` docs.
- **B3 stays a known limit.**
  - Twilio warns 3 minutes before a token expires, so tokens shorter than about 5 minutes refresh badly.
  - Real tokens last about an hour.
  - The proposed fix, scheduling the refresh from the token's own expiry, is in poc-results.
- **Twilio codes join a specific exception only after they have been seen on a real device:**
  - code 5 is `TokenException`;
  - 50350 and 50430 are `ConversationNotFoundException`.
- **Android tests run as release builds with R8,** launched with `adb shell am start`, because `flutter test` can't make release builds. These runs count towards A2.

## How to test

Follow [example/README.md](../example/README.md) and the device-test notes in [AGENTS.md](../AGENTS.md).

Gotchas:
- Run `adb reverse tcp:8787 tcp:8787` before every Android run, because `flutter test` clears it.
- Restart `tool/token_server.py` after the Mac restarts.
- Keep the Android phone awake (Developer options, "Stay awake"). A phone call, the screen sleeping or the app going to the background cuts Android's network, and that looks like a plugin failure.
- iOS test apps never exit. Stop the launch once the `POC` lines are in.
- If the iPhone says the profile isn't trusted, trust it again in Settings → General → VPN & Device Management.

## Open items

- B3 (short tokens) fails by design. Whether to fix it depends on the token lifetime the backend issues.
- Not tested:
  - E4 (soak), F1 (needs push credentials), G5 (adopting the plugin from the README alone);
  - a real push payload for `TwilioPushPayload`;
  - the Android 7.0 emulator.
- U1 ran on the Samsung and the iOS simulator, not the physical iPhone.
- `example/lib/main.dart` (the minimal example) has never run on a device.
