import 'package:flutter/services.dart';

/// Every failure the plugin reports. Apps branch on the few specific types and log
/// the rest, which keep Twilio's own code and message (api-design §10).
sealed class ConversationsException implements Exception {
  const ConversationsException(this.message, {this.twilioCode});

  final String message;

  /// Twilio's numeric error code, when Twilio produced the error.
  final int? twilioCode;

  @override
  String toString() => '$runtimeType: $message${twilioCode == null ? '' : ' (Twilio $twilioCode)'}';
}

/// No client is connected, or the client was shut down.
final class NotConnectedException extends ConversationsException {
  const NotConnectedException(super.message, {super.twilioCode});
}

/// [TwilioConversationsClient.connect] was called while a client is connected.
final class ClientAlreadyConnectedException extends ConversationsException {
  const ClientAlreadyConnectedException(super.message, {super.twilioCode});
}

/// The conversation doesn't exist, or this identity can't access it: it left, was
/// removed, or was never a member.
final class ConversationNotFoundException extends ConversationsException {
  const ConversationNotFoundException(super.message, {super.twilioCode});
}

/// A token was invalid or expired, or the app's token provider failed.
final class TokenException extends ConversationsException {
  const TokenException(super.message, {super.twilioCode, this.cause});

  /// What the token provider threw, when that's the reason.
  final Object? cause;
}

/// The file couldn't be read, or Twilio rejected the upload.
final class MediaUploadException extends ConversationsException {
  const MediaUploadException(super.message, {super.twilioCode});
}

/// Any other Twilio failure.
final class TwilioException extends ConversationsException {
  const TwilioException(super.message, {super.twilioCode});
}

/// Twilio codes that mean a specific exception, on both platforms. Codes are added
/// here once they've been seen on real devices (api-design §15).
const _conversationNotFoundCodes = {50350};

/// Turns a failed native call into the matching [ConversationsException].
ConversationsException exceptionFromPlatform(PlatformException e) {
  final message = e.message ?? e.code;
  final twilioCode = switch (e.details) {
    final int code => code,
    _ => null,
  };
  return switch (e.code) {
    'not_connected' => NotConnectedException(message),
    'already_connected' => ClientAlreadyConnectedException(message),
    'conversation_not_found' => ConversationNotFoundException(message, twilioCode: twilioCode),
    'token' => TokenException(message, twilioCode: twilioCode),
    'media_upload' => MediaUploadException(message, twilioCode: twilioCode),
    _ when _conversationNotFoundCodes.contains(twilioCode) => ConversationNotFoundException(
      message,
      twilioCode: twilioCode,
    ),
    _ => TwilioException(message, twilioCode: twilioCode),
  };
}

/// Runs a native call, turning its [PlatformException] into a [ConversationsException].
Future<T> guardPlatform<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (e) {
    throw exceptionFromPlatform(e);
  }
}
