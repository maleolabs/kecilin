const int kb = 1024;
const int mb = 1024 * 1024;

String formatBytes(int bytes) {
  if (bytes < 0) bytes = 0;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) {
    final value = bytes / kb;
    return '${_trim(value, value < 10 ? 1 : 0)} KB';
  }
  final value = bytes / mb;
  return '${_trim(value, value < 10 ? 1 : 0)} MB';
}

String _trim(double value, int decimals) {
  final text = value.toStringAsFixed(decimals);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

String formatSavings(int savedBytes) {
  final sign = savedBytes >= 0 ? '−' : '+';
  return '$sign${formatBytes(savedBytes.abs())}';
}

String formatPercent(double ratio) {
  final percent = ratio * 100;
  if (percent.abs() >= 10) return '${percent.round()}%';
  return '${percent.toStringAsFixed(1)}%';
}

String formatDuration(Duration duration) {
  if (duration.inSeconds < 1) return '${duration.inMilliseconds} ms';
  if (duration.inMinutes < 1) return '${duration.inSeconds} dtk';
  final seconds = duration.inSeconds % 60;
  return '${duration.inMinutes} mnt $seconds dtk';
}

/// Waktu relatif singkat untuk baris riwayat, contoh: "5 mnt lalu", "Kemarin".
String formatRelativeTime(DateTime time) {
  final delta = DateTime.now().difference(time);
  if (delta.inMinutes < 1) return 'baru saja';
  if (delta.inMinutes < 60) return '${delta.inMinutes} mnt lalu';
  if (delta.inHours < 24) return '${delta.inHours} jam lalu';
  if (delta.inDays < 2) return 'Kemarin';
  if (delta.inDays < 7) return '${delta.inDays} hari lalu';
  return '${time.day}/${time.month}/${time.year}';
}

/// Parses "200kb", "1.5 MB", "750 KB" into bytes. Returns null when the input
/// has no explicit unit, because guessing the unit is how people lose files.
int? parseSize(String raw) {
  final text = raw.trim().toLowerCase().replaceAll(',', '.');
  final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(b|kb|mb|gb)$').firstMatch(text);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  final unit = match.group(2)!;
  final multiplier = switch (unit) {
    'b' => 1,
    'kb' => kb,
    'mb' => mb,
    _ => 1024 * mb,
  };
  final bytes = (value * multiplier).round();
  return bytes <= 0 ? null : bytes;
}

String extensionFor(String path) {
  final dot = path.lastIndexOf('.');
  if (dot <= 0 || dot == path.length - 1) return '';
  return path.substring(dot + 1).toLowerCase();
}

String baseName(String path) {
  final index = path.lastIndexOf(RegExp(r'[/\\]'));
  return index < 0 ? path : path.substring(index + 1);
}

String stemOf(String path) {
  final name = baseName(path);
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

/// Replaces the extension of [path] with [extension] (given without a dot).
String withExtension(String path, String extension) {
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  if (dot <= slash) return '$path.$extension';
  return '${path.substring(0, dot)}.$extension';
}

bool isJpegName(String name) {
  final ext = extensionFor(name);
  return ext == 'jpg' || ext == 'jpeg';
}

String sanitizeFileName(String name) {
  var cleaned = name
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
      // Bidi overrides make "ijazah\u202Efdp.exe.pdf" render as an .exe in
      // file managers, so they never survive into a file name we create.
      .replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '')
      .trim();
  // A trailing dot hides the real extension on most filesystems.
  cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '');
  if (cleaned.length > 100) cleaned = cleaned.substring(0, 100).trimRight();
  return cleaned.isEmpty ? 'berkas' : cleaned;
}
