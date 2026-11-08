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

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    // Logo resmi: wordmark navy + tagline Maleo Labs. Warna navy butuh permukaan
    // terang agar tetap terbaca di tema gelap, jadi logo selalu ditaruh di chip
    // putih — tampilan identik di kedua tema.
    return Semantics(
      label: 'Kecilin, A Maleo Labs Product',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.large),
          border: Border.all(color: colors.line),
        ),
        child: Image.asset(
          'assets/logo/kecilin-header.png',
          height: 40,
          fit: BoxFit.contain,
        ),
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
        child: ListenableBuilder(
          listenable: Listenable.merge([scope.history, scope.controller]),
          builder: (context, _) {
            final history = scope.history;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(theme, colors)),
                SliverToBoxAdapter(child: _actions(theme, colors)),
                if (history.items.isNotEmpty)
                  SliverToBoxAdapter(child: _stats(theme, colors, history)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                    child: SectionHeader(
                      title: 'Terakhir dikompres',
                      trailing: history.items.isEmpty
                          ? null
                          : TextButton(
                              onPressed: () => _confirmClear(history),
                              child: const Text('Bersihkan'),
                            ),
                    ),
                  ),
                ),
                if (history.items.isEmpty)
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                    sliver: SliverToBoxAdapter(
                      child: EmptyHint(
                        icon: Icons.inbox_outlined,
                        title: 'Belum ada hasil',
                        message:
                            'File yang sudah dikompres muncul di sini, lengkap dengan total penghematan.',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    sliver: SliverList.separated(
                      itemCount: history.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = history.items[index];
                        return AppCard(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                          onTap: () => showFileActions(
                            context,
                            path: item.outputPath,
                            name: baseName(item.outputPath),
                            kind: item.kind,
                            outputs: scope.controller.outputs,
                            onRemove: () => history.removeAt(index),
                          ),
                          child: Column(
                            children: [
                              FileRow(
                                name: baseName(item.outputPath),
                                kind: item.kind,
                                meta:
                                    '${formatBytes(item.sourceBytes)} → ${formatBytes(item.outputBytes)}'
                                    '${item.pages != null ? ' • ${item.pages} halaman' : ''}',
                                trailing: SavingsBadge(
                                  ratio: item.savedRatio,
                                  compact: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizeBar(
                                before: item.sourceBytes,
                                after: item.outputBytes,
                                height: 6,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                SliverToBoxAdapter(child: _footer(theme, colors)),
                const SliverPadding(padding: EdgeInsets.only(bottom: 28)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x5,
        AppSpace.x5,
        AppSpace.x2,
        0,
      ),
      child: Column(
        children: [
          // Logo dan tombol pengaturan satu baris, keduanya center secara vertikal.
          Row(
            children: [
              _BrandLogo(colors: colors),
              const Spacer(),
              IconButton(
                tooltip: 'Pengaturan',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.x3),
          Text(
            'Less Size. More Value.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 2),
          Text(
            'Compress images and PDFs. Keep what matters.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpace.x2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 13, color: colors.muted),
              const SizedBox(width: 5),
              Text(
                'Kompres lokal, tanpa upload',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actions(ThemeData theme, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x5,
        AppSpace.x6,
        AppSpace.x5,
        0,
      ),
      child: AbsorbPointer(
        absorbing: _picking,
        child: Opacity(
          opacity: _picking ? 0.6 : 1,
          child: Row(
            children: [
              Expanded(
                child: _ActionTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Gambar',
                  subtitle: 'Pilih gambar',
                  onTap: () => _pick(MediaKind.image),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'PDF',
                  subtitle: 'Pilih file PDF',
                  onTap: () => _pick(MediaKind.pdf),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stats(ThemeData theme, AppColors colors, HistoryStore history) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TOTAL DIHEMAT', style: theme.textTheme.labelSmall),
                const SizedBox(height: 5),
                Text(
                  formatBytes(history.totalSavedBytes),
                  style: kNumbers.copyWith(fontSize: 24, color: colors.accent),
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${history.items.length} file',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 5),
                Text(
                  '${(history.savingsRatio * 100).round()}% rata-rata',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(ThemeData theme, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 15, color: colors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Semua file diproses di perangkat ini. Kecilin tidak punya izin internet '
              'dan tidak mengunggah apa pun.',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(HistoryStore history) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bersihkan riwayat?'),
        content: const Text(
          'Riwayat dan statistik penghematan akan dihapus. File hasil di folder Download tidak ikut terhapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bersihkan'),
          ),
        ],
      ),
    );
    if (confirmed == true) await history.clear();
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Container(
          height: 150,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(color: colors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: Icon(icon, size: 22, color: colors.accent),
              ),
              const Spacer(),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
