import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/ark_theme_tokens.dart';
import '../theme/endfield_theme_tokens.dart';

/// Available theme identifiers.
enum AppTheme {
  ark,
  endfield,
}

/// Initial theme read from persisted storage in `main()` and injected here.
///
/// Defaults to [AppTheme.ark] so tests and non-overridden environments keep
/// the historical default; `main()` always overrides it with the saved value.
final initialThemeProvider = Provider<AppTheme>((ref) => AppTheme.ark);

/// Notifier that holds the current [AppThemeTokens] instance and allows
/// switching between [ArkThemeTokens] and [EndfieldThemeTokens].
class ThemeNotifier extends StateNotifier<AppThemeTokens> {
  ThemeNotifier(super.initial);

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
  final initial = ref.watch(initialThemeProvider);
  return ThemeNotifier(
    initial == AppTheme.endfield ? EndfieldThemeTokens() : ArkThemeTokens(),
  );
});
