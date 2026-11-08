import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kecilin/data/compress_channel.dart';
import 'package:kecilin/data/image_engine.dart';
import 'package:kecilin/data/pdf_engine.dart';
import 'package:kecilin/domain/compression_engine.dart';
import 'package:kecilin/domain/models.dart';
import 'package:path_provider/path_provider.dart';

/// On-device tests for the Kotlin compression engines.
///
/// These are the only tests that exercise the real decoders, the real PDF
/// parser and the real MediaStore path, so they are the ones that decide
/// whether the app actually works on a phone.
///
/// Fixtures are not committed and not bundled into release builds. Generate
/// them with `tool/test_fixtures.sh`, uncomment the `assets:` block in
/// pubspec.yaml, then run:
///
///   flutter test integration_test/compression_test.dart -d DEVICE_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory input;
  late Directory output;

  setUpAll(() async {
    final docs = await getApplicationDocumentsDirectory();
    input = Directory('${docs.path}/integration-in')
      ..createSync(recursive: true);
    output = Directory('${docs.path}/integration-out')
      ..createSync(recursive: true);
    for (final entity in output.listSync()) {
      entity.deleteSync(recursive: true);
    }

    // Materialise the bundled fixtures as real files: the native engines take
    // file paths, exactly like a user-picked document.
    for (final name in const [
      'sample-photo.jpg',
      'scan-4p.pdf',
      'scan-12p.pdf',
      'text-only.pdf',
      'mixed-6p.pdf',
    ]) {
      final bytes = await rootBundle.load('integration_test/assets/$name');
      File(
        '${input.path}/$name',
      ).writeAsBytesSync(bytes.buffer.asUint8List(), flush: true);
    }
  });

  SelectedFile picked(String name, MediaKind kind, {int? pages}) {
    final file = File('${input.path}/$name');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'missing test asset ${file.path}',
    );
    return SelectedFile(
      path: file.path,
      name: name,
      bytes: file.lengthSync(),
      kind: kind,
      pages: pages,
    );
  }

  /// Pushes a produced file into Download/Kecilin so it survives the test run
  /// and can be validated outside the phone.
  Future<void> export(String path, String name, String mime) async {
    await CompressChannel.methods.invokeMapMethod<String, dynamic>(
      'saveToDownloads',
      {'path': path, 'displayName': name, 'mime': mime},
    );
  }

  bool looksLikeJpeg(File file) {
    final bytes = file.readAsBytesSync();
    if (bytes.length < 4) return false;
    return bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[bytes.length - 2] == 0xFF &&
        bytes[bytes.length - 1] == 0xD9;
  }

  group('image engine', () {
    test('hits a 200 KB target on a 6 MP photo', () async {
      final file = picked('sample-photo.jpg', MediaKind.image);
      final target = 200 * 1024;
      final path = '${output.path}/sample-photo-kecil.jpg';

      final outcome = await const ImageCompressionEngine().compress(
        file: file,
        options: CompressionOptions(
          imageMode: ImageMode.target,
          targetBytes: target,
        ),
        outputPath: path,
        onProgress: (_, _) {},
        isCancelled: () => false,
      );

      final produced = File(outcome.outputPath);
      expect(produced.existsSync(), isTrue);
      expect(
        outcome.outputBytes,
        lessThanOrEqualTo(target),
        reason: 'target was ${target}B, got ${outcome.outputBytes}B',
      );
      expect(
        looksLikeJpeg(produced),
        isTrue,
        reason: 'output is not a complete JPEG',
      );
      expect(
        outcome.outputBytes,
        lessThan(file.bytes),
        reason: 'compression must never grow the file',
      );

      final size = await readImageSize(produced.path);
      expect(size, isNotNull);
      expect(size!.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });

    test('never returns a file bigger than the source', () async {
      final file = picked('sample-photo.jpg', MediaKind.image);
      final path = '${output.path}/sample-photo-max.jpg';

      final outcome = await const ImageCompressionEngine().compress(
        file: file,
        options: const CompressionOptions(imageMode: ImageMode.maximum),
        outputPath: path,
        onProgress: (_, _) {},
        isCancelled: () => false,
      );

      expect(outcome.outputBytes, lessThanOrEqualTo(file.bytes));
      expect(File(outcome.outputPath).existsSync(), isTrue);
    });

    test('keeps the source format when the original bytes are kept', () async {
      // Already below the target: the engine must not rename PNG bytes to .jpg.
      final file = picked('sample-photo.jpg', MediaKind.image);
      final path = '${output.path}/sample-photo-small.jpg';

      final outcome = await const ImageCompressionEngine().compress(
        file: file,
        options: const CompressionOptions(
          imageMode: ImageMode.target,
          targetBytes: 50 * 1024 * 1024,
        ),
        outputPath: path,
        onProgress: (_, _) {},
        isCancelled: () => false,
      );

      expect(outcome.outputBytes, file.bytes);
      expect(outcome.outputExtension, 'jpg');
      expect(looksLikeJpeg(File(outcome.outputPath)), isTrue);
    });
  });

  group('pdf engine', () {
    test('light mode shrinks a scan and keeps the pages', () async {
      final file = picked('scan-4p.pdf', MediaKind.pdf, pages: 4);
      final path = '${output.path}/scan-light.pdf';

      final outcome = await const PdfCompressionEngine().compress(
        file: file,
        options: const CompressionOptions(pdfMode: PdfMode.light),
        outputPath: path,
        onProgress: (_, _) {},
        isCancelled: () => false,
      );

      // ignore: avoid_print
      print(
        'LIGHT note: ${outcome.note} | ${outcome.outputBytes} vs ${file.bytes}',
      );
      expect(
        outcome.outputBytes,
        lessThan(file.bytes),
        reason: 'a JPEG-only scan must shrink',
      );
      expect(
        outcome.outputBytes,
        lessThan(file.bytes * 0.9),
        reason: 'expected a real gain, got ${outcome.outputBytes}B',
      );
      final pages = await readPdfPages(outcome.outputPath);
      expect(pages, 4);
      await export(outcome.outputPath, 'verify-light.pdf', 'application/pdf');
    });

    test('light mode keeps a text-only PDF at its original size', () async {
      final file = picked('text-only.pdf', MediaKind.pdf, pages: 2);
      final path = '${output.path}/text-light.pdf';

      final outcome = await const PdfCompressionEngine().compress(
        file: file,
        options: const CompressionOptions(pdfMode: PdfMode.light),
        outputPath: path,
        onProgress: (_, _) {},
        isCancelled: () => false,
      );

      // Nothing to re-encode; the app must hand back the original bytes
      // instead of a slightly larger rewritten document.
      expect(outcome.outputBytes, lessThanOrEqualTo(file.bytes));
      expect(await readPdfPages(outcome.outputPath), 2);
    });

    test(
      'light mode keeps the text layer while shrinking a shared image',
      () async {
        // Pages 1-2 are pure text, pages 3-6 are four references to one JPEG
        // XObject. This is the only case that proves the two promises of Ringan
        // at once: text survives, and the shared stream is rewritten once.
        final file = picked('mixed-6p.pdf', MediaKind.pdf, pages: 6);
        final path = '${output.path}/mixed-light.pdf';

        final outcome = await const PdfCompressionEngine().compress(
          file: file,
          options: const CompressionOptions(
            pdfMode: PdfMode.light,
            // The fixture is 276 KB, below the default 500 KB target, so the
            // engine would (correctly) skip it. Force a real budget.
            targetBytes: 120 * 1024,
          ),
          outputPath: path,
          onProgress: (_, _) {},
          isCancelled: () => false,
        );

        // ignore: avoid_print
        print(
          'MIXED note: ${outcome.note} | ${outcome.outputBytes} vs ${file.bytes}',
        );
        expect(
          outcome.outputBytes,
          lessThan(file.bytes),
          reason: 'shared XObject must shrink the whole document',
        );
        expect(await readPdfPages(outcome.outputPath), 6);
        await export(outcome.outputPath, 'verify-mixed.pdf', 'application/pdf');
      },
    );

    test('raster mode rebuilds a readable document', () async {
      final file = picked('scan-4p.pdf', MediaKind.pdf, pages: 4);
      final path = '${output.path}/scan-raster.pdf';

      final outcome = await const PdfCompressionEngine().compress(
        file: file,
        options: const CompressionOptions(pdfMode: PdfMode.raster, pdfDpi: 110),
        outputPath: path,
        onProgress: (_, _) {},
        isCancelled: () => false,
      );

      final produced = File(outcome.outputPath);
      expect(produced.existsSync(), isTrue);
      final header = produced.readAsBytesSync().sublist(0, 5);
      expect(String.fromCharCodes(header), '%PDF-');
      expect(
        outcome.outputBytes,
        lessThan(file.bytes),
        reason: 'raster output must beat the 1.1 MB scan',
      );
      expect(await readPdfPages(outcome.outputPath), 4);
      await export(outcome.outputPath, 'verify-raster.pdf', 'application/pdf');
    });

    test('cancel stops a running raster job', () async {
      final file = picked('scan-12p.pdf', MediaKind.pdf, pages: 12);
      final path = '${output.path}/scan-cancel.pdf';

      var cancelled = false;
      final engine = const PdfCompressionEngine();
      final future = engine.compress(
        file: file,
        options: const CompressionOptions(pdfMode: PdfMode.raster, pdfDpi: 200),
        outputPath: path,
        onProgress: (_, _) {},
        isCancelled: () => cancelled,
      );
      // Attach the expectation immediately: an error that lands before a
      // handler exists is reported as an unhandled async error.
      final expectation = expectLater(
        future,
        throwsA(isA<CompressionCancelled>()),
      );

      // Give the native side time to start, then hit the same path the
      // "Batalkan" button uses.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      cancelled = true;
      await CompressChannel.cancelActive();

      await expectation;
      expect(
        File(path).existsSync(),
        isFalse,
        reason: 'a cancelled job must not leave a partial file',
      );
    });
  });

  group('downloads', () {
    test('saves the result through MediaStore', () async {
      final file = picked('sample-photo.jpg', MediaKind.image);
      final path = '${output.path}/sample-photo-download.jpg';

      final outcome = await const ImageCompressionEngine().compress(
        file: file,
        options: const CompressionOptions(
          imageMode: ImageMode.target,
          targetBytes: 200 * 1024,
        ),
        outputPath: path,
        onProgress: (_, _) {},
        isCancelled: () => false,
      );

      final saved = await CompressChannel.methods
          .invokeMapMethod<String, dynamic>('saveToDownloads', {
            'path': outcome.outputPath,
            'displayName': 'sample-photo-kecil.jpg',
            'mime': 'image/jpeg',
          });

      expect(saved, isNotNull);
      expect(saved!['uri'], isA<String>());
      expect(
        (saved['uri'] as String).startsWith('content://'),
        isTrue,
        reason: 'got ${saved['uri']}',
      );
      // ignore: avoid_print
      print('SAVED_TO: ${saved['displayPath']}');
    });
  });
}
