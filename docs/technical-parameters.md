# Technical parameters

The versions and minimums this plugin builds against, and why. Checked against live sources on 5 October 2026.

## Identity

| | Value |
|---|---|
| Dart package | `flutter_twilio_conversations_client` |
| Android namespace | `com.identity_solutions.twilio_conversations` (reverse of `identity-solutions.com`; hyphens become underscores) |
| iOS module | `flutter_twilio_conversations_client` (Flutter's convention: same as the package) |
| First version | `0.1.0`. 0.x means the API may still change between minor versions |

## Flutter and Dart

| | Value | Why |
|---|---|---|
| Minimum Flutter | **3.44** | First release with Swift Package Manager on by default, which the iOS SDK requires (see below) |
| Development Flutter | latest stable (3.47.6 / Dart 3.13.5 at time of writing) | Pigeon 29 needs Dart ≥ 3.11 |
| CI matrix | Flutter 3.44 + latest stable | Proves the stated minimum actually works |
| Runtime dependencies | none besides `flutter` | Fewer version conflicts for apps using the plugin |
| Code generation | `pigeon` **29.0.6**, pinned exactly, dev dependency only | A pinned generator keeps generated code stable. Apps never download it |
| Lints | `flutter_lints` | Standard Flutter rules |

## iOS

| | Value | Why |
|---|---|---|
| Twilio SDK | `twilio/conversations-ios` **4.0.9+**, `upToNextMajor` | Latest release (Aug 2026) |
| Dependency manager | **Swift Package Manager only** | See below |
| Minimum iOS | **13.0** | Twilio's own minimum. Apps can set a higher one |
| Language | Swift | |

**Why no CocoaPods:** Twilio published its iOS SDK to CocoaPods up to 4.0.2 (August 2023) only. Every release since (4.0.3–4.0.9) is available through Swift Package Manager alone. The alternatives were:
- a CocoaPods version pinned to a three-year-old SDK, with different bugs and twice the testing;
- bundling Twilio's binary in this repo, with unclear redistribution terms.

Apps on Flutter < 3.44, or with Swift Package Manager disabled, are not supported. Revisit if real users need it.

## Android

| | Value | Why |
|---|---|---|
| Twilio SDK | `com.twilio:conversations-android` **6.2.1** | Latest release |
| minSdk | **24** (Android 7.0) | Flutter's default. Twilio supports down to 21, so it can be lowered on request |
| compileSdk | 36 | Flutter's current default |
| Java / JVM target | 17 | Required by current Android Gradle tooling |
| Language | Kotlin | |
| R8 keep rules | to be checked (see API design §15) | |

## Sources

- Twilio iOS releases: https://github.com/twilio/conversations-ios/releases
- Twilio iOS on CocoaPods: https://cocoapods.org/pods/TwilioConversationsClient
- Twilio Android on Maven Central: https://repo1.maven.org/maven2/com/twilio/conversations-android/
- Pigeon: https://pub.dev/packages/pigeon
- Flutter and Swift Package Manager: https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors
