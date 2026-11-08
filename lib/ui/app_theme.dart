import 'package:flutter/material.dart';

abstract final class AppSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x7 = 28;
}

abstract final class AppRadius {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double sheet = 24;
  static const double pill = 999;
}

abstract final class AppMotion {
  static const selection = Duration(milliseconds: 160);
  static const progress = Duration(milliseconds: 260);
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.danger,
    required this.warn,
    required this.success,
    required this.info,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color danger;
  final Color warn;
  final Color success;
  final Color info;

  static AppColors of(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors extension is missing from the theme.');
    return colors!;
  }

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? danger,
    Color? warn,
    Color? success,
    Color? info,
  }) => AppColors(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    accentSoft: accentSoft ?? this.accentSoft,
    danger: danger ?? this.danger,
    warn: warn ?? this.warn,
    success: success ?? this.success,
    info: info ?? this.info,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      success: Color.lerp(success, other.success, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

const _light = AppColors(
  bg: Color(0xFFF5F8FA),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFE3EAF0),
  ink: Color(0xFF1C2933),
  muted: Color(0xFF64748B),
  line: Color(0xFFE3EAF0),
  accent: Color(0xFF19B6A0),
  onAccent: Color(0xFF101D27),
  accentSoft: Color(0xFFA6E5D8),
  danger: Color(0xFFDC4C4C),
  warn: Color(0xFFE9A23B),
  success: Color(0xFF16A36A),
  info: Color(0xFF3986C8),
);

const _dark = AppColors(
  bg: Color(0xFF101D27),
  surface: Color(0xFF1B2D39),
  surfaceAlt: Color(0xFF243946),
  ink: Color(0xFFEAF1F4),
  muted: Color(0xFFA7B6C1),
  line: Color(0xFF304451),
  accent: Color(0xFF19B6A0),
  onAccent: Color(0xFF101D27),
  accentSoft: Color(0xFF21574F),
  danger: Color(0xFFDC4C4C),
  warn: Color(0xFFE9A23B),
  success: Color(0xFF16A36A),
  info: Color(0xFF3986C8),
);

class AppTheme {
  static ThemeData light() => _build(_light, Brightness.light);
  static ThemeData dark() => _build(_dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF142B3B),
          brightness: brightness,
        ).copyWith(
          primary: colors.accent,
          onPrimary: colors.onAccent,
          secondary: const Color(0xFF142B3B),
          onSecondary: Colors.white,
          surface: colors.surface,
          onSurface: colors.ink,
          error: colors.danger,
          onError: Colors.white,
          outline: colors.line,
          outlineVariant: colors.line,
          surfaceContainerHighest: colors.surfaceAlt,
        );
    final text = TextTheme(
      displaySmall: TextStyle(
        fontSize: 32,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: colors.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: colors.ink,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
        color: colors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: colors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: colors.ink,
      ),
      bodyLarge: TextStyle(fontSize: 14, height: 1.5, color: colors.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: colors.ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: colors.muted),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: colors.ink,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.35,
        color: colors.muted,
      ),
    ).apply(fontFamily: 'Plus Jakarta Sans');

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Plus Jakarta Sans',
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.bg,
      canvasColor: colors.bg,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          side: BorderSide(color: colors.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          minimumSize: const Size.fromHeight(52),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.ink,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: colors.line),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: colors.ink),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surface,
        selectedColor: colors.accentSoft,
        side: BorderSide(color: colors.line),
        labelStyle: text.labelLarge!,
        secondaryLabelStyle: text.labelLarge!.copyWith(color: colors.accent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: colors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.line,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF142B3B),
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.muted,
        textColor: colors.ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
    );
  }
}

/// Tabular figures keep size deltas from jittering while compressing.
const TextStyle kNumbers = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
  fontWeight: FontWeight.w700,
  letterSpacing: -0.4,
);
