import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

class HistoryStore extends ChangeNotifier {
  HistoryStore._(this._preferences, this._items);

  static const _key = 'history.v2';
  static const _limit = 40;

  final SharedPreferences _preferences;
  final List<JobResult> _items;

  static Future<HistoryStore> create() async {
    final preferences = await SharedPreferences.getInstance();
    final items = <JobResult>[];
    final raw = preferences.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final entry in jsonDecode(raw) as List) {
          items.add(
            JobResult.fromJson(Map<String, dynamic>.from(entry as Map)),
          );
        }
      } catch (_) {
        // Corrupted history is not worth a crash.
      }
    }
    return HistoryStore._(preferences, items);
  }

  List<JobResult> get items => List.unmodifiable(_items);

  int get totalSavedBytes =>
      _items.fold(0, (sum, item) => sum + item.savedBytes);

  int get totalSourceBytes =>
      _items.fold(0, (sum, item) => sum + item.sourceBytes);

  double get savingsRatio =>
      totalSourceBytes == 0 ? 0 : totalSavedBytes / totalSourceBytes;

  Future<void> add(JobResult result) async {
    _items.insert(0, result);
    if (_items.length > _limit) {
      _items.removeRange(_limit, _items.length);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    _items.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final payload = jsonEncode(_items.map((item) => item.toJson()).toList());
    await _preferences.setString(_key, payload);
  }
}
