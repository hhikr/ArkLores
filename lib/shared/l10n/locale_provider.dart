import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supported locales for ArkLores.
///
/// To add a new language, add an entry here and a corresponding .arb file.
enum SupportedLocale {
  en(Locale('en')),
  zh(Locale('zh'));

  final Locale flutterLocale;
  const SupportedLocale(this.flutterLocale);

  String get displayName {
    switch (this) {
      case SupportedLocale.en:
        return 'English';
      case SupportedLocale.zh:
        return '中文';
    }
  }
}

/// Notifier that holds the current locale and persists the preference.
class LocaleNotifier extends StateNotifier<SupportedLocale> {
  LocaleNotifier() : super(SupportedLocale.zh);

  void switchTo(SupportedLocale locale) {
    state = locale;
  }
}

/// Provider for locale state.
final localeProvider = StateNotifierProvider<LocaleNotifier, SupportedLocale>(
  (ref) => LocaleNotifier(),
);
