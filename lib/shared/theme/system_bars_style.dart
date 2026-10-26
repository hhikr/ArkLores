import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// System icons follow the resolved app theme, including modal routes.
SystemUiOverlayStyle systemBarsStyle({required bool dark}) =>
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
    );
