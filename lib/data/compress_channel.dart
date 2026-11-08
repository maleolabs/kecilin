import 'package:flutter/services.dart';

/// Shared bridge to the native compression engines.
class CompressChannel {
  const CompressChannel();

  static const MethodChannel methods = MethodChannel(
    'com.maleolabs.kecilin/compress',
  );
  static const EventChannel _progress = EventChannel(
    'com.maleolabs.kecilin/progress',
  );

  /// The job currently in flight. Native work is serialised on a single thread,
  /// so one slot is enough and the cancel button always has something to target.
  static String? _activeJobId;

  static void bindJob(String jobId) => _activeJobId = jobId;

  static void releaseJob(String jobId) {
    if (_activeJobId == jobId) _activeJobId = null;
  }

  /// Asks the native engine to abort the running job. Fire and forget: the
  /// engine reports `CompressCancelled` through the normal result channel.
  static Future<void> cancelActive() async {
    final jobId = _activeJobId;
    if (jobId == null) return;
    try {
      await methods.invokeMethod<bool>('cancel', {'jobId': jobId});
    } catch (_) {
      // A dead engine cannot cancel anything; the timeout handles it.
    }
  }

  static Stream<Map<String, dynamic>> events() {
    return _progress
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => Map<String, dynamic>.from(event as Map));
  }
}
