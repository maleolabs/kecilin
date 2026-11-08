import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/format.dart';
import '../domain/compression_engine.dart';
import '../domain/models.dart';
import 'compress_channel.dart';

/// Hard ceiling for a single image job. A legitimate 12 MP encode is measured
/// in seconds; anything longer means the native side died and will never reply.
const _imageTimeout = Duration(minutes: 10);

/// Fallback target when the user picks "target size" but the shared options
/// object currently has no target (e.g. after choosing "Otomatis" for PDF).
const _defaultTargetBytes = 500 * kb;

class ImageCompressionEngine implements CompressionEngine {
  const ImageCompressionEngine();

  @override
  MediaKind get kind => MediaKind.image;

  @override
  Future<CompressionOutcome> compress({
    required SelectedFile file,
    required CompressionOptions options,
    required String outputPath,
    required ProgressCallback onProgress,
    required CancelCheck isCancelled,
  }) async {
    if (isCancelled()) throw const CompressionCancelled();

    final source = File(file.path);
    if (!source.existsSync()) {
      throw const CompressionFailure('File sumber sudah tidak tersedia.');
    }

    final wantsWebp = options.format == OutputFormat.webp;
    final target = options.imageMode == ImageMode.target
        ? (options.targetBytes ?? _defaultTargetBytes)
        : null;

    // Nothing to gain: keep the original bytes untouched. Only safe when the
    // source already is the format we would write, otherwise a PNG would end up
    // inside a *.jpg file.
    if (target != null &&
        file.bytes <= target &&
        options.maxEdge == 0 &&
        !wantsWebp &&
        isJpegName(file.name)) {
      onProgress(1, 'Selesai');
      await source.copy(outputPath);
      return CompressionOutcome(
        outputPath: outputPath,
        outputBytes: await File(outputPath).length(),
        outputExtension: 'jpg',
        note: 'Sudah di bawah ${formatBytes(target)}, file tidak diubah.',
      );
    }

    final jobId = 'img-${DateTime.now().microsecondsSinceEpoch}';
    var lastFraction = 0.0;
    final subscription = CompressChannel.events().listen((event) {
      if (event['jobId'] != jobId) return;
      final fraction = (event['fraction'] as num?)?.toDouble() ?? 0;
      final stage = event['stage'] as String? ?? 'Mengompres';
      // A retry restarts the native counter; never let the bar move backwards.
      final value = fraction.clamp(0.0, 1.0);
      if (value < lastFraction) return;
      lastFraction = value;
      onProgress(value, stage);
    });

    CompressChannel.bindJob(jobId);
    try {
      final result = await CompressChannel.methods
          .invokeMapMethod<String, dynamic>('compressImage', {
            'jobId': jobId,
            'inputPath': source.path,
            'outputPath': outputPath,
            'targetBytes': target,
            'quality': options.imageQuality,
            'minQuality': 40,
            'maxQuality': 93,
            'maxEdge': options.maxEdge,
            'webp': wantsWebp,
            'maximumMode': options.imageMode == ImageMode.maximum,
          })
          .timeout(_imageTimeout);

      if (result == null) {
        throw const CompressionFailure('Tidak ada hasil dari mesin kompresi.');
      }

      final outputBytes =
          (result['afterBytes'] as num?)?.toInt() ??
          await File(outputPath).length();
      final targetMet = result['targetMet'] as bool? ?? true;

      String? note;
      if (target != null && !targetMet) {
        note =
            'Target ${formatBytes(target)} belum tercapai. '
            'Ini hasil terkecil yang bisa dibuat tanpa merusak gambar.';
      } else if (options.imageMode == ImageMode.maximum) {
        note = 'Metadata dihapus, gambar di-encode ulang di kualitas 96.';
      }

      // Never hand back a file that is bigger than the one the user gave us.
      // Re-encoding an already-optimised JPEG easily costs a few extra KB.
      if (outputBytes >= file.bytes) {
        return _keepOriginal(
          source: source,
          file: file,
          outputPath: outputPath,
          note: options.imageMode == ImageMode.maximum
              ? 'Gambar sudah optimal, file asli dipertahankan.'
              : 'Kompresi tidak memperkecil file, versi asli dipertahankan.',
        );
      }

      onProgress(1, 'Selesai');
      return CompressionOutcome(
        outputPath: outputPath,
        outputBytes: outputBytes,
        outputExtension: wantsWebp ? 'webp' : 'jpg',
        note: note,
      );
    } on TimeoutException {
      throw const CompressionFailure(
        'Proses terlalu lama dan dihentikan. Coba turunkan resolusi atau DPI.',
      );
    } on PlatformException catch (error) {
      if (error.code == 'CompressCancelled') throw const CompressionCancelled();
      throw CompressionFailure(_friendly(error), cause: error);
    } finally {
      CompressChannel.releaseJob(jobId);
      await subscription.cancel();
    }
  }

  /// Copies the source next to the requested output, keeping the source format
  /// so the file extension never lies about its contents.
  Future<CompressionOutcome> _keepOriginal({
    required File source,
    required SelectedFile file,
    required String outputPath,
    required String note,
  }) async {
    final sourceExtension = extensionFor(file.name);
    final keepsExtension =
        sourceExtension.isEmpty || sourceExtension == extensionFor(outputPath);
    final copyPath = keepsExtension
        ? outputPath
        : withExtension(outputPath, sourceExtension);

    if (copyPath != outputPath) {
      try {
        final stale = File(outputPath);
        if (stale.existsSync()) stale.deleteSync();
      } catch (_) {
        // Best effort; the copy below is what matters.
      }
    }
    await source.copy(copyPath);
    return CompressionOutcome(
      outputPath: copyPath,
      outputBytes: await File(copyPath).length(),
      outputExtension: sourceExtension.isEmpty ? null : sourceExtension,
      note: note,
    );
  }

  String _friendly(PlatformException error) {
    switch (error.code) {
      case 'OutOfMemoryError':
        return 'Gambar terlalu besar untuk diproses. Coba turunkan resolusi maksimum.';
      case 'IllegalStateException':
        return error.message ?? 'Gambar gagal dikompres.';
      default:
        return error.message ?? 'Gambar gagal dikompres (${error.code}).';
    }
  }
}

/// Reads pixel dimensions without decoding the whole image.
Future<({int width, int height})?> readImageSize(String path) async {
  try {
    final info = await CompressChannel.methods
        .invokeMapMethod<String, dynamic>('getImageInfo', {'path': path})
        .timeout(const Duration(seconds: 5));
    final width = (info?['width'] as num?)?.toInt();
    final height = (info?['height'] as num?)?.toInt();
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return (width: width, height: height);
  } catch (_) {
    return null;
  }
}
