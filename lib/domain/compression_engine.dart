import 'models.dart';

typedef ProgressCallback = void Function(double fraction, String stage);
typedef CancelCheck = bool Function();

class CompressionCancelled implements Exception {
  const CompressionCancelled();
}

class CompressionFailure implements Exception {
  const CompressionFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

abstract class CompressionEngine {
  MediaKind get kind;

  Future<CompressionOutcome> compress({
    required SelectedFile file,
    required CompressionOptions options,
    required String outputPath,
    required ProgressCallback onProgress,
    required CancelCheck isCancelled,
  });
}
