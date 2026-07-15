import 'dart:ui' show Color;

import 'package:flutter/painting.dart'
    show TextStyle, FontWeight, BorderRadius, BoxShadow, Offset;
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

/// Theme A: Arknights Tactical Archive
///
/// Cyberpunk tactical/industrial aesthetic with cold blue-gray palette,
/// chamfer-corner cards, and geometric decoration lines.
class ArkThemeTokens implements AppThemeTokens {
  @override
  final String themeName = 'ArkTheme';

  @override
  final bool isDark = true;

  // ─── Backgrounds ───────────────────────────────────────────────
  @override
  final Color bgPrimary = const Color(0xFF090A0B);
  @override
  final Color bgSecondary = const Color(0xFF151617);

  // ─── Cards & Surfaces ──────────────────────────────────────────
  @override
  final Color cardSurface = const Color(0xFF202224);
  @override
  final Color cardBorder = const Color(0xFF505457);
  @override
  final Color surfaceElevated = const Color(0xFF292C2E);
  @override
  final Color surfaceOverlay = const Color(0xC20E0F10);

  // ─── Accents ───────────────────────────────────────────────────
  @override
  final Color accentPrimary = const Color(0xFF0BA0D0);
  @override
  final Color accentSecondary = const Color(0xFFCFD6DA);

  // ─── Semantic colors ───────────────────────────────────────────
  @override
  final Color warning = const Color(0xFFD4A843); // Amber-gold
  @override
  final Color danger = const Color(0xFFC0392B); // Deep red

  // ─── Text ──────────────────────────────────────────────────────
  @override
  final Color textPrimary = const Color(0xFFF1F3F4);
  @override
  final Color textSecondary = const Color(0xFFA7AAAC);
  @override
  final Color textMuted = const Color(0xFF6F7274);

  // ─── Borders / Dividers ────────────────────────────────────────
  @override
  final Color divider = const Color(0xFF383B3D);

  // ─── Dynamic / Glow effects ────────────────────────────────────
  @override
  final Color glow = const Color(0xFF0BA0D0);

  // ─── Source badge colors for citation cards ────────────────────
  @override
  final Color wikiBadgeColor = const Color(0xFF4A90D9); // Accent blue
  @override
  final Color bookBadgeColor = const Color(0xFFD4A843); // Amber-gold

  // ─── Bottom navigation ─────────────────────────────────────────
  @override
  final Color navSelectedItem = const Color(0xFF0BA0D0);
  @override
  final Color navUnselectedItem = const Color(0xFF8C979D);

  // ─── Typography ────────────────────────────────────────────────
  @override
  late final TextStyle titleFont = GoogleFonts.getFont(
    'Noto Sans SC',
    fontWeight: FontWeight.w700,
    fontSize: 18,
    color: textPrimary,
  );

  @override
  late final TextStyle bodyFont = GoogleFonts.getFont(
    'Noto Sans SC',
    fontWeight: FontWeight.normal,
    fontSize: 14,
    color: textPrimary,
    height: 1.5,
  );

  // ─── Geometry ──────────────────────────────────────────────────
  @override
  final BorderRadius cardRadius = BorderRadius.zero;

  @override
  final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.3),
      offset: const Offset(0, 2),
      blurRadius: 6,
    ),
  ];

  @override
  final bool isEndfield = false;

  @override
  final double cornerCut = 10;
}
