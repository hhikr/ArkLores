import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'settings_service.dart';

class AppIconService {
  AppIconService._();

  static const _channel = MethodChannel('arklores/app_icon');

  static Future<bool> setIcon(AppLauncherIcon icon) async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'setIcon',
            {'icon': icon.storageValue},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
