import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/format.dart';
import '../data/history_store.dart';
import '../data/picker.dart';
import '../domain/models.dart';
import '../state/compression_controller.dart';
import '../ui/app_theme.dart';
import '../ui/file_actions.dart';
import '../ui/gallery_sheet.dart';
import '../ui/widgets.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

enum _HistoryFilter { semua, gambar, pdf }

/// Wordmark sebagai plain text (tanpa gambar) — identik dengan desain Stitch.
/// Warna mengikuti tema agar terbaca di light dan dark.
class _BrandText extends StatelessWidget {
  const _BrandText({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Kecilin, A Maleo Labs Product',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'kecilin',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'A Maleo Labs Product',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.muted),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _picker = FilePickerService();

  bool _picking = false;
  _HistoryFilter _filter = _HistoryFilter.semua;

  Future<void> _pick(MediaKind kind) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      if (kind == MediaKind.image) {
        final files = await showImagePickerSheet(context);
        if (!mounted) return;
        if (files == null || files.isEmpty) return;

        AppScope.of(context).controller.addFiles(files);
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SetupScreen()));
        return;
      }

      final result = await _picker.pickPdfs();
      if (!mounted) return;
      if (result.files.isEmpty) return;

      final scope = AppScope.of(context);
      scope.controller.addFiles(result.files);

