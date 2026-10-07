import 'dart:convert';

/// Fetches a fresh Twilio access token, usually from the app's backend.
/// Passing one to `connect` turns on automatic refresh (api-design §4).
typedef TokenProvider = Future<String> Function();

/// Waits between attempts when automatic refresh fails: 2 s, 5 s, 15 s, then every 60 s.
const tokenRefreshDelays = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 60)];

/// Reads the `exp` field of a Twilio access token. A token is a signed JWT whose
/// payload is plain base64, so this needs no secret. Null if the token can't be read.
DateTime? tokenExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final exp = payload is Map ? payload['exp'] : null;
    return exp is int ? DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true) : null;
  } on FormatException {
    return null;
  }
}
