import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../core/format.dart';
import '../data/image_engine.dart';
import '../data/pdf_engine.dart';
import '../domain/models.dart';

const _imageGroup = XTypeGroup(
  label: 'Gambar',
  mimeTypes: ['image/*'],
  extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp'],
);

const _pdfGroup = XTypeGroup(
  label: 'PDF',
  mimeTypes: ['application/pdf'],
  extensions: ['pdf'],
  uniformTypeIdentifiers: ['com.adobe.pdf'],
);

const maxBatchSize = 30;

class PickerResult {
  const PickerResult({required this.files, required this.truncated});

  final List<SelectedFile> files;
  final bool truncated;
}

class FilePickerService {
  const FilePickerService();

  Future<PickerResult> pickImages() async {
    final selection = await openFiles(acceptedTypeGroups: const [_imageGroup]);
    return _build(selection, MediaKind.image);
  }

  Future<PickerResult> pickPdfs() async {
    final selection = await openFiles(acceptedTypeGroups: const [_pdfGroup]);
    return _build(selection, MediaKind.pdf);
  }

  Future<PickerResult> _build(List<XFile> selection, MediaKind kind) async {
    final files = <SelectedFile>[];
    var truncated = false;

    for (final picked in selection) {
      if (files.length >= maxBatchSize) {
        truncated = true;
        break;
      }
      final file = File(picked.path);
      if (!file.existsSync()) continue;
      final bytes = await file.length();
      final name = baseName(picked.path);

      if (kind == MediaKind.image) {
        final size = await readImageSize(picked.path);
        files.add(
          SelectedFile(
            path: picked.path,
            name: name,
            bytes: bytes,
            kind: MediaKind.image,
            width: size?.width,
            height: size?.height,
          ),
        );
      } else {
        files.add(
          SelectedFile(
            path: picked.path,
            name: name,
            bytes: bytes,
            kind: MediaKind.pdf,
          ),
        );
      }
    }

    return PickerResult(files: files, truncated: truncated);
  }

  Future<int?> readPages(SelectedFile file) => readPdfPages(file.path);
}
