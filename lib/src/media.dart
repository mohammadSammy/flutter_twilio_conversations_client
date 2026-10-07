import 'dart:async';

import 'models.dart';

/// A file to send. Native code reads it as a stream, so the bytes never cross into
/// Dart and memory stays flat whatever the size (api-design §6).
final class MediaUpload {
  const MediaUpload({required this.filePath, required this.contentType, this.filename});

  final String filePath;

  /// For example image/jpeg, video/mp4 or application/pdf.
  final String contentType;

  /// Defaults to the file's own name.
  final String? filename;
}

/// One upload in progress. An app can keep it after the chat screen closes and still
/// show its progress.
final class MediaSend {
  /// Created by `TwilioConversationsClient.sendMedia`.
  MediaSend.internal(this.uploadId, this.totalBytes, this._progress, this.message);

  final String uploadId;

  /// The file's size when the upload started; 0 if it couldn't be read.
  final int totalBytes;

  final StreamController<int> _progress;

  /// Bytes sent so far. Broadcast, so a late listener only sees later progress.
  /// Closes when the upload ends.
  Stream<int> get bytesSent => _progress.stream;

  /// Completes with the sent message, or fails with a `MediaUploadException`.
  final Future<Message> message;
}
