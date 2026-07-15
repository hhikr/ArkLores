import 'dart:ui' show Color;

import 'package:flutter/painting.dart'
    show TextStyle, FontWeight, BorderRadius, BoxShadow, Offset;
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

/// Theme B: Endfield Holographic Projection
///
/// Futuristic sci-fi with spatial/diegetic UI, semi-transparent frosted
/// glass cards, cyan holographic accents, and grid drift animation.
class EndfieldThemeTokens implements AppThemeTokens {
  @override
  final String themeName = 'EndfieldTheme';

  @override
  final bool isDark = true;

  // ─── Backgrounds ───────────────────────────────────────────────
  @override
  final Color bgPrimary =
      const Color(0xFF050810); // Deep near-black with blue-violet
  @override
  final Color bgSecondary = const Color(0xFF0C1020); // Deep cosmic blue

  // ─── Cards & Surfaces ──────────────────────────────────────────
  @override
  final Color cardSurface =
      const Color(0xB3101828); // Translucent deep blue (frosted glass)
  @override
  final Color cardBorder = const Color(0x2600C8FF); // Subtle holographic cyan

  // ─── Accents ───────────────────────────────────────────────────
  @override
  final Color accentPrimary = const Color(0xFF00C8FF); // Holographic cyan
  @override
  final Color accentSecondary = const Color(0xFF7B61FF); // Violet-blue

  // ─── Semantic colors ───────────────────────────────────────────
  @override
  final Color warning = const Color(0xFFFFB800); // Warm amber
  @override
  final Color danger = const Color(0xFFFF4D6A); // Hot red

  // ─── Text ──────────────────────────────────────────────────────
  @override
  final Color textPrimary = const Color(0xFFC8E0F0); // Cold blue-white
  @override
  final Color textSecondary = const Color(0xFF4A6080); // Dark blue-gray

  // ─── Borders / Dividers ────────────────────────────────────────
  @override
  final Color divider = const Color(0x2600C8FF); // Subtle holographic cyan

  // ─── Dynamic / Glow effects ────────────────────────────────────
  @override
  final Color glow = const Color(0xFF00C8FF); // Holographic cyan

  // ─── Source badge colors for citation cards ────────────────────
  @override
  final Color wikiBadgeColor = const Color(0xFF00C8FF); // Holographic cyan
  @override
  final Color bookBadgeColor = const Color(0xFFFFB800); // Warm amber

  // ─── Bottom navigation ─────────────────────────────────────────
  @override
  final Color navSelectedItem = const Color(0xFF00C8FF);
  @override
  final Color navUnselectedItem = const Color(0xFF4A6080);

  // ─── Typography ────────────────────────────────────────────────
  @override
  late final TextStyle titleFont = GoogleFonts.exo2(
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
  final BorderRadius cardRadius = BorderRadius.circular(12);

  @override
  final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF00C8FF).withValues(alpha: 0.25),
      offset: const Offset(0, 0),
      blurRadius: 12,
    ),
  ];
}
