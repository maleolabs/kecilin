import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../data/gallery.dart';
import '../data/picker.dart';
import '../domain/models.dart';
import 'app_theme.dart';
import 'widgets.dart';

/// Opens the image picker sheet.
///
/// Returns the chosen files, or `null` when the user dismissed the sheet
/// without picking anything.
Future<List<SelectedFile>?> showImagePickerSheet(BuildContext context) {
  return showModalBottomSheet<List<SelectedFile>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) => const GallerySheet(),
  );
}

class GallerySheet extends StatefulWidget {
  const GallerySheet({super.key, this.service = const GalleryService()});

  final GalleryService service;

  @override
  State<GallerySheet> createState() => _GallerySheetState();
}

class _GallerySheetState extends State<GallerySheet> {
  /// Distance from the bottom that triggers the next page request.
  static const _prefetchDistance = 400.0;

  GalleryAccess? _access;
  bool _requesting = false;
  bool _partialDismissed = false;
  bool _fallback = false;

  final List<GalleryEntry> _entries = [];
  final Set<int> _seenIds = {};
  int _offset = 0;
  bool _hasMore = true;
  bool _loadingPage = false;
  bool _pageFailed = false;

  final List<GalleryEntry> _selected = [];
  bool _pickingSystem = false;
  bool _materializing = false;
  int _materializeIndex = 0;

  String? _notice;
  NoteTone _noticeTone = NoteTone.warn;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final access = await widget.service.status();
    if (!mounted) return;
    setState(() => _access = access);
    if (access == GalleryAccess.granted || access == GalleryAccess.partial) {
      await _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_fallback || _loadingPage || _pageFailed || !_hasMore) return;
    setState(() => _loadingPage = true);

    final page = await widget.service.page(offset: _offset);
    if (!mounted) return;

    if (page == null) {
      setState(() {
        _loadingPage = false;
        _pageFailed = true;
      });
      return;
    }

