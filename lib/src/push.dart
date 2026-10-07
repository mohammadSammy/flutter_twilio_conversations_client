import 'generated/conversations_api.g.dart';

/// A device token for push notifications sent by Twilio (api-design §8).
///
/// Twilio needs the APNs device token on iOS and the FCM token on Android. Two types
/// make a mismatch fail at once, instead of registering fine and never delivering.
sealed class PushToken {
  const PushToken(this.token);

  /// iOS: the APNs device token as a hex string, for example from
  /// `FirebaseMessaging.instance.getAPNSToken()`.
  const factory PushToken.apns(String hexDeviceToken) = ApnsPushToken;

  /// Android: the FCM registration token.
  const factory PushToken.fcm(String token) = FcmPushToken;

  final String token;
}

final class ApnsPushToken extends PushToken {
  const ApnsPushToken(super.token);
}

final class FcmPushToken extends PushToken {
  const FcmPushToken(super.token);
}

/// The bridge's name for the token's kind. Not exported.
PlatformPushTokenType platformPushTokenType(PushToken token) => switch (token) {
  ApnsPushToken() => PlatformPushTokenType.apns,
  FcmPushToken() => PlatformPushTokenType.fcm,
};
