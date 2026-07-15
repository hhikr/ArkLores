import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show TextStyle, BorderRadius, BoxShadow;

/// Abstract definition of all theme tokens used across the app.
///
/// Two concrete implementations exist:
/// - [ArkThemeTokens] — Tactical Archive (Arknights industrial aesthetic)
/// - [EndfieldThemeTokens] — Industrial Signal (Endfield black/white/yellow)
///
/// Every UI component MUST read tokens via [ref.watch(themeProvider)]
/// and MUST NOT hardcode any color, font, or spacing value.
abstract class AppThemeTokens {
  // ─── Backgrounds ───────────────────────────────────────────────
  Color get bgPrimary;
  Color get bgSecondary;

  // ─── Cards & Surfaces ──────────────────────────────────────────
  Color get cardSurface;
  Color get cardBorder;
  Color get surfaceElevated;
  Color get surfaceOverlay;

  // ─── Accents ───────────────────────────────────────────────────
  Color get accentPrimary;
  Color get accentSecondary;

  // ─── Semantic colors ───────────────────────────────────────────
  Color get warning;
  Color get danger;

  // ─── Text ──────────────────────────────────────────────────────
  Color get textPrimary;
  Color get textSecondary;
  Color get textMuted;

  // ─── Borders / Dividers ────────────────────────────────────────
  Color get divider;

  // ─── Dynamic / Glow effects ────────────────────────────────────
  Color get glow;

  // ─── Source badge colors for citation cards ────────────────────
  Color get wikiBadgeColor;
  Color get bookBadgeColor;

  // ─── Bottom navigation ─────────────────────────────────────────
  Color get navSelectedItem;
  Color get navUnselectedItem;

  // ─── Typography ────────────────────────────────────────────────
  TextStyle get titleFont;
  TextStyle get bodyFont;

  // ─── Geometry ──────────────────────────────────────────────────
  BorderRadius get cardRadius;
  List<BoxShadow> get cardShadow;

  // ─── Visual language ───────────────────────────────────────────
  bool get isEndfield;
  double get cornerCut;

  // ─── Theme metadata ────────────────────────────────────────────
  String get themeName;
  bool get isDark;
}
