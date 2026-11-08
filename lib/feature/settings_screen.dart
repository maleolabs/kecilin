import 'package:flutter/material.dart';

import '../app.dart';
import '../core/app_version.dart';
import '../core/format.dart';
import '../ui/app_theme.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _outputBytes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshSize());
  }

  Future<void> _refreshSize() async {
    final outputs = AppScope.of(context).controller.outputs;
    final bytes = await outputs.totalOutputBytes();
    if (mounted) setState(() => _outputBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListenableBuilder(
        listenable: Listenable.merge([scope.settings, scope.history]),
        builder: (context, _) {
          final settings = scope.settings;
          final history = scope.history;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              const SectionHeader(title: 'Tampilan'),
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mode tema', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in const [
                          (label: 'Sistem', mode: ThemeMode.system),
                          (label: 'Terang', mode: ThemeMode.light),
                          (label: 'Gelap', mode: ThemeMode.dark),
                        ])
                          ChoicePill(
                            label: entry.label,
                            selected: settings.themeMode == entry.mode,
                            accent: colors.accent,
                            onTap: () => settings.setThemeMode(entry.mode),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeader(title: 'Penyimpanan'),
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: settings.autoSaveToDownloads,
                      onChanged: settings.setAutoSaveToDownloads,
                      title: Text(
                        'Simpan otomatis ke Download',
                        style: theme.textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        'Hasil disalin ke Download/Kecilin setelah selesai.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Divider(color: colors.line, height: 1),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'File hasil di perangkat',
                        style: theme.textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        formatBytes(_outputBytes),
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: TextButton(
                        onPressed: _outputBytes == 0
                            ? null
                            : _confirmClearOutputs,
                        child: Text(
                          'Hapus',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.dangerText,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeader(title: 'Riwayat'),
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${history.items.length} entri riwayat',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    'Total dihemat ${formatBytes(history.totalSavedBytes)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: TextButton(
                    onPressed: history.items.isEmpty
                        ? null
                        : _confirmClearHistory,
                    child: Text(
                      'Bersihkan',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.dangerText,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeader(title: 'Tentang'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Kecilin', style: theme.textTheme.titleLarge),
                        const SizedBox(width: 8),
                        Text(appVersion, style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A Maleo Labs Product',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Kompresor gambar dan PDF yang bekerja sepenuhnya di perangkat. '
                      'Tidak ada server, tidak ada unggahan, dan aplikasi ini tidak meminta izin internet.',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    const NoteBanner(
                      message:
                          'Kompresi selalu menurunkan sedikit kualitas. Kecilin memilih setelan '
                          'tertinggi yang masih memenuhi target ukuran kamu.',
                      icon: Icons.info_outline,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClearOutputs() async {
    final scope = AppScope.of(context);
    final confirmed = await confirmDialog(
      context,
      title: 'Hapus file hasil?',
      message:
          'Salinan file di Download/Kecilin yang dibuat aplikasi ini tidak ikut terhapus.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!confirmed) return;
    await scope.controller.outputs.clear();
    await _refreshSize();
    if (mounted) _toast(context, 'File hasil dihapus.');
  }

  Future<void> _confirmClearHistory() async {
    final history = AppScope.of(context).history;
    final confirmed = await confirmDialog(
      context,
      title: 'Bersihkan riwayat?',
      message:
          'Riwayat dan statistik penghematan akan dihapus. File hasil di folder Download tidak ikut terhapus.',
      confirmLabel: 'Bersihkan',
      destructive: true,
    );
    if (!confirmed) return;
    await history.clear();
    if (mounted) _toast(context, 'Riwayat dibersihkan.');
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
