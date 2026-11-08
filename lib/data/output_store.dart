import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/format.dart';
import '../domain/models.dart';
import 'compress_channel.dart';

abstract class OutputTarget {
  Future<String> nextPath(SelectedFile file, CompressionOptions options);

  Future<String?> saveToDownloads(
    File file, {
    required String displayName,
    required String mime,
  });

  String mimeFor(MediaKind kind, OutputFormat format, {String? extension});

  Future<int> totalOutputBytes();

  Future<void> clear();
}

class OutputStore implements OutputTarget {
  const OutputStore();

  Future<Directory> outputDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/Kecilin');
    if (!directory.existsSync()) directory.createSync(recursive: true);
    return directory;
  }

  @override
  Future<String> nextPath(SelectedFile file, CompressionOptions options) async {
    final directory = await outputDirectory();
    final extension = switch (file.kind) {
      MediaKind.pdf => 'pdf',
      MediaKind.image => options.format == OutputFormat.webp ? 'webp' : 'jpg',
    };
    final stem = sanitizeFileName(stemOf(file.name));
    var candidate = File('${directory.path}/$stem-kecil.$extension');
    var counter = 1;
    while (candidate.existsSync()) {
      candidate = File('${directory.path}/$stem-kecil ($counter).$extension');
      counter++;
    }
    return candidate.path;
  }

  @override
  Future<String?> saveToDownloads(
    File file, {
    required String displayName,
    required String mime,
  }) async {
    try {
      final result = await CompressChannel.methods
          .invokeMapMethod<String, dynamic>('saveToDownloads', {
            'path': file.path,
            'displayName': displayName,
            'mime': mime,
          });
      return result?['displayPath'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  String mimeFor(MediaKind kind, OutputFormat format, {String? extension}) {
    if (kind == MediaKind.pdf) return 'application/pdf';
    final actual = extension ?? (format == OutputFormat.webp ? 'webp' : 'jpg');
    switch (actual) {
      case 'webp':
        return 'image/webp';
      case 'png':
        return 'image/png';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Future<int> totalOutputBytes() async {
    final directory = await outputDirectory();
    if (!directory.existsSync()) return 0;
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  @override
  Future<void> clear() async {
    final directory = await outputDirectory();
    if (directory.existsSync()) {
      for (final entity in directory.listSync()) {
        try {
          entity.deleteSync(recursive: true);
        } catch (_) {
          // A file may still be open by another app; leave it alone.
        }
      }
    }
    // Libraries stage copies of the documents (PDFBox scratch, share_plus);
    // "hapus file hasil" has to mean all of them.
    try {
      await CompressChannel.methods.invokeMethod<Map<dynamic, dynamic>>(
        'clearCache',
      );
    } catch (_) {
      // Best effort only.
    }
  }
}
