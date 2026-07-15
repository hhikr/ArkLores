import 'dart:ui' show Color;

import 'package:flutter/painting.dart'
    show TextStyle, FontWeight, BorderRadius, BoxShadow, Offset;
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

/// Theme B: Endfield Holographic Projection
///
/// Restrained black/white industrial UI with signal-yellow interaction states.
class EndfieldThemeTokens implements AppThemeTokens {
  @override
  final String themeName = 'EndfieldTheme';

  @override
  final bool isDark = false;

  // ─── Backgrounds ───────────────────────────────────────────────
  @override
  final Color bgPrimary = const Color(0xFFF5F5F2);
  @override
  final Color bgSecondary = const Color(0xFFE7E8E5);

  // ─── Cards & Surfaces ──────────────────────────────────────────
  @override
  final Color cardSurface = const Color(0xFFFCFCF9);
  @override
  final Color cardBorder = const Color(0xFF9A9E9B);
  @override
  final Color surfaceElevated = const Color(0xFFE1E2DF);
  @override
  final Color surfaceOverlay = const Color(0xEFFFFFFC);

  // ─── Accents ───────────────────────────────────────────────────
  @override
  final Color accentPrimary = const Color(0xFFF8D439);
  @override
  final Color accentSecondary = const Color(0xFFF3F4EF);

  // ─── Semantic colors ───────────────────────────────────────────
  @override
  final Color warning = const Color(0xFFFFC400);
  @override
  final Color danger = const Color(0xFFFF6262);

  // ─── Text ──────────────────────────────────────────────────────
  @override
  final Color textPrimary = const Color(0xFF141615);
  @override
  final Color textSecondary = const Color(0xFF555A57);
  @override
  final Color textMuted = const Color(0xFF7C817E);

  // ─── Borders / Dividers ────────────────────────────────────────
  @override
  final Color divider = const Color(0xFFC7CAC6);

  // ─── Dynamic / Glow effects ────────────────────────────────────
  @override
  final Color glow = const Color(0xFFF8D439);

  // ─── Source badge colors for citation cards ────────────────────
  @override
  final Color wikiBadgeColor = const Color(0xFFF8D439);
  @override
  final Color bookBadgeColor = const Color(0xFFFFB800); // Warm amber

  // ─── Bottom navigation ─────────────────────────────────────────
  @override
  final Color navSelectedItem = const Color(0xFFF8D439);
  @override
  final Color navUnselectedItem = const Color(0xFF666B68);

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
      color: const Color(0xFF000000).withValues(alpha: 0.12),
      offset: const Offset(0, 2),
      blurRadius: 6,
    ),
  ];

  @override
  final bool isEndfield = true;

  @override
  final double cornerCut = 12;
}