      if (result.truncated) {
        _toast('Maksimal $maxBatchSize file per proses.');
      }
      unawaited(_enrichPdf(scope.controller));

      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SetupScreen()));
    } catch (error) {
      if (mounted) _toast(CompressionController.describeError(error));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _enrichPdf(CompressionController controller) async {
    for (final file in controller.selection.toList()) {
      if (file.pages != null) continue;
      final pages = await _picker.readPages(file);
      if (pages != null) controller.enrichPdf(file, pages);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: GlassBackdrop(
          child: ListenableBuilder(
            listenable: Listenable.merge([scope.history, scope.controller]),
            builder: (context, _) {
              final history = scope.history;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _header(theme, colors)),
                  if (history.items.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _bentoStats(theme, colors, history),
                    ),
                  SliverToBoxAdapter(child: _quickStart(theme, colors)),
                  if (history.items.isNotEmpty) ...[
                    SliverToBoxAdapter(child: _activityHeader(colors, history)),
                    SliverToBoxAdapter(child: _filterPills(colors)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      sliver: SliverList.separated(
                        itemCount: _filtered(history).length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _historyRow(
                          colors,
                          history,
                          _filtered(history)[index],
                        ),
                      ),
                    ),
                  ] else
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
                      sliver: SliverToBoxAdapter(
                        child: EmptyHint(
                          icon: Icons.inbox_outlined,
                          title: 'Belum ada hasil',
                          message:
                              'File yang sudah dikompres muncul di sini, lengkap dengan total penghematan.',
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(child: _footer(theme, colors)),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 28)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<JobResult> _filtered(HistoryStore history) {
    switch (_filter) {
      case _HistoryFilter.semua:
        return history.items;
      case _HistoryFilter.gambar:
        return history.items.where((i) => i.kind == MediaKind.image).toList();
      case _HistoryFilter.pdf:
        return history.items.where((i) => i.kind == MediaKind.pdf).toList();
    }
  }

  Widget _header(ThemeData theme, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x5,
        AppSpace.x5,
        AppSpace.x2,
        0,
      ),
      child: Row(
        children: [
          _BrandText(colors: colors),
          const Spacer(),
          IconButton(
            tooltip: 'Pengaturan',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
    );
  }

  /// Label kualitas turunan dari rasio penghematan (presentasi saja).
  String _efficiencyLabel(double ratio) {
    if (ratio >= 0.5) return 'Efisien';
    if (ratio >= 0.2) return 'Hemat';
    return 'Standar';
  }

  Widget _bentoStats(ThemeData theme, AppColors colors, HistoryStore history) {
    final ratio = history.savingsRatio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'STATISTIK RUANG PENYIMPANAN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'Aktif On-Device',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.accentText,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Total Penghematan', style: theme.textTheme.bodySmall),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        _efficiencyLabel(ratio),
                        style: kNumbers.copyWith(
                          fontSize: 10,
                          color: colors.accentText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatBytes(history.totalSavedBytes),
                      style: kStatValue.copyWith(
                        fontSize: 32,
                        color: colors.accentText,
                      ),
                    ),
                    const Spacer(),
                    Text('Dihemat', style: theme.textTheme.bodyMedium),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: SizedBox(
                    height: 6,
                    child: LinearProgressIndicator(
                      value: ratio.clamp(0.0, 1.0),
                      backgroundColor: colors.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(colors.accent),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _BentoTile(
                  icon: Icons.inventory_2_outlined,
                  iconBackground: colors.surfaceAlt,
                  iconColor: colors.ink,
                  value: '${history.items.length} Berkas',
                  valueColor: colors.ink,
                  caption: 'Dioptimalkan',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BentoTile(
                  icon: Icons.trending_down,
                  iconBackground: colors.accentSoft,
                  iconColor: colors.accentText,
                  value: formatPercent(ratio),
                  valueColor: colors.accentText,
                  caption: 'Rata-rata Lebih Ringan',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickStart(ThemeData theme, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: AbsorbPointer(
        absorbing: _picking,
        child: Opacity(
          opacity: _picking ? 0.6 : 1,
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mulai Kompresi Cepat',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.bolt_rounded,
                      size: 18,
                      color: colors.accentText,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Pilih file dari galeri untuk diperkecil tanpa mengurangi ketajaman',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _QuickSelector(
                        icon: Icons.photo_library_outlined,
                        iconBackground: colors.accentSoft,
                        iconColor: colors.accentText,
                        title: 'Foto & Gambar',
                        subtitle: 'JPG, PNG, WebP, dll.',
                        onTap: () => _pick(MediaKind.image),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickSelector(
                        icon: Icons.picture_as_pdf_outlined,
                        iconBackground: colors.surfaceAlt,
                        iconColor: colors.ink,
                        title: 'Dokumen PDF',
                        subtitle: 'Batch hingga $maxBatchSize file',
                        onTap: () => _pick(MediaKind.pdf),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _activityHeader(AppColors colors, HistoryStore history) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'AKTIVITAS TERKINI',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(letterSpacing: 1.1),
            ),
          ),
          TextButton(
            onPressed: () => _confirmClear(history),
            style: TextButton.styleFrom(
              foregroundColor: colors.accentText,
              textStyle: Theme.of(context).textTheme.labelMedium,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Bersihkan'),
          ),
        ],
      ),
    );
  }

  Widget _filterPills(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          for (final entry in const [
            (filter: _HistoryFilter.semua, label: 'Semua'),
            (filter: _HistoryFilter.gambar, label: 'Gambar'),
            (filter: _HistoryFilter.pdf, label: 'PDF'),
          ]) ...[
            _FilterPill(
              label: entry.label,
              selected: _filter == entry.filter,
              colors: colors,
              onTap: () => setState(() => _filter = entry.filter),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _historyRow(AppColors colors, HistoryStore history, JobResult item) {
    final finishedAt = item.finishedAt;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      onTap: () => showFileActions(
        context,
        path: item.outputPath,
        name: baseName(item.outputPath),
        kind: item.kind,
        outputs: AppScope.of(context).controller.outputs,
        onRemove: () => history.removeAt(history.items.indexOf(item)),
      ),
      child: Column(
        children: [
          FileRow(
            name: baseName(item.outputPath),
            kind: item.kind,
            meta:
                '${formatBytes(item.sourceBytes)} → ${formatBytes(item.outputBytes)}'
                '${item.pages != null ? ' • ${item.pages} halaman' : ''}',
            trailing: SavingsBadge(ratio: item.savedRatio, compact: true),
            nameSuffix: finishedAt == null
                ? null
                : '• ${formatRelativeTime(finishedAt)}',
          ),
          const SizedBox(height: 8),
          SizeBar(before: item.sourceBytes, after: item.outputBytes, height: 6),
        ],
      ),
    );
  }

  Widget _footer(ThemeData theme, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GlassCard(
        radius: AppRadius.medium,
        padding: const EdgeInsets.all(12),
        color: colors.surface.withValues(alpha: 0.35),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 16,
              color: colors.accentText,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pemrosesan 100% On-Device — Data pribadi & dokumen Anda tidak pernah meninggalkan perangkat.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(HistoryStore history) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Bersihkan riwayat?',
      message:
          'Riwayat dan statistik penghematan akan dihapus. File hasil di folder Download tidak ikut terhapus.',
      confirmLabel: 'Bersihkan',
      destructive: true,
    );
    if (confirmed) await history.clear();
  }
}

class _BentoTile extends StatelessWidget {
  const _BentoTile({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.value,
    required this.valueColor,
    required this.caption,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String value;
  final Color valueColor;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: kNumbers.copyWith(fontSize: 20, color: valueColor),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.muted,
              letterSpacing: 0,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _QuickSelector extends StatelessWidget {
  const _QuickSelector({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(color: colors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.muted,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // Padding transparan menjaga target sentuh tetap lega di sekitar pil.
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: AnimatedContainer(
            duration: AppMotion.selection,
            curve: AppMotion.standard,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.secondary
                  : colors.glassSurface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? Colors.transparent : colors.line,
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? Theme.of(context).colorScheme.onSecondary
                    : colors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
