import 'package:flutter/material.dart';
import '../model/app_colors.dart';

/// VIEW LAYER — light-first Material 3 theme (spec §Design System).
///
/// Light is the star (bg #F4F5F9, accent #0E9F6E).
/// Dark is still supported via [dark]. Dynamic color: callers may pass a seed;
/// defaults to the accent.
///
/// Views must use `AppTheme.*` (never `Color(0x...)` / `Colors.*`).
/// Numbers must use [tabular] / [displayNumber] so digits don't jitter.
///
/// NOTE: [AppTheme] statics are light-aware via [isLight] (set by the shell
/// in `main.dart` from UiPrefs + platform brightness). Do NOT use them in
/// `const` expressions — drop `const` where the analyzer complains.
class AppTheme {
  /// Set by the shell before building [MaterialApp]. Defaults to light-first.
  static bool isLight = true;

  // ---- light-first aliases (single source: model/app_colors.dart) ----
  static Color get bg => isLight ? AppColorsLight.background : AppColors.background;
  static Color get card => isLight ? AppColorsLight.surface : AppColors.surface;
  static Color get elevated => isLight ? AppColorsLight.elevated : AppColors.elevated;
  static Color get border => isLight ? AppColorsLight.border : AppColors.border;
  static Color get ink => isLight ? AppColorsLight.ink : AppColors.ink;
  static Color get sub => isLight ? AppColorsLight.sub : AppColors.sub;
  static Color get primary => isLight ? AppColorsLight.primary : AppColors.primary;
  static Color get accent => isLight ? AppColorsLight.accent : AppColors.accent;
  static Color get primarySoft => isLight ? AppColorsLight.primarySoft : AppColors.primarySoft;
  static Color get green => isLight ? AppColorsLight.success : AppColors.success;
  static Color get red => isLight ? AppColorsLight.danger : AppColors.danger;
  static Color get amber => isLight ? AppColorsLight.warning : AppColors.warning;
  static Color get blue => isLight ? AppColorsLight.info : AppColors.info;
  static Color get unknown => isLight ? AppColorsLight.unknown : AppColors.unknown;
  static Color get disabled => isLight ? AppColorsLight.disabled : AppColors.disabled;
  static Color get chipInactive => isLight ? AppColorsLight.chipInactive : AppColors.chipInactive;
  static Color get panel => isLight ? AppColorsLight.panel : AppColors.panel;
  static Color get track => isLight ? AppColorsLight.track : AppColors.track;
  static Color get dangerSoft => isLight ? AppColorsLight.dangerSoft : AppColors.dangerSoft;
  static Color get dangerBorder => isLight ? AppColorsLight.dangerBorder : AppColors.dangerBorder;
  static Color get successSoft => isLight ? AppColorsLight.successSoft : AppColors.successSoft;
  static Color get successBorder => isLight ? AppColorsLight.successBorder : AppColors.successBorder;
  static Color get successMint => isLight ? AppColorsLight.successMint : AppColors.successMint;
  static Color get warningSoft => isLight ? AppColorsLight.warningSoft : AppColors.warningSoft;
  static Color get warningBorder => isLight ? AppColorsLight.warningBorder : AppColors.warningBorder;
  static Color get warningIcon => isLight ? AppColorsLight.warningIcon : AppColors.warningIcon;
  static Color get warningText => isLight ? AppColorsLight.warningText : AppColors.warningText;
  static Color get cursor => isLight ? AppColorsLight.cursor : AppColors.cursor;
  static Color get heat0 => isLight ? AppColorsLight.heat0 : AppColors.heat0;
  static Color get heat1 => isLight ? AppColorsLight.heat1 : AppColors.heat1;
  static Color get heat2 => isLight ? AppColorsLight.heat2 : AppColors.heat2;
  static Color get heat3 => isLight ? AppColorsLight.heat3 : AppColors.heat3;
  static Color get chartFillTop => isLight ? AppColorsLight.chartFillTop : AppColors.chartFillTop;
  static Color get chartFillBottom => isLight ? AppColorsLight.chartFillBottom : AppColors.chartFillBottom;
  static Color get cardShadow => isLight ? AppColorsLight.cardShadow : AppColors.cardShadow;
  static Color get onDark => AppColors.onDark;
  static Color get onAccent => isLight ? AppColorsLight.onAccent : AppColors.onAccent;

  // ---- motion (spec: 200ms entry, 120ms value change) ----
  static const entryMs = 200;
  static const valueMs = 120;

  // ---- type (spec hierarchy) ----
  static TextStyle get displayNumber => TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: ink,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontFamilyFallback: const ['monospace'],
      );
  static TextStyle get heroNumber => TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: ink,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontFamilyFallback: const ['monospace'],
      );
  static TextStyle get body => TextStyle(fontSize: 15, color: ink);
  static TextStyle get muted => TextStyle(fontSize: 12, color: sub);
  static TextStyle get microLabel => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: sub,
      );
  static const tabular = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontFamilyFallback: ['monospace'],
  );

  static Color statusColor(String status) {
    if (status == 'down') return red;
    if (status != 'ok') return unknown;
    return green;
  }

  static ThemeData dark({Color? seed}) {
    final seedColor = seed ?? AppColors.primary;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppColors.background,
      primary: seedColor,
      onPrimary: AppColors.onAccent,
      error: AppColors.danger,
    );
    return _base(scheme, Brightness.dark);
  }

  static ThemeData light({Color? seed}) {
    final seedColor = seed ?? AppColorsLight.primary;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    ).copyWith(
      surface: AppColorsLight.background,
      primary: seedColor,
      error: AppColorsLight.danger,
    );
    return _base(scheme, Brightness.light, light: true);
  }

  static ThemeData _base(ColorScheme scheme, Brightness b,
      {bool light = false}) {
    final scaffold = light ? AppColorsLight.background : AppColors.background;
    final cardC = light ? AppColorsLight.surface : AppColors.surface;
    final borderC = light ? AppColorsLight.border : AppColors.border;
    final inkC = light ? AppColorsLight.ink : AppColors.ink;
    final subC = light ? AppColorsLight.sub : AppColors.sub;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold.withValues(alpha: 0.82),
        foregroundColor: inkC,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: inkC,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: borderC),
        ),
        color: cardC,
        shadowColor: AppColors.cardShadow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardC,
        hintStyle: TextStyle(color: subC, fontSize: 13.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderC),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderC),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardC,
        elevation: 0,
        indicatorColor: scheme.primary.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5, color: inkC),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: light ? Colors.white : AppColors.onAccent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: light ? AppColorsLight.ink : AppColors.elevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: inkC,
            fontSize: 17),
        titleSmall: TextStyle(fontWeight: FontWeight.w700, color: inkC),
        bodySmall: TextStyle(color: subC),
      ),
    );
  }
}
