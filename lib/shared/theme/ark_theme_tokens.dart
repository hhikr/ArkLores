import 'dart:ui' show Color;

import 'package:flutter/painting.dart'
    show TextStyle, FontWeight, BorderRadius, Radius, BoxShadow, Offset;
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
  final Color bgPrimary = const Color(0xFF0B0D10); // Near-black with blue tint
  @override
  final Color bgSecondary = const Color(0xFF13181F); // Deep slate-gray blue

  // ─── Cards & Surfaces ──────────────────────────────────────────
  @override
  final Color cardSurface = const Color(0xFF1A2233); // Blue-tinted dark gray
  @override
  final Color cardBorder = const Color(0xFF1E2D40); // Deep blue-gray

  // ─── Accents ───────────────────────────────────────────────────
  @override
  final Color accentPrimary = const Color(0xFF4A90D9); // Cold steel blue
  @override
  final Color accentSecondary = const Color(0xFFA8C8E8); // Pale ice blue

  // ─── Semantic colors ───────────────────────────────────────────
  @override
  final Color warning = const Color(0xFFD4A843); // Amber-gold
  @override
  final Color danger = const Color(0xFFC0392B); // Deep red

  // ─── Text ──────────────────────────────────────────────────────
  @override
  final Color textPrimary = const Color(0xFFE2E8F0); // Light cold white
  @override
  final Color textSecondary = const Color(0xFF6B7F99); // Gray-blue

  // ─── Borders / Dividers ────────────────────────────────────────
  @override
  final Color divider = const Color(0xFF1E2D40); // Deep blue-gray

  // ─── Dynamic / Glow effects ────────────────────────────────────
  @override
  final Color glow = const Color(0xFF5BA3E0); // Bright blue

  // ─── Source badge colors for citation cards ────────────────────
  @override
  final Color wikiBadgeColor = const Color(0xFF4A90D9); // Accent blue
  @override
  final Color bookBadgeColor = const Color(0xFFD4A843); // Amber-gold

  // ─── Bottom navigation ─────────────────────────────────────────
  @override
  final Color navSelectedItem = const Color(0xFF4A90D9);
  @override
  final Color navUnselectedItem = const Color(0xFF6B7F99);

  // ─── Typography ────────────────────────────────────────────────
  @override
  late final TextStyle titleFont = GoogleFonts.rajdhani(
    fontWeight: FontWeight.w600,
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
  final BorderRadius cardRadius = BorderRadius.only(
    topRight: const Radius.circular(12),
    topLeft: const Radius.circular(4),
    bottomRight: const Radius.circular(4),
    bottomLeft: const Radius.circular(4),
  );

  @override
  final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.3),
      offset: const Offset(0, 2),
      blurRadius: 8,
    ),
  ];
}
