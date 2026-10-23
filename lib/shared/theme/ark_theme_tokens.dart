import 'dart:ui' show Color;

import 'package:flutter/painting.dart'
    show TextStyle, FontWeight, BorderRadius, BoxShadow;

import 'app_theme.dart';

/// The dark theme: a complete second theme, not the light one inverted.
/// Near-black paper, light ink, and the Arknights blue as its one accent,
/// which on this ground also works as a line ([trace]) and as text.
class ArkThemeTokens implements AppThemeTokens {
  ArkThemeTokens({this.readingFontFamily});

  @override
  final String? readingFontFamily;

  @override
  final String themeName = 'ArkTheme';

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
  @override
  final Color surfaceOverlay = const Color(0xF5222222);

  // ─── Accent ────────────────────────────────────────────────────
  @override
  final Color accentPrimary = const Color(0xFF0BA0D0);
  @override
  final Color accentSecondary = const Color(0xFF2E2E2E);
  @override
  final Color accentText = const Color(0xFF0BA0D0);
  @override
  final Color onAccent = const Color(0xFF0D0D0D);
  @override
  final Color trace = const Color(0xFF0BA0D0);

  // ─── Semantic colours ──────────────────────────────────────────
  @override
  final Color warning = const Color(0xFF0BA0D0);
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
  @override
  final Color scrim = const Color(0xA0000000);

  @override
  final Color glow = const Color(0xFF0BA0D0);

  @override
  final Color wikiBadgeColor = const Color(0xFF0BA0D0);
  @override
  final Color bookBadgeColor = const Color(0xFFA3A3A3);

  @override
  final Color navSelectedItem = const Color(0xFF0D0D0D);
  @override
  final Color navUnselectedItem = const Color(0xFFA3A3A3);

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

  // ─── Geometry ──────────────────────────────────────────────────
  @override
  final BorderRadius cardRadius = BorderRadius.zero;

  @override
  final List<BoxShadow> cardShadow = const [];

  @override
  final bool isEndfield = false;

  @override
  final double cornerCut = 8;
}
