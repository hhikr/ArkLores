import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/ark_theme_tokens.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The dark (Ark) theme with plain title and body styles, so a widget test
/// does not depend on the reading-font setting. (It was made when the theme
/// fetched Google fonts over the network; the fonts are bundled since 0.17.)
class PlainArkThemeTokens extends ArkThemeTokens {
  @override
  TextStyle get titleFont => const TextStyle(fontWeight: FontWeight.w700);

  @override
  TextStyle get bodyFont => const TextStyle();
}

/// Overrides the app theme with [PlainArkThemeTokens].
Override plainThemeOverride() =>
    themeProvider.overrideWith((ref) => ThemeNotifier(PlainArkThemeTokens()));
