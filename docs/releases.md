# Releases

The plugin isn't on pub.dev. Apps use it from GitHub as a git dependency pinned to a tag (see the README). [CHANGELOG.md](../CHANGELOG.md) lists every change. This record adds how each release was tested, and how to make the next one.

## Releases so far

All are tagged and pushed to `main`.

| Version | Date | Commit | What | Tested on |
|---|---|---|---|---|
| v0.1.0 | 2026-10-12 | `478ceb8` | First release: the whole API, device tests and results | Must criteria on an iPhone XS and a Samsung S23 Ultra ([device-testing.md](device-testing.md)); CI green on Flutter 3.44 and stable |
| v0.1.1 | 2026-10-12 | `150d099` | iOS upload background task, privacy manifest, exact Twilio iOS pin, progress on the main queue | D3 on the iPhone |
| v0.1.2 | 2026-10-13 | `0d09a79` | Native `connect` replaces a client left over from a hot restart | `native_api_test` on the Samsung and the iPhone |
| v0.1.3 | 2026-10-20 | `e6aa02b` | `ConversationUpdated`, `ConversationDeleted`, `ParticipantUpdated`; `advanceLastReadMessageIndex`, `setAllMessagesRead`; Android read index before sync | U1 on the Samsung and the iOS simulator |
| v0.1.4 | 2026-10-23 | `1657545` | Calls that need a synced conversation wait for its sync ([sync-wait.md](sync-wait.md)) | In an app, on the Samsung and the iOS simulator |

Commits between releases that changed no version: `b56b528` (CI installs the latest stable Flutter) and `2644f38` (CI results for A1 and G3).

## Decisions

- **GitHub tags, not pub.dev.** `publish_to: none` stays on purpose. `.pubignore` exists because pub ignores `.git/info/exclude`, so private local files would otherwise ship.
- **Exact native pins.** Twilio iOS 4.0.9 and Android 6.2.1 are pinned exactly, so a new Twilio release only reaches apps through a plugin release. See [technical-parameters.md](technical-parameters.md).
- **0.1.3 is breaking for exhaustive `switch`es** over `ConversationsEvent`, though it is a patch version; the CHANGELOG says so.
- **Platform differences the plugin evens out:**
  - Android's `advanceLastReadMessageIndex` to an earlier index is skipped, as iOS ignores it.
  - Android's `lastReadMessageIndex` before sync is null instead of a throw.
  - The wait for sync is in 0.1.4.

## How to release

1. Run the checks in [AGENTS.md](../AGENTS.md). Then build the example for Android (`flutter build apk --debug`), and with `xcodebuild` for a generic iOS device in `example/ios`.
2. Test the change on the device tests or in the app, as the change needs.
3. Bump `version` in `pubspec.yaml`. `example/pubspec.lock` follows it.
4. Date the version's CHANGELOG entry.
5. Bump the README status line and the install `ref:`.
6. Commit as `add: … (x.y.z)`, tag `vx.y.z`, then push `main` and the tag.
7. Apps move their `ref:` to the new tag.

## Open items

- No licence has been chosen yet.
- The repository may move to another GitHub organisation.
- B3 (short tokens) is a known limit; see [device-testing.md](device-testing.md).
