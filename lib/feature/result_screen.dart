import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../domain/models.dart';
import '../ui/app_theme.dart';
import '../ui/file_actions.dart';
import '../ui/widgets.dart';
import 'setup_screen.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.report});

  final RunReport report;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final results = report.results;
    final savedPath = results
        .map((item) => item.savedToDownloads)
        .whereType<String>()
        .toList();
    final autoSave = scope.settings.autoSaveToDownloads;
    final copyFailed = autoSave && savedPath.length < results.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hasil'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Tutup',
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          AppCard(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  results.isEmpty
                      ? 'Gagal memproses'
                      : 'Hemat ${formatPercent(report.savedRatio)}',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: results.isEmpty
                        ? colors.dangerText
                        : colors.accentText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  results.isEmpty
                      ? 'Tidak ada file yang berhasil dikompres.'
                      : '${formatBytes(report.totalSourceBytes)} → ${formatBytes(report.totalOutputBytes)}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.muted,
                  ),
                ),
                if (results.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizeComparison(
                    before: report.totalSourceBytes,
                    after: report.totalOutputBytes,
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const SetupScreen()),
                    ),
                    icon: const Icon(Icons.tune),
                    label: const Text('Ubah setelan'),
                  ),
                ],
              ],
            ),
          ),
          if (copyFailed) ...[
            const SizedBox(height: 12),
            NoteBanner(
              tone: NoteTone.warn,
              icon: Icons.error_outline,
              message:
                  'Sebagian hasil gagal disalin ke Download. Filenya tetap aman di '
                  'penyimpanan aplikasi dan bisa dibagikan dari daftar di bawah.',
            ),
          ],
          if (savedPath.isNotEmpty) ...[
            const SizedBox(height: 12),
            NoteBanner(
              tone: NoteTone.success,
              icon: Icons.download_done,
              message: 'Tersimpan di ${savedPath.first}',
            ),
          ],
          if (report.failures.isNotEmpty) ...[
            const SizedBox(height: 20),
            AppCard(
              borderColor: colors.danger.withValues(alpha: 0.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${report.failures.length} file gagal',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.dangerText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final failure in report.failures)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${failure.fileName}: ${failure.message}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (results.isNotEmpty) ...[
            const SizedBox(height: 26),
            SectionHeader(
              title: 'Detail',
              trailing: Text(
                '${results.length} file',
                style: theme.textTheme.bodySmall,
              ),
            ),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  for (var index = 0; index < results.length; index++) ...[
                    if (index > 0) Divider(color: colors.line, height: 1),
                    _ResultRow(
                      result: results[index],
                      onTap: () => showFileActions(
                        context,
                        path: results[index].outputPath,
                        name: baseName(results[index].outputPath),
                        kind: results[index].kind,
                        outputs: scope.controller.outputs,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          NoteBanner(
            message: autoSave
                ? 'File asli tidak diubah. Salinan hasil memakai akhiran "-kecil" dan '
                      'disalin ke Download/Kecilin.'
                : 'File asli tidak diubah. Simpan otomatis dimatikan, jadi hasil hanya ada '
                      'di penyimpanan aplikasi — pakai "Bagikan" atau "Simpan ke Download".',
            icon: Icons.info_outline,
          ),
        ],
      ),
      bottomNavigationBar: StickyFooter(
        child: Row(
          children: [
            if (results.isNotEmpty) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => shareFiles(
                    context,
                    results.map((item) => item.outputPath).toList(),
                  ),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text(results.length > 1 ? 'Bagikan semua' : 'Bagikan'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Selesai'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result, required this.onTap});

  final JobResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final exists = File(result.outputPath).existsSync();

    final note = result.note;
    final meta =
        '${formatBytes(result.sourceBytes)} → ${formatBytes(result.outputBytes)}'
        '${result.pages != null ? ' • ${result.pages} halaman' : ''}'
        '${exists ? '' : ' • file terhapus'}';

    final row = FileRow(
      name: baseName(result.outputPath),
      kind: result.kind,
      meta: note == null || note.isEmpty ? meta : '$meta\n$note',
      onTap: exists ? onTap : null,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          SavingsBadge(ratio: result.savedRatio),
          if (!result.targetMet) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.warnSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'target belum tercapai',
                style: kNumbers.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.warnText,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (exists) return row;
    // Output file no longer on disk: keep the row for the record but dim it.
    return Opacity(
      opacity: 0.5,
      child: Row(
        children: [
          Expanded(child: row),
          Icon(Icons.info_outline, size: 16, color: colors.infoText),
        ],
      ),
    );
  }
}
