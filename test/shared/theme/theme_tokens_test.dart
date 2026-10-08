import 'dart:math' as math;

import 'package:arklores/shared/theme/app_theme.dart';
import 'package:arklores/shared/theme/ark_theme_tokens.dart';
import 'package:arklores/shared/theme/endfield_theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backgrounds follow the revised palette; the accents stay', () {
    final ark = ArkThemeTokens();
    final endfield = EndfieldThemeTokens();
    expect(ark.bgPrimary.r, closeTo(ark.bgPrimary.g, 0.01));
    expect(ark.bgPrimary.g, closeTo(ark.bgPrimary.b, 0.01));
    expect(endfield.isDark, isFalse);
    expect(endfield.bgPrimary.computeLuminance(), greaterThan(0.85));
    expect(endfield.cardSurface.computeLuminance(), greaterThan(0.95));
    expect(ark.accentPrimary, const Color(0xFF0BA0D0));
    expect(endfield.accentPrimary, const Color(0xFFF8D439));
  });

  group('accent text contrast', () {
    double luminance(Color c) => c.computeLuminance();
    double contrast(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final AppThemeTokens theme in [EndfieldThemeTokens(), ArkThemeTokens()]) {
      test('${theme.themeName}: accentText is readable on its surfaces', () {
        for (final surface in [
          theme.bgPrimary,
          theme.bgSecondary,
          theme.cardSurface,
        ]) {
          expect(contrast(theme.accentText, surface), greaterThanOrEqualTo(4.5));
        }
        expect(
          contrast(theme.onAccent, theme.accentPrimary),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
}
