import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../ui/app_theme.dart';
import 'result_screen.dart';

class RunScreen extends StatefulWidget {
  const RunScreen({super.key});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started || !mounted) return;
    _started = true;
    final controller = AppScope.of(context).controller;
    final report = await controller.run();
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResultScreen(report: report)),
      ),
    );
  }

  Future<void> _confirmCancel() async {
    final controller = AppScope.of(context).controller;
    if (controller.cancelRequested) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan kompresi?'),
        content: const Text(
          'File yang sudah selesai tetap tersimpan. Sisa antrean tidak diproses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Lanjutkan'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );
    if (confirmed == true) controller.requestCancel();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).controller;
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    // PopScope must live inside the builder: `canPop` depends on the cancel
    // state, and reading it outside would leave the gate permanently closed.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final progress = controller.progress;
        final overall = progress?.overall ?? 0;
        final cancelling = controller.cancelRequested;

        return PopScope(
          // Once a cancel is requested the job is aborting; blocking back
          // would trap the user on a screen that is about to finish anyway.
          canPop: cancelling,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmCancel();
          },
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    SizedBox(
                      width: 172,
                      height: 172,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 172,
                            height: 172,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: overall),
                              duration: AppMotion.progress,
                              builder: (context, value, _) =>
                                  CircularProgressIndicator(
                                    value: value.clamp(0.0, 1.0),
                                    strokeWidth: 9,
                                    strokeCap: StrokeCap.round,
                                    backgroundColor: colors.surfaceAlt,
                                    valueColor: AlwaysStoppedAnimation(
                                      colors.accent,
                                    ),
                                  ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(overall * 100).round()}%',
                                style: kNumbers.copyWith(
                                  fontSize: 40,
                                  color: colors.ink,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Text(
                                cancelling ? 'Membatalkan' : 'Memproses',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      progress?.fileName ?? 'Menyiapkan…',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      progress?.stage ?? 'Mohon tunggu',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'File ${progress.jobIndex + 1} dari ${progress.jobCount}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                    const Spacer(flex: 3),
                    Text(
                      'Jangan tutup aplikasi sampai proses selesai.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: cancelling ? null : _confirmCancel,
                      child: Text(cancelling ? 'Membatalkan…' : 'Batalkan'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
