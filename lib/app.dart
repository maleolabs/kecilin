import 'package:flutter/material.dart';

import 'core/app_version.dart';
import 'core/changelog.dart';
import 'data/history_store.dart';
import 'data/settings_store.dart';
import 'feature/home_screen.dart';
import 'state/compression_controller.dart';
import 'ui/announcements.dart';
import 'ui/app_theme.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.controller,
    required this.history,
    required this.settings,
    required super.child,
  });

  final CompressionController controller;
  final HistoryStore history;
  final SettingsStore settings;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      controller != oldWidget.controller ||
      history != oldWidget.history ||
      settings != oldWidget.settings;
}

class KecilinApp extends StatefulWidget {
  const KecilinApp({
    super.key,
    required this.controller,
    required this.history,
    required this.settings,
  });

  final CompressionController controller;
  final HistoryStore history;
  final SettingsStore settings;

  @override
  State<KecilinApp> createState() => _KecilinAppState();
}

class _KecilinAppState extends State<KecilinApp> {
  /// Context di bawah MaterialApp agar theme extension terbaca saat modal
  /// dibuka dari post-frame callback.
  static final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAnnouncementGate());
  }

  /// Gerbang popup lokal: versi tersimpan vs versi build saat ini.
  /// Null = instal pertama (sambutan); lebih baru = setelah update (changelog).
  /// Tidak ada jaringan — deteksi murni dari perbandingan versi lokal.
  Future<void> _runAnnouncementGate() async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final settings = widget.settings;
    final seen = settings.seenVersion;
    if (seen == null) {
      await showWelcomeModal(context);
    } else if (isNewerVersion(appVersion, seen)) {
      await showChangelogModal(context);
    } else {
      return;
    }
    await settings.markVersionSeen(appVersion);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      history: widget.history,
      settings: widget.settings,
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'Kecilin',
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigatorKey,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: widget.settings.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
