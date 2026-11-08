import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kecilin/data/history_store.dart';
import 'package:kecilin/data/output_store.dart';
import 'package:kecilin/data/settings_store.dart';
import 'package:kecilin/domain/compression_engine.dart';
import 'package:kecilin/domain/models.dart';
import 'package:kecilin/state/compression_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeEngine implements CompressionEngine {
  _FakeEngine({
    required this.kind,
    this.outputBytes = 400,
    this.failWith,
    this.cancel = false,
  });

  @override
  final MediaKind kind;

  final int outputBytes;
  final String? failWith;
  final bool cancel;
  int calls = 0;

  @override
  Future<CompressionOutcome> compress({
    required SelectedFile file,
    required CompressionOptions options,
    required String outputPath,
    required ProgressCallback onProgress,
    required CancelCheck isCancelled,
  }) async {
    calls++;
    onProgress(0.5, 'setengah');
    if (cancel) throw const CompressionCancelled();
    if (failWith != null) throw CompressionFailure(failWith!);
    onProgress(1, 'selesai');
    return CompressionOutcome(
      outputPath: outputPath,
      outputBytes: outputBytes,
      note: 'ok',
    );
  }
}

class _FakeOutputs implements OutputTarget {
  int saves = 0;

  @override
  Future<String> nextPath(SelectedFile file, CompressionOptions options) async {
    final extension = file.kind == MediaKind.pdf
        ? 'pdf'
        : (options.format == OutputFormat.webp ? 'webp' : 'jpg');
    return '${Directory.systemTemp.path}/kecilin-test-${file.name}-kecil.$extension';
  }

  @override
  Future<String?> saveToDownloads(
    File file, {
    required String displayName,
    required String mime,
  }) async {
    saves++;
    return 'Download/Kecilin/$displayName';
  }

  @override
  String mimeFor(MediaKind kind, OutputFormat format, {String? extension}) =>
      kind == MediaKind.pdf ? 'application/pdf' : 'image/jpeg';

  @override
  Future<int> totalOutputBytes() async => 0;

  @override
  Future<void> clear() async {}
}

SelectedFile _file(
  String name, {
  int bytes = 1000,
  MediaKind kind = MediaKind.image,
}) {
  return SelectedFile(path: '/tmp/$name', name: name, bytes: bytes, kind: kind);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HistoryStore history;
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    history = await HistoryStore.create();
    settings = await SettingsStore.create();
  });

  CompressionController build({
    required CompressionEngine imageEngine,
    required CompressionEngine pdfEngine,
    OutputTarget? outputs,
  }) {
    return CompressionController(
      imageEngine: imageEngine,
      pdfEngine: pdfEngine,
      outputs: outputs ?? _FakeOutputs(),
      history: history,
      settings: settings,
    );
  }

  test('runs every selected file and records the savings', () async {
    final engine = _FakeEngine(kind: MediaKind.image, outputBytes: 250);
    final controller = build(
      imageEngine: engine,
      pdfEngine: _FakeEngine(kind: MediaKind.pdf),
    );
    controller.addFiles([
      _file('dokumen.jpg', bytes: 1000),
      _file('kk-contoh.jpg', bytes: 2000),
    ]);

    expect(controller.totalBytes, 3000);

    final report = await controller.run();

    expect(engine.calls, 2);
    expect(report.results, hasLength(2));
    expect(report.failures, isEmpty);
    expect(report.totalSourceBytes, 3000);
    expect(report.totalOutputBytes, 500);
    expect(report.totalSavedBytes, 2500);
    expect(history.items, hasLength(2));
    expect(controller.running, isFalse);
    expect(controller.progress, isNull);
  });

  test('keeps going when one file fails', () async {
    final failing = _FakeEngine(kind: MediaKind.image, failWith: 'rusak');
    final controller = build(
      imageEngine: failing,
      pdfEngine: _FakeEngine(kind: MediaKind.pdf),
    );
    controller.addFiles([_file('a.jpg'), _file('b.jpg')]);

    final report = await controller.run();

    expect(report.failures, hasLength(2));
    expect(report.failures.first.message, 'rusak');
    expect(report.results, isEmpty);
  });

  test('stops after the active file is cancelled', () async {
    final engine = _FakeEngine(kind: MediaKind.image, cancel: true);
    final controller = build(
      imageEngine: engine,
      pdfEngine: _FakeEngine(kind: MediaKind.pdf),
    );
    controller.addFiles([_file('a.jpg'), _file('b.jpg')]);

    final report = await controller.run();

    expect(engine.calls, 1);
    expect(report.results, isEmpty);
    expect(report.failures, isEmpty);
    expect(controller.running, isFalse);
  });

  test('auto-save copies results to Downloads when enabled', () async {
    final outputs = _FakeOutputs();
    final controller = build(
      imageEngine: _FakeEngine(kind: MediaKind.image),
      pdfEngine: _FakeEngine(kind: MediaKind.pdf),
      outputs: outputs,
    );
    controller.addFiles([_file('dokumen.jpg')]);

    final report = await controller.run();

    expect(outputs.saves, 1);
    expect(
      report.results.single.savedToDownloads,
      startsWith('Download/Kecilin/'),
    );
  });

  test('compression options survive a JSON round trip', () {
    const options = CompressionOptions(
      imageMode: ImageMode.quality,
      imageQuality: 62,
      format: OutputFormat.webp,
      maxEdge: 1600,
      pdfMode: PdfMode.raster,
      pdfDpi: 200,
      targetBytes: null,
    );

    final restored = CompressionOptions.fromJson(options.toJson());

    expect(restored.imageMode, ImageMode.quality);
    expect(restored.imageQuality, 62);
    expect(restored.format, OutputFormat.webp);
    expect(restored.maxEdge, 1600);
    expect(restored.pdfMode, PdfMode.raster);
    expect(restored.pdfDpi, 200);
    expect(restored.targetBytes, isNull);
  });

  test('copyWith can clear the target', () {
    const options = CompressionOptions(targetBytes: 204800);
    expect(options.copyWith(targetBytes: 102400).targetBytes, 102400);
    expect(options.copyWith(clearTarget: true).targetBytes, isNull);
  });

  test('run report reports zero savings for empty results', () {
    const report = RunReport(results: [], failures: []);
    expect(report.savedRatio, 0);
    expect(report.totalSavedBytes, 0);
  });
}
