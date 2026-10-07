import 'package:arklores/shared/providers/theme_provider.dart';
import 'package:arklores/shared/theme/ark_theme_tokens.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Ark theme with plain text styles: its Google fonts would be fetched
/// over the network, which a widget test cannot do (the failed fetch is
/// thrown into the test).
class PlainArkThemeTokens extends ArkThemeTokens {
  @override
  TextStyle get titleFont => const TextStyle(fontWeight: FontWeight.w700);

  @override
  TextStyle get bodyFont => const TextStyle();
}

/// Overrides the app theme with [PlainArkThemeTokens].
Override plainThemeOverride() =>
    themeProvider.overrideWith((ref) => ThemeNotifier(PlainArkThemeTokens()));
