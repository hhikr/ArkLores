import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supported locales for ArkLores.
///
/// To add a new language, add an entry here and a corresponding .arb file.
enum SupportedLocale {
  en(Locale('en')),
  zh(Locale('zh'));

  const SupportedLocale(this.flutterLocale);

  final Locale flutterLocale;

  String get displayName {
    switch (this) {
      case SupportedLocale.en:
        return 'English';
      case SupportedLocale.zh:
        return '中文';
    }
  }
}

/// Initial locale read from persisted storage in `main()` and injected here.
///
/// Defaults to [SupportedLocale.zh] so tests and non-overridden environments
/// keep the historical default; `main()` always overrides it with the saved
/// value.
final initialLocaleProvider =
    Provider<SupportedLocale>((ref) => SupportedLocale.zh);

/// Notifier that holds the current locale and persists the preference.
class LocaleNotifier extends StateNotifier<SupportedLocale> {
  LocaleNotifier(super.initial);

  void switchTo(SupportedLocale locale) {
    state = locale;
  }
}

/// Provider for locale state.
final localeProvider = StateNotifierProvider<LocaleNotifier, SupportedLocale>(
  (ref) => LocaleNotifier(ref.watch(initialLocaleProvider)),
);
