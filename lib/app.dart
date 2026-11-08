import 'package:flutter/material.dart';

import 'data/history_store.dart';
import 'data/settings_store.dart';
import 'feature/home_screen.dart';
import 'state/compression_controller.dart';
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

class KecilinApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      history: history,
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'Kecilin',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
