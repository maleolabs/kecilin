import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/format.dart';
import '../domain/compression_engine.dart';
import '../domain/models.dart';
import 'compress_channel.dart';

/// A large PDF on a slow phone can legitimately take minutes; this only exists
/// to escape a dead native side, not to bound normal work.
const _pdfTimeout = Duration(minutes: 30);

class PdfCompressionEngine implements CompressionEngine {
  const PdfCompressionEngine();

  @override
  MediaKind get kind => MediaKind.pdf;

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

    final target = options.targetBytes;
    if (target != null && file.bytes <= target) {
      onProgress(1, 'Selesai');
      await source.copy(outputPath);
      return CompressionOutcome(
        outputPath: outputPath,
        outputBytes: await File(outputPath).length(),
        pages: file.pages,
        outputExtension: 'pdf',
        note: 'Sudah di bawah ${formatBytes(target)}, file tidak diubah.',
      );
    }

    final jobId = 'pdf-${DateTime.now().microsecondsSinceEpoch}';
    var lastFraction = 0.0;
    final subscription = CompressChannel.events().listen((event) {
      if (event['jobId'] != jobId) return;
      final stage = event['stage'] as String? ?? 'Memproses';
      final pages = (event['pages'] as num?)?.toInt() ?? 0;
      final page = (event['page'] as num?)?.toInt() ?? 0;
      final double fraction;
      final String label;
      if (pages > 0) {
        fraction = (page / pages).clamp(0.0, 1.0);
        label = '$stage • halaman $page/$pages';
      } else {
        fraction = (event['fraction'] as num?)?.toDouble() ?? 0;
        label = stage;
      }
      // Retry passes restart the page counter; keep the bar monotonic.
      if (fraction < lastFraction) return;
      lastFraction = fraction;
      onProgress(fraction, label);
    });

    CompressChannel.bindJob(jobId);
    try {
      final result = await CompressChannel.methods
          .invokeMapMethod<String, dynamic>('compressPdf', {
            'jobId': jobId,
            'inputPath': source.path,
            'outputPath': outputPath,
            'mode': options.pdfMode == PdfMode.raster ? 'raster' : 'light',
            'targetBytes': target,
            'quality': options.pdfMode == PdfMode.light
                ? (target != null ? 84 : 72)
                : 80,
            'minQuality': options.pdfMode == PdfMode.light ? 45 : 30,
            'maxQuality': options.pdfMode == PdfMode.light ? 90 : 92,
            'maxDpi': options.pdfDpi,
          })
          .timeout(_pdfTimeout);

      if (result == null) {
        throw const CompressionFailure('Tidak ada hasil dari mesin kompresi.');
      }

      final outputBytes =
          (result['afterBytes'] as num?)?.toInt() ??
          await File(outputPath).length();
      final pages = (result['pages'] as num?)?.toInt();
      final note = result['note'] as String?;

      // A text-only PDF has nothing to re-encode, and rewriting the structure
      // can make it slightly larger. Give back the original instead.
      if (outputBytes >= file.bytes) {
        await source.copy(outputPath);
        return CompressionOutcome(
          outputPath: outputPath,
          outputBytes: await File(outputPath).length(),
          pages: pages ?? file.pages,
          outputExtension: 'pdf',
          note: 'Sudah optimal, file asli dipertahankan.',
        );
      }

      onProgress(1, 'Selesai');
      return CompressionOutcome(
        outputPath: outputPath,
        outputBytes: outputBytes,
        pages: pages,
        outputExtension: 'pdf',
        note: note,
      );
    } on TimeoutException {
      throw const CompressionFailure(
        'Proses terlalu lama dan dihentikan. Coba mode Ringan atau pecah dokumennya.',
      );
    } on PlatformException catch (error) {
      if (error.code == 'CompressCancelled') throw const CompressionCancelled();
      throw CompressionFailure(_friendly(error), cause: error);
    } finally {
      CompressChannel.releaseJob(jobId);
      await subscription.cancel();
    }
  }

  String _friendly(PlatformException error) {
    switch (error.code) {
      case 'OutOfMemoryError':
        return 'PDF terlalu besar untuk diproses di HP ini. Coba mode Agresif atau pecah dokumennya.';
      case 'SecurityException':
        return 'PDF terkunci password. Buka dulu di aplikasi PDF lain, lalu simpan tanpa password.';
      case 'IllegalStateException':
        return error.message ?? 'PDF gagal dikompres.';
      case 'IllegalArgumentException':
        return error.message ?? 'PDF tidak bisa dibaca.';
      default:
        return error.message ?? 'PDF gagal dikompres (${error.code}).';
    }
  }
}

/// Page count for the setup screen. Best effort: a locked or damaged PDF simply
/// reports no pages instead of blocking the flow.
Future<int?> readPdfPages(String path) async {
  try {
    final info = await CompressChannel.methods
        .invokeMapMethod<String, dynamic>('getPdfInfo', {'path': path})
        .timeout(const Duration(seconds: 6));
    final pages = (info?['pages'] as num?)?.toInt();
    return pages == 0 ? null : pages;
  } catch (_) {
    return null;
  }
}
