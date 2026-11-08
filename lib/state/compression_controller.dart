import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../data/compress_channel.dart';
import '../data/history_store.dart';
import '../data/output_store.dart';
import '../data/settings_store.dart';
import '../domain/compression_engine.dart';
import '../domain/models.dart';

class CompressionController extends ChangeNotifier {
  CompressionController({
    required this.imageEngine,
    required this.pdfEngine,
    required this.outputs,
    required this.history,
    required this.settings,
    CompressionOptions? options,
  }) : _options = options ?? settings.lastOptions;

  final CompressionEngine imageEngine;
  final CompressionEngine pdfEngine;
  final OutputTarget outputs;
  final HistoryStore history;
  final SettingsStore settings;

  final List<SelectedFile> _selection = [];
  CompressionOptions _options;
  bool _running = false;
  bool _cancelRequested = false;
  RunProgress? _progress;
  RunReport? _report;

  List<SelectedFile> get selection => List.unmodifiable(_selection);

  CompressionOptions get options => _options;

  bool get running => _running;

  bool get cancelRequested => _cancelRequested;

  RunProgress? get progress => _progress;

  RunReport? get report => _report;

  int get totalBytes => _selection.fold(0, (sum, file) => sum + file.bytes);

  MediaKind? get selectionKind =>
      _selection.isEmpty ? null : _selection.first.kind;

  void addFiles(List<SelectedFile> files) {
    _selection
      ..clear()
      ..addAll(files);
    _report = null;
    notifyListeners();
  }

  void removeFile(SelectedFile file) {
    _selection.removeWhere((item) => item.path == file.path);
    notifyListeners();
  }

  void clearSelection() {
    _selection.clear();
    notifyListeners();
  }

  void updateOptions(CompressionOptions options) {
    _options = options;
    notifyListeners();
  }

  /// Replaces an entry in place once we know the page count.
  void enrichPdf(SelectedFile original, int pages) {
    final index = _selection.indexWhere((item) => item.path == original.path);
    if (index < 0) return;
    final current = _selection[index];
    _selection[index] = SelectedFile(
      path: current.path,
      name: current.name,
      bytes: current.bytes,
      kind: current.kind,
      width: current.width,
      height: current.height,
      pages: pages,
    );
    notifyListeners();
  }

  void requestCancel() {
    if (!_running || _cancelRequested) return;
    _cancelRequested = true;
    notifyListeners();
    // Tell the native engine too; without this the flag only stops the *next*
    // file and the user stays stuck on the progress screen.
    unawaited(CompressChannel.cancelActive());
  }

  void resetRun() {
    _report = null;
    _progress = null;
    _cancelRequested = false;
    notifyListeners();
  }

  Future<RunReport> run() async {
    if (_running || _selection.isEmpty) {
      return _report ?? const RunReport(results: [], failures: []);
    }

    _running = true;
    _cancelRequested = false;
    _report = null;
    notifyListeners();

    final results = <JobResult>[];
    final failures = <RunFailure>[];
    await settings.rememberOptions(_options);

    for (var index = 0; index < _selection.length; index++) {
      if (_cancelRequested) break;
      final file = _selection[index];
      final started = DateTime.now();
      String? outputPath;

      _progress = RunProgress(
        jobIndex: index,
        jobCount: _selection.length,
        fileName: file.name,
        fraction: 0,
        stage: 'Menyiapkan',
      );
      notifyListeners();

      try {
        final engine = file.kind == MediaKind.image ? imageEngine : pdfEngine;
        outputPath = await outputs.nextPath(file, _options);
        final outcome = await engine.compress(
          file: file,
          options: _options,
          outputPath: outputPath,
          onProgress: (fraction, stage) {
            _progress = RunProgress(
              jobIndex: index,
              jobCount: _selection.length,
              fileName: file.name,
              fraction: fraction,
              stage: stage,
            );
            notifyListeners();
          },
          isCancelled: () => _cancelRequested,
        );

        String? savedPath;
        if (settings.autoSaveToDownloads) {
          savedPath = await outputs.saveToDownloads(
            File(outcome.outputPath),
            displayName: baseName(outcome.outputPath),
            mime: outputs.mimeFor(
              file.kind,
              _options.format,
              extension: outcome.outputExtension,
            ),
          );
        }

        final result = JobResult(
          sourcePath: file.path,
          sourceName: file.name,
          outputPath: outcome.outputPath,
          kind: file.kind,
          sourceBytes: file.bytes,
          outputBytes: outcome.outputBytes,
          duration: DateTime.now().difference(started),
          pages: outcome.pages ?? file.pages,
          note: outcome.note,
          targetBytes: _options.targetBytes,
          savedToDownloads: savedPath,
        );
        results.add(result);
        // Losing the history entry is a cosmetic problem; it must never delete
        // an output file that was produced successfully.
        try {
          await history.add(result);
        } catch (_) {
          // Ignore: the result still shows on the result screen.
        }
      } on CompressionCancelled {
        _cancelRequested = true;
        if (outputPath != null) _discard(outputPath);
        break;
      } catch (error) {
        if (outputPath != null) _discard(outputPath);
        failures.add(
          RunFailure(fileName: file.name, message: describeError(error)),
        );
      }
    }

    _running = false;
    _progress = null;
    _report = RunReport(results: results, failures: failures);
    notifyListeners();
    return _report!;
  }

  void _discard(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best effort only.
    }
  }

  static String describeError(Object error) {
    if (error is CompressionFailure) return error.message;
    if (error is FileSystemException) {
      return 'Tidak bisa menulis file hasil. Cek ruang penyimpanan.';
    }
    if (error is PlatformException) {
      return error.message ?? 'Gagal memproses file (${error.code}).';
    }
    return 'Gagal memproses file: $error';
  }
}
