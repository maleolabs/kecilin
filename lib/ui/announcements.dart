import 'package:flutter/material.dart';

import '../core/app_version.dart';
import '../core/changelog.dart';
import 'app_theme.dart';
import 'widgets.dart';

/// Gerbang sambutan dan "Yang baru": dua modal auto-open yang tampil di atas
/// beranda saat aplikasi dibuka (instal pertama / setelah update manual).
/// Semuanya lokal — tidak ada jaringan yang disentuh.

/// Modal instal pertama: pengenalan singkat, fitur, dan jaminan privasi
/// on-device. Harus ditutup lewat tombol agar klaim privasi terbaca.
Future<void> showWelcomeModal(BuildContext context) {
  return _showGlassDialog(
    context,
    barrierDismissible: false,
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'kecilin',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.of(context).ink,
            ),
          ),
          Text(
            'A Maleo Labs Product',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.of(context).muted,
            ),
          ),
          const SizedBox(height: AppSpace.x3),
          Text(
            'Kompresor gambar dan PDF yang bekerja sepenuhnya di perangkat '
            'Anda.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          const SizedBox(height: AppSpace.x4),
          const _FeatureRow(
            icon: Icons.photo_library_outlined,
            title: 'Kompres gambar',
            detail: 'JPG, PNG, WebP, HEIC — satu file atau sekaligus.',
          ),
          const _FeatureRow(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF tanpa ribet',
            detail: 'Batch hingga 30 dokumen dalam satu proses.',
          ),
          const _FeatureRow(
            icon: Icons.tune,
            title: 'Atur sesuai kebutuhan',
            detail:
                'Tentukan target ukuran per file, kualitas dicari otomatis.',
          ),
          const SizedBox(height: AppSpace.x4),
          _PrivacyCard(
            title: 'Privasi & Keamanan',
            message:
                'Pemrosesan 100% on-device. File Anda tidak pernah '
                'meninggalkan perangkat — tanpa server, tanpa unggahan, dan '
                'aplikasi ini tidak meminta izin internet.',
          ),
          const SizedBox(height: AppSpace.x4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Mengerti, Mulai'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Modal setelah update: ringkasan changelog antara versi terakhir yang
/// dibuka pengguna dan versi saat ini.
Future<void> showChangelogModal(BuildContext context) {
  final theme = Theme.of(context);
  final colors = AppColors.of(context);
  return _showGlassDialog(
    context,
    barrierDismissible: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Yang baru',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.ink,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.x2,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                'v$appVersion',
                style: kNumbers.copyWith(
                  fontSize: 11,
                  color: colors.accentText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.x2),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry
                    in changelog[appVersion] ?? const <ChangelogEntry>[]) ...[
                  const SizedBox(height: AppSpace.x2),
                  _ChangelogRow(entry: entry),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.x4),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Lanjut'),
          ),
        ),
      ],
    ),
  );
}

Future<void> _showGlassDialog(
  BuildContext context, {
  required Widget child,
  required bool barrierDismissible,
}) {
  final colors = AppColors.of(context);
  return showGeneralDialog(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Tutup',
    barrierColor: colors.scrim,
    transitionDuration: AppMotion.progress,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.x6),
          child: GlassCard(
            radius: AppRadius.sheet,
            padding: const EdgeInsets.all(AppSpace.x5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: child,
            ),
          ),
        ),
      );
    },
    // Fade + scale halus, kurva dan durasi mengikuti design system.
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.standard,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(icon, size: 18, color: colors.accentText),
          ),
          const SizedBox(width: AppSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 1),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.muted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return GlassCard(
      radius: AppRadius.medium,
      padding: const EdgeInsets.all(AppSpace.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: colors.accentText,
          ),
          const SizedBox(width: AppSpace.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.accentText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangelogRow extends StatelessWidget {
  const _ChangelogRow({required this.entry});

  final ChangelogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.title, style: theme.textTheme.labelLarge),
              const SizedBox(height: 1),
              Text(
                entry.detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.muted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
