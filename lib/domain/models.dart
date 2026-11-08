import '../core/format.dart';

enum MediaKind { image, pdf }

/// How the image engine decides what to do.
enum ImageMode {
  /// Hard byte ceiling per file, quality is maximised inside that budget.
  target,

  /// Fixed quality preset, optional resolution cap.
  quality,

  /// Near-lossless: quality 95, no resize, metadata removed.
  maximum,
}

enum PdfMode {
  /// Keep the text layer, only re-encode embedded JPEGs.
  light,

  /// Rasterise every page to JPEG, rebuild the PDF.
  raster,
}

enum OutputFormat { jpeg, webp }

class CompressionOptions {
  const CompressionOptions({
    this.imageMode = ImageMode.target,
    this.imageQuality = 80,
    this.format = OutputFormat.jpeg,
    this.maxEdge = 0,
    this.pdfMode = PdfMode.light,
    this.pdfDpi = 150,
    this.targetBytes = 500 * kb,
  });

  final ImageMode imageMode;
  final int imageQuality;
  final OutputFormat format;
  final int maxEdge;
  final PdfMode pdfMode;
  final int pdfDpi;
  final int? targetBytes;

  bool get usesTarget => targetBytes != null;

  CompressionOptions copyWith({
    ImageMode? imageMode,
    int? imageQuality,
    OutputFormat? format,
    int? maxEdge,
    PdfMode? pdfMode,
    int? pdfDpi,
    int? targetBytes,
    bool clearTarget = false,
  }) {
    return CompressionOptions(
      imageMode: imageMode ?? this.imageMode,
      imageQuality: imageQuality ?? this.imageQuality,
      format: format ?? this.format,
      maxEdge: maxEdge ?? this.maxEdge,
      pdfMode: pdfMode ?? this.pdfMode,
      pdfDpi: pdfDpi ?? this.pdfDpi,
      targetBytes: clearTarget ? null : (targetBytes ?? this.targetBytes),
    );
  }

  Map<String, dynamic> toJson() => {
    'imageMode': imageMode.name,
    'imageQuality': imageQuality,
    'format': format.name,
    'maxEdge': maxEdge,
    'pdfMode': pdfMode.name,
    'pdfDpi': pdfDpi,
    'targetBytes': targetBytes,
  };

  factory CompressionOptions.fromJson(Map<String, dynamic> json) {
    return CompressionOptions(
      imageMode: ImageMode.values.firstWhere(
        (value) => value.name == json['imageMode'],
        orElse: () => ImageMode.target,
      ),
      imageQuality: (json['imageQuality'] as num?)?.toInt() ?? 80,
      format: OutputFormat.values.firstWhere(
        (value) => value.name == json['format'],
        orElse: () => OutputFormat.jpeg,
      ),
      maxEdge: (json['maxEdge'] as num?)?.toInt() ?? 0,
      pdfMode: PdfMode.values.firstWhere(
        (value) => value.name == json['pdfMode'],
        orElse: () => PdfMode.light,
      ),
      pdfDpi: (json['pdfDpi'] as num?)?.toInt() ?? 150,
      targetBytes: (json['targetBytes'] as num?)?.toInt(),
    );
  }
}

/// A file the user picked, with the metadata we can read cheaply.
class SelectedFile {
  const SelectedFile({
    required this.path,
    required this.name,
    required this.bytes,
    required this.kind,
    this.width,
    this.height,
    this.pages,
  });

  final String path;
  final String name;
  final int bytes;
  final MediaKind kind;
  final int? width;
  final int? height;
  final int? pages;

  String get dimensions {
    if (width != null && height != null) return '$width × $height px';
    if (pages != null) return '$pages halaman';
    return kind == MediaKind.image ? 'Gambar' : 'PDF';
  }
}

class CompressionOutcome {
  const CompressionOutcome({
    required this.outputPath,
    required this.outputBytes,
    this.pages,
    this.note,
    this.outputExtension,
  });

  final String outputPath;
  final int outputBytes;
  final int? pages;
  final String? note;

  /// Real extension of the produced file. Differs from the requested format
  /// when the original bytes were kept as-is.
  final String? outputExtension;
}

class JobResult {
  const JobResult({
    required this.sourcePath,
    required this.sourceName,
    required this.outputPath,
    required this.kind,
    required this.sourceBytes,
    required this.outputBytes,
    required this.duration,
    this.pages,
    this.note,
    this.targetBytes,
    this.savedToDownloads,
    this.outputExtension,
  });

  final String sourcePath;
  final String sourceName;
  final String outputPath;
  final MediaKind kind;
  final int sourceBytes;
  final int outputBytes;
  final Duration duration;
  final int? pages;
  final String? note;
  final int? targetBytes;
  final String? savedToDownloads;
  final String? outputExtension;

  int get savedBytes => sourceBytes - outputBytes;

  double get savedRatio => sourceBytes == 0 ? 0 : savedBytes / sourceBytes;

  bool get targetMet => targetBytes == null || outputBytes <= targetBytes!;

  Map<String, dynamic> toJson() => {
    'sourcePath': sourcePath,
    'sourceName': sourceName,
    'outputPath': outputPath,
    'kind': kind.name,
    'sourceBytes': sourceBytes,
    'outputBytes': outputBytes,
    'durationMs': duration.inMilliseconds,
    'pages': pages,
    'note': note,
    'targetBytes': targetBytes,
    'savedToDownloads': savedToDownloads,
    'outputExtension': outputExtension,
  };

  factory JobResult.fromJson(Map<String, dynamic> json) {
    return JobResult(
      sourcePath: json['sourcePath'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? 'berkas',
      outputPath: json['outputPath'] as String? ?? '',
      kind: MediaKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => MediaKind.image,
      ),
      sourceBytes: (json['sourceBytes'] as num?)?.toInt() ?? 0,
      outputBytes: (json['outputBytes'] as num?)?.toInt() ?? 0,
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
      ),
      pages: (json['pages'] as num?)?.toInt(),
      note: json['note'] as String?,
      targetBytes: (json['targetBytes'] as num?)?.toInt(),
      savedToDownloads: json['savedToDownloads'] as String?,
      outputExtension: json['outputExtension'] as String?,
    );
  }
}

class RunProgress {
  const RunProgress({
    required this.jobIndex,
    required this.jobCount,
    required this.fileName,
    required this.fraction,
    required this.stage,
  });

  final int jobIndex;
  final int jobCount;
  final String fileName;
  final double fraction;
  final String stage;

  double get overall => jobCount == 0
      ? 0
      : ((jobIndex + fraction.clamp(0.0, 1.0)) / jobCount).clamp(0.0, 1.0);
}

class RunReport {
  const RunReport({required this.results, required this.failures});

  final List<JobResult> results;
  final List<RunFailure> failures;

  int get totalSourceBytes =>
      results.fold(0, (sum, item) => sum + item.sourceBytes);

  int get totalOutputBytes =>
      results.fold(0, (sum, item) => sum + item.outputBytes);

  int get totalSavedBytes =>
      results.fold(0, (sum, item) => sum + item.savedBytes);

  double get savedRatio =>
      totalSourceBytes == 0 ? 0 : totalSavedBytes / totalSourceBytes;
}

class RunFailure {
  const RunFailure({required this.fileName, required this.message});

  final String fileName;
  final String message;
}
