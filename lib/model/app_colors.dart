import 'package:flutter/material.dart';

/// MODEL LAYER — single source of truth for every color in the app.
///
/// RULE: no view / view-model / theme file may hardcode `Color(0x...)`
/// or `Colors.*`. They must refer to a named constant below.
///
/// Light-first (spec): background #F4F5F9, surface #FFFFFF,
/// accent #0E9F6E. Dark palette lives in [AppColors] in this same file
/// for dark mode.
class AppColors {
  AppColors._();

  // ---------- core surfaces & text ----------
  /// App scaffold background.
  static const background = Color(0xFF0B0D10);

  /// Cards, sheets, nav bar.
  static const surface = Color(0xFF14171C);

  /// Elevated cards / panels / pressed states.
  static const elevated = Color(0xFF1B1F26);

  /// Hairline borders on cards / inputs / chips: white @ 6%.
  static const border = Color(0x0FFFFFFF);

  /// Primary text on dark.
  static const ink = Color(0xFFF2F4F8);

  /// Secondary / hint / muted text and icons.
  static const sub = Color(0xFF9AA3B2);

  // ---------- brand ----------
  static const primary = Color(0xFF3DDC97);
  static const accent = primary;
  static const primarySoft = Color(0x243DDC97);

  /// Chart area-fill gradient (top -> bottom). Derived from [primary].
  static const chartFillTop = Color(0x663DDC97);
  static const chartFillBottom = Color(0x0A3DDC97);

  // ---------- status (semantic only, never decorative) ----------
  static const success = Color(0xFF3DDC97);
  static const danger = Color(0xFFFF5C5C);
  static const warning = Color(0xFFFFB020);
  static const info = Color(0xFF6EA8FE);

  /// "Unknown / offline-grey" status dot.
  static const unknown = Color(0xFF5A6272);

  /// Disabled / null usage bar.
  static const disabled = Color(0xFF3A4150);

  // ---------- tinted containers ----------
  /// Error banners, down-server boxes.
  static const dangerSoft = Color(0x1FFf5C5C);
  static const dangerBorder = Color(0x40FF5C5C);

  /// Test-OK banner background + border.
  static const successSoft = Color(0x1F3DDC97);
  static const successBorder = Color(0x403DDC97);

  /// Traffic "up" pill.
  static const successMint = Color(0x243DDC97);

  /// Unsaved-changes banner.
  static const warningSoft = Color(0x1FFFB020);
  static const warningBorder = Color(0x40FFB020);
  static const warningIcon = Color(0xFFFFB020);
  static const warningText = Color(0xFFFFC964);

  // ---------- chrome ----------
  /// Unselected pills / icon buttons / range selectors.
  static const chipInactive = Color(0xFF1B1F26);

  /// Metric panels, chart empty state, preview box, history rows.
  static const panel = Color(0xFF1B1F26);

  /// Progress track, chart grid lines, heatmap "empty" cell.
  static const track = Color(0xFF262C36);

  /// Dashed chart cursor.
  static const cursor = Color(0xFF5A6272);

  // ---------- heatmap scale (low -> high, teal ramp) ----------
  static const heat0 = track;
  static const heat1 = Color(0xFF1E3A30);
  static const heat2 = Color(0xFF27634D);
  static const heat3 = Color(0xFF2F9468);
  // heat4 == primary

  // ---------- shadows / glow ----------
  static const cardShadow = Color(0x40000000);
  static const themeShadow = Color(0x40000000);

  // ---------- on-colors ----------
  /// Text/icons drawn on top of [ink] fills (light text on dark chip).
  static const onDark = Color(0xFFFFFFFF);

  /// Text drawn on top of accent fill (dark text on teal).
  static const onAccent = Color(0xFF06281B);
}

/// Light primary palette (same roles, light values).
/// Lives in the same file so rebrand still touches one file.
class AppColorsLight {
  AppColorsLight._();

  static const background = Color(0xFFF4F5F9);
  static const surface = Color(0xFFFFFFFF);
  static const elevated = Color(0xFFF7F8FC);
  static const border = Color(0xFFE8EAF0);
  static const ink = Color(0xFF111827);
  static const sub = Color(0xFF8A8FA3);
  static const primary = Color(0xFF0E9F6E);
  static const accent = primary;
  static const primarySoft = Color(0xFFE3F5EC);
  static const chartFillTop = Color(0x330E9F6E);
  static const chartFillBottom = Color(0x070E9F6E);
  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFDC2626);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF2563EB);
  static const unknown = Color(0xFFB6BAC8);
  static const disabled = Color(0xFFD5D8E2);
  static const dangerSoft = Color(0xFFFEF2F2);
  static const dangerBorder = Color(0xFFFECACA);
  static const successSoft = Color(0xFFF0FDF4);
  static const successBorder = Color(0xFFBBF7D0);
  static const successMint = Color(0xFFDCFCE7);
  static const warningSoft = Color(0xFFFFFBEB);
  static const warningBorder = Color(0xFFFDE68A);
  static const warningIcon = Color(0xFFB45309);
  static const warningText = Color(0xFF92400E);
  static const chipInactive = Color(0xFFF1F2F6);
  static const panel = Color(0xFFF7F8FC);
  static const track = Color(0xFFEEF0F5);
  static const cursor = Color(0xFFB9BDCB);
  static const heat0 = track;
  static const heat1 = Color(0xFFC9EEDB);
  static const heat2 = Color(0xFF8FDDb8);
  static const heat3 = Color(0xFF4CC38A);
  static const cardShadow = Color(0x08000000);
  static const themeShadow = Color(0x0A000000);
  static const onDark = Color(0xFFFFFFFF);
  static const onAccent = Color(0xFFFFFFFF);
}
