import 'package:flutter/material.dart';

import '../core/format.dart';
import '../domain/models.dart';
import 'app_theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.x4),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: borderColor ?? colors.line),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: content,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.1),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class SavingsBadge extends StatelessWidget {
  const SavingsBadge({super.key, required this.ratio, this.compact = false});

  final double ratio;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final grown = ratio < -0.001;
    final flat = ratio >= -0.001 && ratio <= 0.001;
    final background = grown || flat ? colors.surfaceAlt : colors.accentSoft;
    final foreground = grown
        ? colors.warn
        : flat
        ? colors.muted
        : colors.accent;
    final label = grown
        ? '+${formatPercent(ratio.abs())}'
        : flat
        ? 'tanpa perubahan'
        : '−${formatPercent(ratio)}';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: kNumbers.copyWith(
          fontSize: compact ? 11 : 12.5,
          color: foreground,
        ),
      ),
    );
  }
}

class SizeBar extends StatelessWidget {
  const SizeBar({
    super.key,
    required this.before,
    required this.after,
    this.height = 10,
  });

  final int before;
  final int after;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final ratio = before <= 0 ? 0.0 : (after / before).clamp(0.0, 1.0);
    final afterFlex = (ratio * 1000).round().clamp(1, 1000);
    final beforeFlex = 1000 - afterFlex;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              flex: afterFlex,
              child: ColoredBox(color: colors.accent),
            ),
            if (beforeFlex > 0)
              Expanded(
                flex: beforeFlex,
                child: ColoredBox(color: colors.surfaceAlt),
              ),
          ],
        ),
      ),
    );
  }
}

class SizeComparison extends StatelessWidget {
  const SizeComparison({
    super.key,
    required this.before,
    required this.after,
    this.alwaysShowLabels = true,
  });

  final int before;
  final int after;
  final bool alwaysShowLabels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final ratio = before <= 0 ? 0.0 : (after / before).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizeBar(before: before, after: after),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              formatBytes(after),
              style: kNumbers.copyWith(fontSize: 13, color: colors.ink),
            ),
            const SizedBox(width: 6),
            Text(
              'dari ${formatBytes(before)}',
              style: theme.textTheme.bodySmall,
            ),
            const Spacer(),
            if (ratio < 1)
              Text(
                '${(100 - ratio * 100).round()}% lebih kecil',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.accent,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class KindGlyph extends StatelessWidget {
  const KindGlyph({super.key, required this.kind, this.size = 44});

  final MediaKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isPdf = kind == MediaKind.pdf;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isPdf ? colors.surfaceAlt : colors.accentSoft,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(
        isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
        size: size * 0.48,
        color: isPdf ? colors.muted : colors.accent,
      ),
    );
  }
}

class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.name,
    required this.meta,
    required this.kind,
    this.trailing,
    this.onTap,
  });

  final String name;
  final String meta;
  final MediaKind kind;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          KindGlyph(kind: kind),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(meta, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: row,
    );
  }
}

class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.x3),
            decoration: BoxDecoration(
              color: selected ? colors.accentSoft : colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.medium),
              border: Border.all(
                color: selected ? colors.accent : colors.line,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? colors.accent : colors.muted,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: selected ? colors.accent : colors.ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(subtitle!, style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: AppMotion.selection,
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? colors.accent : Colors.transparent,
                    border: Border.all(
                      color: selected ? colors.accent : colors.line,
                      width: 1.6,
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 13, color: colors.onAccent)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChipOption<T> {
  const ChipOption(this.value, this.label);

  final T value;
  final String label;
}

class OptionChips<T> extends StatelessWidget {
  const OptionChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<ChipOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoicePill(
            label: option.label,
            selected: option.value == selected,
            accent: colors.accent,
            onTap: () => onSelected(option.value),
          ),
      ],
    );
  }
}

class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: AppMotion.selection,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.x3,
              vertical: AppSpace.x2,
            ),
            decoration: BoxDecoration(
              color: selected ? accent : colors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? accent : colors.line),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? colors.onAccent : colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StickyFooter extends StatelessWidget {
  const StickyFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: child,
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: colors.muted),
          const SizedBox(height: 10),
          Text(
            title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class NoteBanner extends StatelessWidget {
  const NoteBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.tone = NoteTone.info,
  });

  final String message;
  final IconData icon;
  final NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final color = switch (tone) {
      NoteTone.info => colors.muted,
      NoteTone.warn => colors.warn,
      NoteTone.success => colors.accent,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

enum NoteTone { info, warn, success }
