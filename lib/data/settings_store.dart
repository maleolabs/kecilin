import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/changelog.dart';
import '../domain/models.dart';

class SettingsStore extends ChangeNotifier {
  SettingsStore._(
    this._preferences,
    this._themeMode,
    this._autoSave,
    this._lastOptions,
    this._seenVersion,
  );

  static const _key = 'settings.v2';

  final SharedPreferences _preferences;
  ThemeMode _themeMode;
  bool _autoSave;
  CompressionOptions _lastOptions;

  /// Versi aplikasi yang terakhir menampilkan sambutan/changelog. Null =
  /// pengguna baru (instal pertama).
  String? _seenVersion;

  static Future<SettingsStore> create() async {
    final preferences = await SharedPreferences.getInstance();
    var themeMode = ThemeMode.system;
    var autoSave = true;
    var options = const CompressionOptions();
    String? seenVersion;

    final raw = preferences.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        themeMode = ThemeMode.values.firstWhere(
          (value) => value.name == json['themeMode'],
          orElse: () => ThemeMode.system,
        );
        autoSave = json['autoSave'] as bool? ?? true;
        seenVersion = json['seenVersion'] as String?;
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

    return SettingsStore._(
      preferences,
      themeMode,
      autoSave,
      options,
      seenVersion,
    );
  }

  ThemeMode get themeMode => _themeMode;

  bool get autoSaveToDownloads => _autoSave;

  CompressionOptions get lastOptions => _lastOptions;

  String? get seenVersion => _seenVersion;

  Future<void> markVersionSeen(String version) async {
    // Downgrade tidak menimpa riwayat yang lebih baru; popup tidak berulang
    // saat pengguna kembali ke versi lama lalu update lagi.
    if (_seenVersion != null && !isNewerVersion(version, _seenVersion!)) return;
    _seenVersion = version;
    await _persist();
  }

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
        if (_seenVersion != null) 'seenVersion': _seenVersion,
      }),
    );
  }
}
