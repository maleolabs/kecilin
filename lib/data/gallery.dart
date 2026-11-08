import 'dart:io';

import 'package:flutter/services.dart';

import '../core/format.dart';
import '../domain/models.dart';
import 'image_engine.dart';

/// How much of the device gallery Kecilin is allowed to see.
enum GalleryAccess { granted, partial, denied, unavailable }

/// Entries per page request. Big enough that a normal phone screen is filled
/// several times over, small enough that the first paint is quick.
const galleryPageSize = 60;

/// How many images the "Pakai riwayat Kecilin" fallback may show.
const galleryHistoryLimit = 40;

/// One thumbnail in the picker grid.
///
/// [id] is the native gallery id, or `null` when the entry comes from the
/// history fallback. [path] is the thumbnail file for native entries and the
/// original source file for fallback entries, so both can be rendered with
/// `Image.file` without extra plumbing.
class GalleryEntry {
  const GalleryEntry({
    required this.id,
    required this.path,
    required this.name,
    required this.bytes,
    this.width,
    this.height,
    this.dateAdded = 0,
  });

  final int? id;
  final String path;
  final String name;
  final int bytes;
  final int? width;
  final int? height;
  final int dateAdded;

  bool get isNative => id != null;

  /// Stable identity across pages and sources. Native ids are unique per
  /// device, fallback entries are unique per path.
  String get key => id == null ? 'path:$path' : 'id:$id';
}

class GalleryPage {
  const GalleryPage({required this.items, required this.hasMore});

  final List<GalleryEntry> items;
  final bool hasMore;

  static const empty = GalleryPage(items: [], hasMore: false);
}

/// Thin, failure-tolerant client for the `com.maleolabs.kecilin/gallery` channel.
///
/// Every call degrades instead of throwing: a missing plugin (old build), a
/// platform error, or a `null` reply must never take the picker sheet down.
class GalleryService {
  const GalleryService();

  static const MethodChannel channel = MethodChannel(
    'com.maleolabs.kecilin/gallery',
  );

  Future<GalleryAccess> status() async =>
      await _access('status', const Duration(seconds: 6)) ??
      GalleryAccess.unavailable;

  /// Shows the system permission dialog. Safe to call repeatedly: on Android
  /// the second call for a permanently denied permission resolves immediately.
  ///
  /// The reply only arrives after the user answers, and on Android 14+ that can
  /// include the system photo-selection screen, so the timeout is generous. If
  /// it still expires, the dialog is presumably open and `status` is the only
  /// honest answer — never report the gallery as unavailable.
  Future<GalleryAccess> request() async {
    final access = await _access('request', const Duration(minutes: 5));
    return access ?? status();
  }

  Future<GalleryAccess?> _access(String method, Duration timeout) async {
    try {
      final raw = await channel.invokeMethod<Object?>(method).timeout(timeout);
      if (raw is! Map) return GalleryAccess.unavailable;
      return switch (raw['access']) {
        'granted' => GalleryAccess.granted,
        'partial' => GalleryAccess.partial,
        'denied' => GalleryAccess.denied,
        _ => GalleryAccess.unavailable,
      };
    } catch (_) {
      // MissingPluginException, PlatformException, timeout: the caller decides
      // what a failed probe means.
      return null;
    }
  }

  /// Returns `null` when the page could not be loaded (the sheet then offers a
  /// retry). A `null` native reply is a valid empty page, not a failure.
  Future<GalleryPage?> page({
    required int offset,
    int limit = galleryPageSize,
  }) async {
    try {
      final raw = await channel
          .invokeMapMethod<String, dynamic>('page', {
            'offset': offset,
            'limit': limit,
          })
          .timeout(const Duration(seconds: 15));
      if (raw == null) return GalleryPage.empty;

      final items = <GalleryEntry>[];
      final rawItems = raw['items'];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is! Map) continue;
          final entry = _parseEntry(item);
          if (entry != null) items.add(entry);
        }
      }

      // `hasMore` on an empty page would make the grid spin forever.
      final hasMore = raw['hasMore'] == true && items.isNotEmpty;
      return GalleryPage(items: items, hasMore: hasMore);
    } catch (_) {
      return null;
    }
  }

  /// Copies the original into the app cache and returns a path the compression
  /// engine can read. `null` means this one file has to be skipped.
  Future<SelectedFile?> materialize(int id) async {
    try {
      final raw = await channel
          .invokeMapMethod<String, dynamic>('materialize', {'id': id})
          .timeout(const Duration(seconds: 30));
      if (raw == null) return null;

      final path = raw['path'] as String? ?? '';
      if (path.isEmpty) return null;

      final file = File(path);
      if (!file.existsSync()) return null;

      var bytes = (raw['bytes'] as num?)?.toInt() ?? 0;
      if (bytes <= 0) {
        try {
          bytes = await file.length();
        } catch (_) {
          return null;
        }
      }

      final rawName = (raw['name'] as String?)?.trim() ?? '';
      var width = _positive(raw['width']);
      var height = _positive(raw['height']);
      if (width == null || height == null) {
        // The compressor shows "W × H px" in the setup summary, so a missing
        // pair is worth one cheap header read.
        final size = await readImageSize(path);
        width ??= size?.width;
        height ??= size?.height;
      }

      return SelectedFile(
        path: path,
        name: rawName.isEmpty ? baseName(path) : rawName,
        bytes: bytes,
        kind: MediaKind.image,
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    }
  }

  /// Best-effort cache cleanup. Never throws, returns the freed bytes when the
  /// native side reports them.
  Future<int> clearCache() async {
    try {
      final raw = await channel.invokeMapMethod<String, dynamic>('clearCache');
      return (raw?['freedBytes'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  GalleryEntry? _parseEntry(Map<Object?, Object?> raw) {
    final id = (raw['id'] as num?)?.toInt();
    final thumbPath = raw['thumbPath'] as String? ?? '';
    // Native keeps a row when thumbnail generation fails so pagination stays
    // stable. The grid renders its normal broken-image placeholder for "".
    if (id == null) return null;

    final rawName = (raw['name'] as String?)?.trim() ?? '';
    return GalleryEntry(
      id: id,
      path: thumbPath,
      name: rawName.isEmpty ? 'Gambar $id' : rawName,
      bytes: (raw['bytes'] as num?)?.toInt() ?? 0,
      width: _positive(raw['width']),
      height: _positive(raw['height']),
      dateAdded: (raw['dateAdded'] as num?)?.toInt() ?? 0,
    );
  }

  static int? _positive(Object? value) {
    final number = (value as num?)?.toInt();
    return number == null || number <= 0 ? null : number;
  }
}

/// Grid entries built from Kecilin's own history, so the picker still works
/// when the user refuses the gallery permission. Newest first, deduped by path,
/// capped at [galleryHistoryLimit].
List<GalleryEntry> historyEntries(Iterable<JobResult> items) {
  final entries = <GalleryEntry>[];
  final seen = <String>{};

  for (final item in items) {
    if (item.kind != MediaKind.image) continue;
    final path = item.sourcePath;
    if (path.isEmpty || !seen.add(path)) continue;
    if (!File(path).existsSync()) continue;

    entries.add(
      GalleryEntry(
        id: null,
        path: path,
        name: baseName(path),
        bytes: item.sourceBytes,
      ),
    );
    if (entries.length >= galleryHistoryLimit) break;
  }

  return entries;
}
