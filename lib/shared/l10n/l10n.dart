export 'generated/app_localizations.dart' show AppLocalizations;
export 'locale_provider.dart' show SupportedLocale, localeProvider;

import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

/// Convenience extension to shorten `AppLocalizations.of(context)!` to `context.t`.
extension L10n on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this)!;
}
