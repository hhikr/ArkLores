import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../providers/theme_provider.dart';

const _channel = MethodChannel('arklores/app_theme');

/// Tells the system the app's own light or dark: Android 12+ then starts
/// the app in it, so its splash is the app's paper (a dark app opened on a
/// light system flashed white). [AppTheme.system] hands it back to the
/// system. Nothing elsewhere.
Future<void> syncSystemNightMode(AppTheme choice) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod<bool>('setNightMode', {
      'mode': switch (choice) {
        AppTheme.ark => 'yes',
        AppTheme.endfield => 'no',
        AppTheme.system => 'auto',
      },
    });
  } on MissingPluginException {
    // Not on a device (tests).
  } on PlatformException {
    // Left as it was; only the splash's colour depends on it.
  }
}