    setState(() {
      _loadingPage = false;
      _offset += page.items.length;
      for (final entry in page.items) {
        final id = entry.id;
        if (id == null || !_seenIds.add(id)) continue;
        _entries.add(entry);
      }
      _hasMore = page.hasMore;
    });
  }

  void _retryPage() {
    if (_loadingPage) return;
    setState(() => _pageFailed = false);
    unawaited(_loadPage());
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (!_fallback &&
        !_pageFailed &&
        notification.metrics.extentAfter < _prefetchDistance) {
      unawaited(_loadPage());
    }
    return false;
  }

  Future<void> _requestAccess() async {
    if (_requesting) return;
    setState(() => _requesting = true);

    final access = await widget.service.request();
    if (!mounted) return;

    final usable =
        access == GalleryAccess.granted || access == GalleryAccess.partial;
    setState(() {
      _requesting = false;
      _access = access;
      _partialDismissed = false;
      if (usable) {
        // Permissions may have widened, so the cached list is stale.
        _entries.clear();
        _seenIds.clear();
        _selected.clear();
        _offset = 0;
        _hasMore = true;
        _pageFailed = false;
      }
    });

    if (usable) await _loadPage();
  }

  void _useHistory() {
    final entries = historyEntries(AppScope.of(context).history.items);
    setState(() {
      _fallback = true;
      _entries
        ..clear()
        ..addAll(entries);
      _selected.clear();
      _notice = null;
      _hasMore = false;
      _pageFailed = false;
      _loadingPage = false;
    });
  }

  void _toggle(GalleryEntry entry) {
    if (_materializing) return;
    HapticFeedback.selectionClick();

    final index = _selected.indexWhere((item) => item.key == entry.key);
    if (index >= 0) {
      setState(() => _selected.removeAt(index));
      return;
    }
    if (_selected.length >= maxBatchSize) {
      _flash('Maksimal $maxBatchSize gambar per proses.', NoteTone.warn);
      return;
    }
    setState(() => _selected.add(entry));
  }

  void _flash(String message, NoteTone tone) {
    _noticeTimer?.cancel();
    setState(() {
      _notice = message;
      _noticeTone = tone;
    });
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _notice = null);
    });
  }

  Future<void> _pickFromSystem() async {
    if (_pickingSystem || _materializing) return;
    setState(() => _pickingSystem = true);

    PickerResult? result;
    try {
      result = await const FilePickerService().pickImages();
    } catch (_) {
      result = null;
    }
    if (!mounted) return;

    if (result != null && result.files.isNotEmpty) {
      Navigator.of(context).pop(result.files);
      return;
    }

    setState(() => _pickingSystem = false);
    if (result == null) {
      _flash('Galeri sistem tidak bisa dibuka. Coba lagi.', NoteTone.warn);
    }
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty || _materializing) return;

    final total = _selected.length;
    setState(() {
      _materializing = true;
      _materializeIndex = 0;
    });

    final files = <SelectedFile>[];
    for (var index = 0; index < _selected.length; index++) {
      final entry = _selected[index];
      if (!mounted) return;
      setState(() => _materializeIndex = index);

      if (entry.isNative) {
        final file = await widget.service.materialize(entry.id!);
        if (file != null) files.add(file);
        continue;
      }

      // Fallback entries already point at a real file; nothing to copy.
      final source = File(entry.path);
      if (!source.existsSync()) continue;
      files.add(
        SelectedFile(
          path: entry.path,
          name: entry.name,
          bytes: entry.bytes,
          kind: MediaKind.image,
          width: entry.width,
          height: entry.height,
        ),
      );
    }

    if (!mounted) return;

    if (files.isEmpty) {
      setState(() => _materializing = false);
      _flash(
        total == 1
            ? 'Gambar gagal disiapkan. Coba pilih gambar lain.'
            : 'Tidak ada gambar yang bisa disiapkan. Coba pilih ulang.',
        NoteTone.warn,
      );
      return;
    }

    Navigator.of(context).pop(files);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return PopScope(
      // Materializing copies real files; leaving mid-way would strand them.
      canPop: !_materializing,
      child: SafeArea(
        top: true,
        bottom: false,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) => ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.sheet),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.glassSurface,
                  border: Border(top: BorderSide(color: colors.glassBorder)),
                ),
                child: Column(
                  children: [
                    _handle(colors),
                    _header(context),
                    Expanded(
                      child: AbsorbPointer(
                        absorbing: _materializing,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onScroll,
                          child: CustomScrollView(
                            controller: scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: _slivers(context),
                          ),
                        ),
                      ),
                    ),
                    _footer(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle(AppColors colors) {
    return ExcludeSemantics(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 8),
        decoration: BoxDecoration(
          color: colors.line,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = _fallback
        ? 'Dari riwayat Kecilin'
        : switch (_access) {
            GalleryAccess.partial => 'Hanya sebagian foto terlihat',
            GalleryAccess.denied ||
            GalleryAccess.unavailable => 'Akses galeri belum aktif',
            _ => 'Terbaru dulu • maksimal $maxBatchSize',
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pilih gambar', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Tutup',
            onPressed: _materializing
                ? null
                : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  List<Widget> _slivers(BuildContext context) {
    if (_access == null) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final blocked =
        !_fallback &&
        (_access == GalleryAccess.denied ||
            _access == GalleryAccess.unavailable);
    if (blocked) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          sliver: SliverToBoxAdapter(child: _accessCard(context)),
        ),
      ];
    }

    final slivers = <Widget>[];

    if (_fallback) {
      slivers.add(
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: NoteBanner(
              icon: Icons.history,
              message:
                  'Menampilkan gambar dari riwayat Kecilin. Pilih file lain '
                  'lewat galeri sistem kapan saja.',
            ),
          ),
        ),
      );
    } else if (_access == GalleryAccess.partial && !_partialDismissed) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(child: _partialBanner(context)),
        ),
      );
    }

    final waitingFirstPage =
        _entries.isEmpty && _hasMore && !_pageFailed && !_fallback;
    if (waitingFirstPage) {
      slivers.add(
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
      return slivers;
    }

    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate(
            _cell,
            childCount:
                1 +
                _entries.length +
                (_loadingPage ? 1 : 0) +
                (_pageFailed ? 1 : 0),
          ),
        ),
      ),
    );

    if (_entries.isEmpty && !_loadingPage && !_pageFailed) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          sliver: SliverToBoxAdapter(
            child: EmptyHint(
              icon: _fallback
                  ? Icons.history_toggle_off
                  : Icons.photo_library_outlined,
              title: _fallback ? 'Riwayat masih kosong' : 'Belum ada foto',
              message: _fallback
                  ? 'Gambar yang pernah kamu kompres muncul di sini. Pakai galeri '
                        'sistem untuk memilih file lain.'
                  : 'Foto di perangkat ini akan muncul di sini. Kamu tetap bisa '
                        'memilih lewat galeri sistem.',
            ),
          ),
        ),
      );
    } else {
      slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 16)));
    }

    return slivers;
  }

  Widget _cell(BuildContext context, int index) {
    if (index == 0) {
      return _CtaTile(busy: _pickingSystem, onTap: _pickFromSystem);
    }

    final entryIndex = index - 1;
    if (entryIndex < _entries.length) {
      final entry = _entries[entryIndex];
      final order = _selected.indexWhere((item) => item.key == entry.key);
      return _ImageCell(
        entry: entry,
        position: entryIndex + 1,
        order: order < 0 ? null : order + 1,
        onTap: () => _toggle(entry),
      );
    }

    if (_pageFailed) return _RetryTile(onTap: _retryPage);
    return const _LoadingTile();
  }

  Widget _partialBanner(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: NoteBanner(
                  icon: Icons.visibility_outlined,
                  message: 'Hanya foto yang kamu izinkan yang terlihat.',
                ),
              ),
              IconButton(
                tooltip: 'Tutup info',
                onPressed: () => setState(() => _partialDismissed = true),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _requesting ? null : _requestAccess,
              child: Text(_requesting ? 'Meminta izin…' : 'Tambah foto'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accessCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final unavailable = _access == GalleryAccess.unavailable;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
              child: Icon(
                unavailable
                    ? Icons.image_not_supported_outlined
                    : Icons.photo_library_outlined,
                size: 26,
                color: colors.accentText,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            unavailable ? 'Galeri tidak tersedia' : 'Akses galeri diperlukan',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            unavailable
                ? 'Galeri perangkat tidak bisa dibaca di sini. Kamu tetap bisa '
                      'memilih lewat galeri sistem atau memakai riwayat Kecilin.'
                : 'Kecilin butuh akses galeri untuk menampilkan foto terbaru. '
                      'Tanpa izin, kamu tetap bisa memilih lewat galeri sistem.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: unavailable
                ? (_pickingSystem ? null : _pickFromSystem)
                : (_requesting ? null : _requestAccess),
            child: !unavailable && _requesting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: colors.onAccent,
                    ),
                  )
                : Text(
                    unavailable ? 'Buka galeri sistem' : 'Izinkan akses galeri',
                  ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _useHistory,
            child: const Text('Pakai riwayat Kecilin'),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final count = _selected.length;

    return StickyFooter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Notice fades/slides in and collapses smoothly when dismissed.
          AnimatedSize(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppMotion.base,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _notice == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      key: ValueKey(_notice),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NoteBanner(
                        tone: _noticeTone,
                        icon: Icons.info_outline,
                        message: _notice!,
                      ),
                    ),
            ),
          ),
          if (_materializing)
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Menyiapkan ${math.min(_materializeIndex + 1, count)}/$count',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton(
                    onPressed: count == 0 ? null : _confirm,
                    child: Text(
                      count == 0
                          ? 'Tambahkan gambar'
                          : 'Tambahkan $count gambar',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CtaTile extends StatelessWidget {
  const _CtaTile({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      enabled: !busy,
      label: 'Buka galeri sistem untuk memilih gambar',
      onTap: busy ? null : onTap,
      child: ExcludeSemantics(
        child: Material(
          color: colors.surfaceAlt.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: InkWell(
            onTap: busy ? null : onTap,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: colors.line,
                radius: AppRadius.medium,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.accent,
                          ),
                        )
                      else
                        Icon(
                          Icons.photo_library_outlined,
                          size: 22,
                          color: colors.accent,
                        ),
                      const SizedBox(height: 6),
                      Text(
                        busy ? 'Membuka…' : 'Buka galeri',
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 12.5,
                          color: colors.accentText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageCell extends StatefulWidget {
  const _ImageCell({
    required this.entry,
    required this.position,
    required this.order,
    required this.onTap,
  });

  final GalleryEntry entry;
  final int position;

  /// 1-based selection order, or `null` when not selected.
  final int? order;
  final VoidCallback onTap;

  @override
  State<_ImageCell> createState() => _ImageCellState();
}

class _ImageCellState extends State<_ImageCell> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final selected = widget.order != null;
    final label = selected
        ? 'Gambar ${widget.position}, dipilih urutan ${widget.order}'
        : 'Gambar ${widget.position}, belum dipilih';

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: AnimatedScale(
          // Subtle press feedback; full spring overshoot not worth it here.
          scale: _pressed ? 0.96 : 1.0,
          duration: AppMotion.fast,
          curve: Curves.easeOut,
          child: Material(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (highlight) =>
                  setState(() => _pressed = highlight),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final ratio = MediaQuery.devicePixelRatioOf(context);
                      final cacheWidth = (constraints.maxWidth * ratio)
                          .round()
                          .clamp(180, 720)
                          .toInt();
                      return Image.file(
                        File(widget.entry.path),
                        fit: BoxFit.cover,
                        cacheWidth: cacheWidth,
                        frameBuilder: (context, child, frame, loaded) =>
                            frame == null && !loaded
                            ? ColoredBox(color: colors.surfaceAlt)
                            : child,
                        errorBuilder: (_, _, _) => ColoredBox(
                          color: colors.surfaceAlt,
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 20,
                              color: colors.muted,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (selected) ...[
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.medium),
                          border: Border.all(
                            color: colors.accent,
                            width: AppBorder.focus,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: colors.surface, width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 12, color: colors.onAccent),
                            const SizedBox(width: 2),
                            Text(
                              '${widget.order}',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                color: colors.onAccent,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.muted),
        ),
      ),
    );
  }
}

class _RetryTile extends StatelessWidget {
  const _RetryTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      label: 'Coba lagi memuat foto',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 20, color: colors.warnText),
                  const SizedBox(height: 4),
                  Text(
                    'Coba lagi',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 12,
                      color: colors.warnText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.7),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const dash = 5.0;
    const gap = 4.0;
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
