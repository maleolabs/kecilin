import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

class SettingsStore extends ChangeNotifier {
  SettingsStore._(
    this._preferences,
    this._themeMode,
    this._autoSave,
    this._lastOptions,
  );

  static const _key = 'settings.v2';

  final SharedPreferences _preferences;
  ThemeMode _themeMode;
  bool _autoSave;
  CompressionOptions _lastOptions;

  static Future<SettingsStore> create() async {
    final preferences = await SharedPreferences.getInstance();
    var themeMode = ThemeMode.system;
    var autoSave = true;
    var options = const CompressionOptions();

    final raw = preferences.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        themeMode = ThemeMode.values.firstWhere(
          (value) => value.name == json['themeMode'],
          orElse: () => ThemeMode.system,
        );
        autoSave = json['autoSave'] as bool? ?? true;
        final optionsJson = json['options'];
        if (optionsJson is Map) {
          options = CompressionOptions.fromJson(
            Map<String, dynamic>.from(optionsJson),
          );
        }
      } catch (_) {
        // Fall back to defaults when the stored payload is unreadable.
      }
    }

    return SettingsStore._(preferences, themeMode, autoSave, options);
  }

  ThemeMode get themeMode => _themeMode;

  bool get autoSaveToDownloads => _autoSave;

  CompressionOptions get lastOptions => _lastOptions;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _persist();
    notifyListeners();
  }

  Future<void> setAutoSaveToDownloads(bool value) async {
    if (_autoSave == value) return;
    _autoSave = value;
    await _persist();
    notifyListeners();
  }

  Future<void> rememberOptions(CompressionOptions options) async {
    _lastOptions = options;
    await _persist();
  }

  Future<void> _persist() async {
    await _preferences.setString(
      _key,
      jsonEncode({
        'themeMode': _themeMode.name,
        'autoSave': _autoSave,
        'options': _lastOptions.toJson(),
      }),
    );
  }
}
