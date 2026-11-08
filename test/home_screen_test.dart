import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kecilin/app.dart';
import 'package:kecilin/data/history_store.dart';
import 'package:kecilin/data/output_store.dart';
import 'package:kecilin/data/settings_store.dart';
import 'package:kecilin/domain/compression_engine.dart';
import 'package:kecilin/domain/models.dart';
import 'package:kecilin/feature/home_screen.dart';
import 'package:kecilin/state/compression_controller.dart';
import 'package:kecilin/ui/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeEngine implements CompressionEngine {
  const _FakeEngine();

  @override
  MediaKind get kind => MediaKind.image;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by HomeScreen');
}

class _FakeOutputs implements OutputTarget {
  const _FakeOutputs();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by HomeScreen');
}

Future<Widget> _home({List<JobResult> history = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final preferencesHistory = await HistoryStore.create();
  final settings = await SettingsStore.create();
  for (final item in history) {
    await preferencesHistory.add(item);
  }
  final controller = CompressionController(
    imageEngine: const _FakeEngine(),
    pdfEngine: const _FakeEngine(),
    outputs: const _FakeOutputs(),
    history: preferencesHistory,
    settings: settings,
  );
  return AppScope(
    controller: controller,
    history: preferencesHistory,
    settings: settings,
    child: MaterialApp(theme: AppTheme.light(), home: HomeScreen()),
  );
}

void main() {
  testWidgets('CTA gambar & PDF tetap tampil saat riwayat kosong', (
    tester,
  ) async {
    await tester.pumpWidget(await _home());
    await tester.pump();

    expect(find.text('Mulai Kompresi Cepat'), findsOneWidget);
    expect(find.text('Foto & Gambar'), findsOneWidget);
    expect(find.text('Dokumen PDF'), findsOneWidget);
    expect(find.text('STATISTIK RUANG PENYIMPANAN'), findsNothing);
  });

  testWidgets('CTA gambar & PDF tetap tampil saat riwayat terisi', (
    tester,
  ) async {
    const item = JobResult(
      sourcePath: '/tmp/a.jpg',
      sourceName: 'a.jpg',
      outputPath: '/out/a-kecil.jpg',
      kind: MediaKind.image,
      sourceBytes: 1000,
      outputBytes: 500,
      duration: Duration(milliseconds: 10),
      finishedAt: null,
    );
    await tester.pumpWidget(await _home(history: const [item]));
    await tester.pump();

    expect(find.text('Foto & Gambar'), findsOneWidget);
    expect(find.text('Dokumen PDF'), findsOneWidget);
    expect(find.text('STATISTIK RUANG PENYIMPANAN'), findsOneWidget);
  });
}
