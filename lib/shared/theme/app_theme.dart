import 'dart:ui' show Color, FontFeature, FontVariation;

import 'package:flutter/painting.dart'
    show TextStyle, FontWeight, BorderRadius, BoxShadow;

/// The colours, type and shapes of the app (0.17). Two complete themes:
/// [EndfieldThemeTokens] (light: paper and ink, signal yellow) and
/// [ArkThemeTokens] (dark: near-black paper, the Arknights blue). Each
/// theme has ONE accent, used only for "you are here", "you can act on
/// this" and "look at this", and only as a fill (and, on dark, as a line).
///
/// Every UI component reads tokens via `ref.watch(themeProvider)` and never
/// hardcodes a colour, font or spacing value.
abstract class AppThemeTokens {
  // ─── Ground ────────────────────────────────────────────────────
  /// The page ground ("paper").
  Color get bgPrimary;

  /// A quieter ground: bars and wells that sit on the paper.
  Color get bgSecondary;

  // ─── Surfaces ──────────────────────────────────────────────────
  /// Panels, sheets, inputs, bars ("panel").
  Color get cardSurface;

  /// The frame of a control (an input, a button outline): ≥ 3:1 on paper.
  Color get cardBorder;

  /// Quiet fills: idle buttons, chips, tracks ("chip").
  Color get surfaceElevated;
  Color get surfaceOverlay;

  // ─── Accent ────────────────────────────────────────────────────
  /// The one accent, as a fill. Light: signal yellow; dark: Arknights blue.
  Color get accentPrimary;

  /// A quiet companion fill (= chip).
  Color get accentSecondary;

  /// "Here" as text, an icon or a thin line on paper / panel (contrast
  /// ≥ 4.5): ink on light, where yellow lines vanish; the accent on dark.
  Color get accentText;

  /// Text and icons drawn on an [accentPrimary] fill.
  Color get onAccent;

  /// A line that marks where you are (reading progress, a pressed row, a
  /// focused field): ink on light, the accent on dark (= [accentText]).
  Color get trace;

  // ─── Semantic colours ──────────────────────────────────────────
  /// Look at this: drawn as an accent block with ink, never red.
  Color get warning;

  /// Deleting, and nothing else.
  Color get danger;

  // ─── Text ──────────────────────────────────────────────────────
  Color get textPrimary;
  Color get textSecondary;

  /// The faintest text still readable (≥ 4.5:1 on paper).
  Color get textMuted;

  // ─── Lines ─────────────────────────────────────────────────────
  /// 1px hairlines between parts.
  Color get divider;

  // ─── Index tags (No.024, stage codes) ──────────────────────────
  Color get tagBackground;
  Color get tagForeground;

  /// Behind sheets and dialogs.
  Color get scrim;

  Color get glow;

  // ─── Source badge colours for citation cards ───────────────────
  Color get wikiBadgeColor;
  Color get bookBadgeColor;

  // ─── Bottom navigation ─────────────────────────────────────────
  Color get navSelectedItem;
  Color get navUnselectedItem;

  // ─── Typography ────────────────────────────────────────────────
  /// Headings and labels: Saira (wide geometric Latin) over the Chinese sans.
  TextStyle get titleFont;

  /// Running text and list titles: the Chinese sans, regular.
  TextStyle get bodyFont;

  /// The font of long reading text (Settings): null for the Chinese sans.
  String? get readingFontFamily;

  // ─── Geometry ──────────────────────────────────────────────────
  BorderRadius get cardRadius;
  List<BoxShadow> get cardShadow;

  // ─── Visual language ───────────────────────────────────────────
  bool get isEndfield;

  /// The small cut corner of a pressable thing.
  double get cornerCut;

  // ─── Theme metadata ────────────────────────────────────────────
  String get themeName;
  bool get isDark;
}

/// The Chinese sans the interface falls back to after Saira: the bundled
/// Noto Sans SC (思源黑体, variable weight, so a heading's weight is the
/// same on every phone); the system's own only for what it lacks.
const List<String> cjkSansFallback = ['NotoSansSC', 'sans-serif'];

/// The interface face: Saira, a variable font whose weight and width are
/// set through its axes (a plain `fontWeight` does not change its glyphs).
TextStyle sairaStyle({
  double size = 14,
  double weight = 400,
  double width = 100,
  Color? color,
  double? height,
  double spacing = 0,
  bool tabular = false,
}) =>
    TextStyle(
      fontFamily: 'Saira',
      fontFamilyFallback: cjkSansFallback,
      fontSize: size,
      fontWeight: _weightOf(weight),
      fontVariations: [
        FontVariation('wght', weight),
        FontVariation('wdth', width),
      ],
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      color: color,
      height: height,
      letterSpacing: spacing == 0 ? null : spacing * size,
    );

FontWeight _weightOf(double w) =>
    FontWeight.values[((w / 100).round() - 1).clamp(0, 8)];

/// The in-world script of Arknights and Endfield (EndfieldByButan, see
/// assets/fonts/README.md): Latin letters, digits and a little punctuation
/// as its glyphs, nothing else (Chinese falls back to the interface face).
/// Decoration only: the small labels over headings and tabs, never text
/// that has to be read.
TextStyle cipherStyle({
  double size = 12,
  Color? color,
  double? height,
  double spacing = 0,
}) =>
    TextStyle(
      fontFamily: 'EndfieldCipher',
      fontFamilyFallback: const ['Saira', ...cjkSansFallback],
      fontSize: size,
      color: color,
      height: height,
      letterSpacing: spacing == 0 ? null : spacing * size,
    );

/// Type roles, read off the theme so the colours follow it.
extension AppType on AppThemeTokens {
  /// Interface text in Saira (buttons, labels, headings).
  TextStyle ui(
    double size, {
    double weight = 600,
    double width = 100,
    Color? color,
    double? height,
  }) =>
      sairaStyle(
        size: size,
        weight: weight,
        width: width,
        color: color ?? textPrimary,
        height: height,
      );

  /// The small upper-case label over a heading (`RECORDS`) or a tab:
  /// decoration, in the in-world script ([cipherStyle]); what it says is
  /// also said in Chinese next to it.
  TextStyle eyebrow({Color? color, double size = 12}) => cipherStyle(
        size: size,
        color: color ?? textSecondary,
        spacing: 0.12,
        height: 1.2,
      );

  /// A small wide upper-case label that is read (not decoration): Saira at
  /// its heaviest, wide, the Chinese bold beside it.
  TextStyle label({Color? color, double size = 12}) => sairaStyle(
        size: size,
        weight: 800,
        width: 125,
        color: color ?? textSecondary,
        spacing: 0.12,
        height: 1.2,
      );

  /// Numbers, dates, counts: wide, tabular.
  TextStyle field({Color? color, double size = 13, double weight = 500}) =>
      sairaStyle(
        size: size,
        weight: weight,
        width: 112,
        color: color ?? textSecondary,
        tabular: true,
        height: 1.4,
      );

  /// A heading in bold Chinese; a page's big title (22 and up) in the
  /// heaviest weight, like the games' big white captions.
  TextStyle heading(double size, {Color? color}) => sairaStyle(
        size: size,
        weight: size >= 22 ? 900 : 700,
        color: color ?? textPrimary,
        height: 1.3,
      );

  /// Running text.
  TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.6,
  }) =>
      bodyFont.copyWith(
        fontSize: size,
        fontWeight: weight,
        color: color ?? textPrimary,
        height: height,
      );
}
