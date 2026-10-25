import 'dart:async';
import 'dart:ui' show Brightness, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/ark_theme_tokens.dart';
import '../theme/endfield_theme_tokens.dart';
import '../theme/system_night_mode.dart';

/// The theme choice the user saved: dark ([ark]), light ([endfield]), or
/// whichever the system is in ([system]).
enum AppTheme {
  ark,
  endfield,
  system,
}

/// The font of long reading text (stories, profiles, answers).
enum ReadingFont {
  /// Noto Sans SC (思源黑体, bundled), the Chinese of the interface.
  sans('NotoSansSC'),

  /// LXGW WenKai Screen (bundled).
  kai('LXGWWenKaiScreen');

  const ReadingFont(this.family);

  final String? family;
}

/// Initial theme read from persisted storage in `main()` and injected here.
///
/// Defaults to [AppTheme.ark] so tests and non-overridden environments keep
/// the historical default; `main()` always overrides it with the saved value.
final initialThemeProvider = Provider<AppTheme>((ref) => AppTheme.ark);

/// The reading font read in `main()`.
final initialReadingFontProvider =
    Provider<ReadingFont>((ref) => ReadingFont.sans);

/// Holds the current [AppThemeTokens]: the saved choice, resolved against
/// the system's brightness when the choice is [AppTheme.system] (and again
/// whenever the system switches), with the chosen reading font.
class ThemeNotifier extends StateNotifier<AppThemeTokens> {
  ThemeNotifier(
    super.initial, {
    AppTheme choice = AppTheme.ark,
    ReadingFont font = ReadingFont.sans,
  })  : _choice = choice,
        _font = font;

  /// A notifier for [choice] and [font], resolved now.
  factory ThemeNotifier.of(
    AppTheme choice, {
    ReadingFont font = ReadingFont.sans,
  }) {
    final notifier =
        ThemeNotifier(_resolve(choice, font), choice: choice, font: font);
    if (choice == AppTheme.system) notifier._follow();
    return notifier;
  }

  AppTheme _choice;
  ReadingFont _font;
  bool _following = false;

  static AppThemeTokens _resolve(AppTheme choice, ReadingFont font) {
    final dark = switch (choice) {
      AppTheme.ark => true,
      AppTheme.endfield => false,
      AppTheme.system =>
        PlatformDispatcher.instance.platformBrightness == Brightness.dark,
    };
    return dark
        ? ArkThemeTokens(readingFontFamily: font.family)
        : EndfieldThemeTokens(readingFontFamily: font.family);
  }

  void _follow() {
    if (_following) return;
    _following = true;
    final dispatcher = PlatformDispatcher.instance;
    final previous = dispatcher.onPlatformBrightnessChanged;
    dispatcher.onPlatformBrightnessChanged = () {
      previous?.call();
      if (mounted && _choice == AppTheme.system) {
        final next = _resolve(AppTheme.system, _font);
        if (next.isDark != state.isDark) state = next;
      }
    };
  }

  void switchTo(AppTheme theme) {
    _choice = theme;
    // The next start's splash in the same light or dark.
    unawaited(syncSystemNightMode(theme));
    if (theme == AppTheme.system) _follow();
    state = _resolve(theme, _font);
  }

  void toggle() {
    switchTo(state.isDark ? AppTheme.endfield : AppTheme.ark);
  }

  void setReadingFont(ReadingFont font) {
    _font = font;
    state = _resolve(_choice, font);
  }

  /// The saved choice (which may be [AppTheme.system]).
  AppTheme get currentTheme => _choice;

  ReadingFont get readingFont => _font;
}

/// Global theme provider — all UI components read tokens via [ref.watch].
final themeProvider =
    StateNotifierProvider<ThemeNotifier, AppThemeTokens>((ref) {
  return ThemeNotifier.of(
    ref.watch(initialThemeProvider),
    font: ref.watch(initialReadingFontProvider),
  );
});
