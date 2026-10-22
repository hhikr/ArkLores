import 'dart:ui' show Color;

import 'package:flutter/painting.dart'
    show TextStyle, FontWeight, BorderRadius, BoxShadow;

import 'app_theme.dart';

/// The light theme: off-white paper, ink, one signal yellow.
///
/// The yellow is a fill only: on white it is 1.1:1, so lines and text that
/// mean "here" are ink ([trace], [accentText]).
class EndfieldThemeTokens implements AppThemeTokens {
  EndfieldThemeTokens({this.readingFontFamily});

  @override
  final String? readingFontFamily;

  @override
  final String themeName = 'EndfieldTheme';

  @override
  final bool isDark = false;

  // ─── Ground ────────────────────────────────────────────────────
  @override
  final Color bgPrimary = const Color(0xFFF4F4F2);
  @override
  final Color bgSecondary = const Color(0xFFECECE9);

  // ─── Surfaces ──────────────────────────────────────────────────
  @override
  final Color cardSurface = const Color(0xFFFFFFFF);
  @override
  final Color cardBorder = const Color(0xFF8E8E8A);
  @override
  final Color surfaceElevated = const Color(0xFFE4E4E0);
  @override
  final Color surfaceOverlay = const Color(0xF5FFFFFF);

  // ─── Accent ────────────────────────────────────────────────────
  @override
  final Color accentPrimary = const Color(0xFFF8D439);
  @override
  final Color accentSecondary = const Color(0xFFE4E4E0);
  @override
  final Color accentText = const Color(0xFF161616);
  @override
  final Color onAccent = const Color(0xFF161616);
  @override
  final Color trace = const Color(0xFF161616);

  // ─── Semantic colours ──────────────────────────────────────────
  @override
  final Color warning = const Color(0xFFF8D439);
  @override
  final Color danger = const Color(0xFFB3261E);

  // ─── Text ──────────────────────────────────────────────────────
  @override
  final Color textPrimary = const Color(0xFF161616);
  @override
  final Color textSecondary = const Color(0xFF5C5C5C);
  @override
  final Color textMuted = const Color(0xFF6B6B68);

  // ─── Lines ─────────────────────────────────────────────────────
  @override
  final Color divider = const Color(0xFFD9D9D6);

  @override
  final Color tagBackground = const Color(0xFF161616);
  @override
  final Color tagForeground = const Color(0xFFFFFFFF);
  @override
  final Color scrim = const Color(0x80161616);

  @override
  final Color glow = const Color(0xFFF8D439);

  @override
  final Color wikiBadgeColor = const Color(0xFF161616);
  @override
  final Color bookBadgeColor = const Color(0xFF5C5C5C);

  @override
  final Color navSelectedItem = const Color(0xFF161616);
  @override
  final Color navUnselectedItem = const Color(0xFF5C5C5C);

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
  final bool isEndfield = true;

  @override
  final double cornerCut = 8;
}
