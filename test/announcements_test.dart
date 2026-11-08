import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kecilin/app.dart';
import 'package:kecilin/core/app_version.dart';
import 'package:kecilin/core/changelog.dart';
import 'package:kecilin/data/history_store.dart';
import 'package:kecilin/data/output_store.dart';
import 'package:kecilin/data/settings_store.dart';
import 'package:kecilin/domain/compression_engine.dart';
import 'package:kecilin/domain/models.dart';
import 'package:kecilin/state/compression_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeEngine implements CompressionEngine {
  const _FakeEngine();

  @override
  MediaKind get kind => MediaKind.image;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by modals');
}

class _FakeOutputs implements OutputTarget {
  const _FakeOutputs();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by modals');
}

Future<KecilinApp> _app({String? seenVersion}) async {
  SharedPreferences.setMockInitialValues({
    if (seenVersion != null)
      'settings.v2': jsonEncode({
        'themeMode': 'system',
        'autoSave': true,
        'seenVersion': seenVersion,
      }),
  });
  final history = await HistoryStore.create();
  final settings = await SettingsStore.create();
  final controller = CompressionController(
    imageEngine: const _FakeEngine(),
    pdfEngine: const _FakeEngine(),
    outputs: const _FakeOutputs(),
    history: history,
    settings: settings,
  );
  return KecilinApp(
    controller: controller,
    history: history,
    settings: settings,
  );
}

void main() {
  group('isNewerVersion', () {
    test('compares semver segments numerically', () {
      expect(isNewerVersion('1.1.0', '1.0.0'), isTrue);
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.0.0', '1.1.0'), isFalse);
      expect(isNewerVersion('1.1.0', '1.1.0'), isFalse);
    });

    test('fails safe on malformed input', () {
      expect(isNewerVersion('abc', '1.0.0'), isFalse);
      expect(isNewerVersion('1.1.0', ''), isTrue);
    });
  });

  testWidgets(
    'instal pertama menampilkan modal sambutan lalu menyimpan versi',
    (tester) async {
      final app = await _app();
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Mengerti, Mulai'), findsOneWidget);
      expect(find.text('Privasi & Keamanan'), findsOneWidget);
      expect(find.text('Kompres gambar'), findsOneWidget);

      final settings = app.settings;
      expect(settings.seenVersion, isNull);
      await tester.tap(find.text('Mengerti, Mulai'));
      await tester.pumpAndSettle();
      expect(settings.seenVersion, appVersion);
    },
  );

  testWidgets('setelah update menampilkan changelog lalu menyimpan versi', (
    tester,
  ) async {
    final app = await _app(seenVersion: '1.0.0');
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('Yang baru'), findsOneWidget);
    expect(find.text('v$appVersion'), findsOneWidget);
    expect(find.text('Tampilan baru'), findsOneWidget);

    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();
    expect(app.settings.seenVersion, appVersion);
  });

  testWidgets('versi sama tidak memunculkan popup', (tester) async {
    final app = await _app(seenVersion: appVersion);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('Mengerti, Mulai'), findsNothing);
    expect(find.text('Yang baru'), findsNothing);
  });
}
