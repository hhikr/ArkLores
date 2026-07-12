import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/ark_theme_tokens.dart';
import '../theme/endfield_theme_tokens.dart';

/// Available theme identifiers.
enum AppTheme {
  ark,
  endfield,
}

/// Notifier that holds the current [AppThemeTokens] instance and allows
/// switching between [ArkThemeTokens] and [EndfieldThemeTokens].
class ThemeNotifier extends StateNotifier<AppThemeTokens> {
  ThemeNotifier() : super(ArkThemeTokens());

  void switchTo(AppTheme theme) {
    switch (theme) {
      case AppTheme.ark:
        state = ArkThemeTokens();
      case AppTheme.endfield:
        state = EndfieldThemeTokens();
    }
  }

  void toggle() {
    if (state is ArkThemeTokens) {
      switchTo(AppTheme.endfield);
    } else {
      switchTo(AppTheme.ark);
    }
  }

  /// Returns the current theme enum value without changing state.
  AppTheme get currentTheme =>
      state is ArkThemeTokens ? AppTheme.ark : AppTheme.endfield;
}

/// Global theme provider — all UI components read tokens via [ref.watch].
final themeProvider =
    StateNotifierProvider<ThemeNotifier, AppThemeTokens>((ref) {
  return ThemeNotifier();
});
