import 'dart:io';
import 'dart:typed_data';

/// A file of a set size for the media tests (D1, D2). The bytes are filler: Twilio
/// stores any content, and the criteria check type, name, size and progress.
class TestFile {
  const TestFile(this.label, this.filename, this.contentType, this.bytes);

  final String label;
  final String filename;
  final String contentType;
  final int bytes;

  static const all = [
    TestFile('3 MB JPEG', 'test-photo.jpg', 'image/jpeg', 3 * 1024 * 1024),
    TestFile('50 MB MP4', 'test-video.mp4', 'video/mp4', 50 * 1024 * 1024),
    TestFile('200 KB PDF', 'test-document.pdf', 'application/pdf', 200 * 1024),
  ];

  /// Writes the file in 64 KB chunks, so even the 50 MB one never sits in memory.
  Future<File> create() async {
    final file = File('${Directory.systemTemp.path}/$filename');
    if (await file.exists() && await file.length() == bytes) return file;
    final chunk = Uint8List(64 * 1024);
    for (var i = 0; i < chunk.length; i++) {
      chunk[i] = i % 251;
    }
    final out = await file.open(mode: FileMode.write);
    try {
      for (var written = 0; written < bytes; written += chunk.length) {
        final size = bytes - written < chunk.length ? bytes - written : chunk.length;
        await out.writeFrom(chunk, 0, size);
      }
    } finally {
      await out.close();
    }
    return file;
  }
}
