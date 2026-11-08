import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../domain/models.dart';
import '../state/compression_controller.dart';
import '../ui/app_theme.dart';
import '../ui/widgets.dart';
import 'run_screen.dart';

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  static const _targetPresets = <int>[
    100 * kb,
    200 * kb,
    500 * kb,
    1 * mb,
    2 * mb,
  ];

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final kind = controller.selectionKind ?? MediaKind.image;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Atur kompresi'),
            leading: const CloseButton(),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              _Summary(controller: controller, kind: kind),
              const SizedBox(height: 26),
              SectionHeader(
                title: kind == MediaKind.image
                    ? 'Cara kompres gambar'
                    : 'Mode kompres PDF',
              ),
              ..._modeOptions(context, controller, kind),
              const SizedBox(height: 24),
              ..._detailOptions(context, controller, kind),
            ],
          ),
          bottomNavigationBar: StickyFooter(
            child: FilledButton.icon(
              onPressed: controller.selection.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RunScreen()),
                    ),
              icon: const Icon(Icons.bolt_rounded, size: 20),
              label: Text('Kompres ${controller.selection.length} file'),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _modeOptions(
    BuildContext context,
    CompressionController controller,
    MediaKind kind,
  ) {
    final options = controller.options;
    if (kind == MediaKind.image) {
      return [
        OptionCard(
          title: 'Target ukuran',
          subtitle:
              'Tentukan batas maksimum per file, kualitas dicari otomatis.',
          icon: Icons.straighten,
          selected: options.imageMode == ImageMode.target,
          onTap: () => controller.updateOptions(
            options.copyWith(imageMode: ImageMode.target),
          ),
        ),
        const SizedBox(height: 10),
        OptionCard(
          title: 'Kualitas tetap',
          subtitle:
              'Pilih level kompresi sendiri, hasilnya lebih bisa diprediksi.',
          icon: Icons.tune,
          selected: options.imageMode == ImageMode.quality,
          onTap: () => controller.updateOptions(
            options.copyWith(imageMode: ImageMode.quality),
          ),
        ),
        const SizedBox(height: 10),
        OptionCard(
          title: 'Hampir tanpa kompromi',
          subtitle:
              'Resolusi tetap, encode ulang kualitas 96, metadata dibuang.',
          icon: Icons.hd_outlined,
          selected: options.imageMode == ImageMode.maximum,
          onTap: () => controller.updateOptions(
            options.copyWith(imageMode: ImageMode.maximum),
          ),
        ),
      ];
    }

    return [
      OptionCard(
        title: 'Ringan',
        subtitle:
            'Teks tetap bisa dipilih dan dicari. Kompresi lebih terbatas.',
        icon: Icons.text_fields,
        selected: options.pdfMode == PdfMode.light,
        onTap: () =>
            controller.updateOptions(options.copyWith(pdfMode: PdfMode.light)),
      ),
      const SizedBox(height: 10),
      OptionCard(
        title: 'Agresif',
        subtitle:
            'Halaman dijadikan gambar. Paling kecil, teks tidak bisa dipilih.',
        icon: Icons.compress,
        selected: options.pdfMode == PdfMode.raster,
        onTap: () =>
            controller.updateOptions(options.copyWith(pdfMode: PdfMode.raster)),
      ),
    ];
  }

  List<Widget> _detailOptions(
    BuildContext context,
    CompressionController controller,
    MediaKind kind,
  ) {
    final options = controller.options;
    final children = <Widget>[];

    if (kind == MediaKind.image) {
      if (options.imageMode == ImageMode.target) {
        children.addAll(_targetBlock(context, controller, allowAuto: false));
      } else if (options.imageMode == ImageMode.quality) {
        children
          ..add(_label(context, 'Level kualitas'))
          ..add(
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in const [
                  (label: 'Tinggi', value: 90),
                  (label: 'Seimbang', value: 78),
                  (label: 'Kecil', value: 62),
                  (label: 'Paling kecil', value: 50),
                ])
                  ChoicePill(
                    label: preset.label,
                    selected: options.imageQuality == preset.value,
                    accent: AppColors.of(context).accent,
                    onTap: () => controller.updateOptions(
                      options.copyWith(imageQuality: preset.value),
                    ),
                  ),
              ],
            ),
          )
          ..add(const SizedBox(height: 22));
      } else {
        children.add(
          const NoteBanner(
            message:
                'Gambar tidak diperkecil dan kualitas tetap tinggi, tapi file di-encode ulang '
                '(JPEG kualitas 96). Transparansi PNG diratakan ke putih, jadi untuk logo '
                'berlatar transparan pilih format WebP.',
            icon: Icons.info_outline,
          ),
        );
        children.add(const SizedBox(height: 22));
      }

      if (options.imageMode != ImageMode.maximum) {
        children
          ..add(_label(context, 'Resolusi maksimum'))
          ..add(
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in const [
                  (label: 'Asli', value: 0),
                  (label: '3000 px', value: 3000),
                  (label: '2000 px', value: 2000),
                  (label: '1600 px', value: 1600),
                  (label: '1280 px', value: 1280),
                ])
                  ChoicePill(
                    label: preset.label,
                    selected: options.maxEdge == preset.value,
                    accent: AppColors.of(context).accent,
                    onTap: () => controller.updateOptions(
                      options.copyWith(maxEdge: preset.value),
                    ),
                  ),
              ],
            ),
          )
          ..add(const SizedBox(height: 22));
      }

      children
        ..add(_label(context, 'Format hasil'))
        ..add(
          Wrap(
            spacing: 8,
            children: [
              ChoicePill(
                label: 'JPG',
                selected: options.format == OutputFormat.jpeg,
                accent: AppColors.of(context).accent,
                onTap: () => controller.updateOptions(
                  options.copyWith(format: OutputFormat.jpeg),
                ),
              ),
              ChoicePill(
                label: 'WebP',
                selected: options.format == OutputFormat.webp,
                accent: AppColors.of(context).accent,
                onTap: () => controller.updateOptions(
                  options.copyWith(format: OutputFormat.webp),
                ),
              ),
            ],
          ),
        )
        ..add(const SizedBox(height: 10))
        ..add(
          NoteBanner(
            message: options.format == OutputFormat.webp
                ? 'WebP sekitar 25% lebih kecil dari JPG pada kualitas setara, tapi belum semua aplikasi menerimanya.'
                : 'JPG paling aman untuk unggahan portal, lamaran, dan dokumen resmi.',
          ),
        );
    } else {
      children.addAll(_targetBlock(context, controller, allowAuto: true));

      if (options.pdfMode == PdfMode.raster) {
        children
          ..add(_label(context, 'Ketajaman halaman'))
          ..add(
            Wrap(
              spacing: 8,
              children: [
                for (final preset in const [
                  (label: 'Hemat 110', value: 110),
                  (label: 'Seimbang 150', value: 150),
                  (label: 'Tajam 200', value: 200),
                ])
                  ChoicePill(
                    label: preset.label,
                    selected: options.pdfDpi == preset.value,
                    accent: AppColors.of(context).accent,
                    onTap: () => controller.updateOptions(
                      options.copyWith(pdfDpi: preset.value),
                    ),
                  ),
              ],
            ),
          )
          ..add(const SizedBox(height: 12))
          ..add(
            const NoteBanner(
              tone: NoteTone.warn,
              icon: Icons.warning_amber_outlined,
              message:
                  'Mode Agresif mengubah halaman jadi gambar: teks tidak bisa dipilih, dicari, '
                  'atau di-copy, dan link, form field, bookmark, serta tanda tangan digital ikut hilang. '
                  'Fotokopi KTP/KK dan dokumen scan tetap terlihat jelas.',
            ),
          );
      } else {
        children.add(
          const NoteBanner(
            message:
                'Mode Ringan hanya bisa memperkecil gambar di dalam PDF. Kalau target tidak tercapai, '
                'gunakan mode Agresif.',
          ),
        );
      }
    }

    return children;
  }

  List<Widget> _targetBlock(
    BuildContext context,
    CompressionController controller, {
    required bool allowAuto,
  }) {
    final options = controller.options;
    final current = options.targetBytes;
    final custom = current != null && !_targetPresets.contains(current);
    final colors = AppColors.of(context);

    return [
      _label(context, 'Target ukuran per file'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (allowAuto)
            ChoicePill(
              label: 'Otomatis',
              selected: current == null,
              accent: colors.accent,
              onTap: () =>
                  controller.updateOptions(options.copyWith(clearTarget: true)),
            ),
          for (final preset in _targetPresets)
            ChoicePill(
              label: formatBytes(preset),
              selected: current == preset,
              accent: colors.accent,
              onTap: () => controller.updateOptions(
                options.copyWith(targetBytes: preset),
              ),
            ),
          ChoicePill(
            label: custom ? formatBytes(current) : 'Custom…',
            selected: custom,
            accent: colors.accent,
            onTap: () async {
              final value = await showDialog<int>(
                context: context,
                builder: (_) => _SizeDialog(initial: current),
              );
              if (value != null) {
                // Re-read the options: they may have changed while the dialog
                // was open, and the captured copy would overwrite that.
                controller.updateOptions(
                  controller.options.copyWith(targetBytes: value),
                );
              }
            },
          ),
        ],
      ),
      const SizedBox(height: 12),
      NoteBanner(
        message: allowAuto
            ? 'Tanpa target, Kecilin memakai setelan kualitas bawaan untuk tiap mode.'
            : 'Kualitas dicari otomatis setinggi mungkin di bawah target. Kalau target mustahil, hasil terkecil tetap disimpan.',
      ),
      const SizedBox(height: 22),
    ];
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller, required this.kind});

  final CompressionController controller;
  final MediaKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final selection = controller.selection;
    final isImage = kind == MediaKind.image;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KindGlyph(kind: kind, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${selection.length} ${isImage ? 'gambar' : 'PDF'}',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total ${formatBytes(controller.totalBytes)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ganti file',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.swap_horiz),
              ),
            ],
          ),
          if (isImage) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: math.min(selection.length, 10),
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final file = selection[index];
                  return Semantics(
                    image: true,
                    label: 'Pratinjau ${file.name}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      child: Image.file(
                        File(file.path),
                        width: 62,
                        height: 62,
                        fit: BoxFit.cover,
                        cacheWidth: 160,
                        errorBuilder: (_, _, _) => Container(
                          width: 62,
                          height: 62,
                          color: colors.surfaceAlt,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 18,
                            color: colors.muted,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (selection.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+${selection.length - 10} gambar lainnya',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ] else ...[
            const SizedBox(height: 10),
            for (final file in selection.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatBytes(file.bytes),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (selection.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '+${selection.length - 3} file lainnya',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SizeDialog extends StatefulWidget {
  const _SizeDialog({this.initial});

  final int? initial;

  @override
  State<_SizeDialog> createState() => _SizeDialogState();
}

class _SizeDialogState extends State<_SizeDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial == null
          ? ''
          : formatBytes(widget.initial!).replaceAll(' ', ''),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final bytes = parseSize(_controller.text);
    if (bytes == null) {
      setState(
        () => _error = 'Tulis dengan satuan, contoh: 250 KB atau 1.5 MB',
      );
      return;
    }
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Target ukuran'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Target ukuran per file',
              hintText: '250 KB',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Berlaku per file. Contoh: 200 KB, 750 KB, 1.5 MB.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Pakai')),
      ],
    );
  }
}
