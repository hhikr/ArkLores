import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show TextStyle, FontWeight;

import 'app_theme.dart';

/// The dark theme: a complete second theme, not the light one inverted.
/// Near-black paper, light ink, and the Arknights blue as its one accent,
/// which on this ground also works as a line ([trace]) and as text.
class ArkThemeTokens implements AppThemeTokens {
  ArkThemeTokens({this.readingFontFamily});

  @override
  final String? readingFontFamily;

  @override
  final bool isDark = true;

  // ─── Ground ────────────────────────────────────────────────────
  @override
  final Color bgPrimary = const Color(0xFF191919);
  @override
  final Color bgSecondary = const Color(0xFF1E1E1E);

  // ─── Surfaces ──────────────────────────────────────────────────
  @override
  final Color cardSurface = const Color(0xFF222222);
  @override
  final Color cardBorder = const Color(0xFF6E6E6E);
  @override
  final Color surfaceElevated = const Color(0xFF2E2E2E);

  // ─── Accent ────────────────────────────────────────────────────
  @override
  final Color accentPrimary = const Color(0xFF0BA0D0);
  @override
  final Color accentText = const Color(0xFF0BA0D0);
  @override
  final Color onAccent = const Color(0xFF0D0D0D);
  @override
  final Color trace = const Color(0xFF0BA0D0);

  // ─── Semantic colours ──────────────────────────────────────────
  @override
  final Color danger = const Color(0xFFFF8A7A);

  // ─── Text ──────────────────────────────────────────────────────
  @override
  final Color textPrimary = const Color(0xFFEDEDED);
  @override
  final Color textSecondary = const Color(0xFFA3A3A3);
  @override
  final Color textMuted = const Color(0xFF8F8F8F);

  // ─── Lines ─────────────────────────────────────────────────────
  @override
  final Color divider = const Color(0xFF353535);

  @override
  final Color tagBackground = const Color(0xFF3A3A3A);
  @override
  final Color tagForeground = const Color(0xFFEDEDED);

  // ─── Typography ────────────────────────────────────────────────
  @override
  late final TextStyle titleFont =
      sairaStyle(size: 18, weight: 700, color: textPrimary);

  @override
  late final TextStyle bodyFont = TextStyle(
    fontFamilyFallback: cjkSansFallback,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    color: textPrimary,
    height: 1.5,
  );
}
