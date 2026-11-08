import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../data/output_store.dart';
import '../domain/models.dart';
import 'app_theme.dart';
import 'widgets.dart';

Future<void> shareFiles(
  BuildContext context,
  List<String> paths, {
  String? text,
}) async {
  final files = <XFile>[];
  for (final path in paths) {
    if (File(path).existsSync()) files.add(XFile(path));
  }
  if (files.isEmpty) {
    _toast(context, 'File hasil tidak ditemukan.');
    return;
  }
  await SharePlus.instance.share(ShareParams(files: files, text: text));
}

Future<void> showFileActions(
  BuildContext context, {
  required String path,
  required String name,
  required MediaKind kind,
  required OutputTarget outputs,
  VoidCallback? onRemove,
}) {
  final colors = AppColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    KindGlyph(kind: kind, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Buka'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final result = await OpenFilex.open(
                    path,
                    type: kind == MediaKind.pdf ? 'application/pdf' : null,
                  );
                  if (result.type != ResultType.done && context.mounted) {
                    _toast(
                      context,
                      'Tidak ada aplikasi untuk membuka file ini.',
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Bagikan'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  shareFiles(context, [path], text: name);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Simpan ke Download'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final saved = await outputs.saveToDownloads(
                    File(path),
                    displayName: baseName(path),
                    mime: kind == MediaKind.pdf
                        ? 'application/pdf'
                        : 'application/octet-stream',
                  );
                  if (!context.mounted) return;
                  _toast(
                    context,
                    saved == null
                        ? 'Gagal menyimpan ke Download.'
                        : 'Tersimpan di $saved',
                  );
                },
              ),
              if (onRemove != null)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colors.danger),
                  title: Text(
                    'Hapus dari riwayat',
                    style: TextStyle(color: colors.danger),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onRemove();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
