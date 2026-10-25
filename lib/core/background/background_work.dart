import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps the app's long operations (an Ask answer, a knowledge-base
/// download, build or vector update) running while the app is in the
/// background.
///
/// On Android the process of a backgrounded app is frozen, and its sockets
/// are cut, a short while after the user leaves. While at least one
/// operation is registered here, a foreground service (with its ongoing
/// notification and a wake lock) keeps the process alive. Elsewhere, and in
/// tests, nothing happens.
class BackgroundWork {
  BackgroundWork({MethodChannel? channel, bool? enabled})
      : _channel = channel ?? const MethodChannel(channelName),
        _enabled = enabled ?? Platform.isAndroid;

  static const channelName = 'arklores/background_work';

  /// The app-wide instance.
  static final BackgroundWork instance = BackgroundWork();

  final MethodChannel _channel;
  final bool _enabled;
  final Map<String, String> _active = {};
  int _seq = 0;

  /// Keys of the operations running now (for tests).
  Iterable<String> get activeKeys => _active.keys;

  /// Runs [action] as a background-protected operation described by [label]
  /// (shown in the notification).
  Future<T> run<T>(String label, Future<T> Function() action) async {
    final key = '${_seq++}:$label';
    await _begin(key, label);
    try {
      return await action();
    } finally {
      await _end(key);
    }
  }

  Future<void> _begin(String key, String label) async {
    _active[key] = label;
    if (!_enabled) return;
    await _invoke('begin', {'title': 'ArkLores', 'text': _text()});
  }

  Future<void> _end(String key) async {
    _active.remove(key);
    if (!_enabled) return;
    await _invoke(_active.isEmpty ? 'end' : 'begin',
        {'title': 'ArkLores', 'text': _text()},);
  }

  String _text() => _active.values.toSet().join(' · ');

  Future<void> _invoke(String method, Map<String, String> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException {
      // No service (refused start, no notification permission, ...): the
      // operation still runs, only without the protection.
    } on MissingPluginException {
      // Not the Android shell.
    }
  }

  /// Whether the system lets the app work in the background: null where
  /// there is nothing to ask (not Android, or no answer from the shell).
  Future<BackgroundAccess?> access() async {
    if (!_enabled) return null;
    try {
      final map = await _channel.invokeMapMethod<String, bool>('access');
      if (map == null) return null;
      return BackgroundAccess(
        notifications: map['notifications'] ?? false,
        batteryExempt: map['batteryExempt'] ?? false,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Asks for notifications (the system's dialog, or the app's
  /// notification settings once that was asked). The answer comes back
  /// with [access] when the app is resumed.
  Future<void> requestNotifications() => _invoke('requestNotifications', {});

  /// Asks to be exempt from battery optimisation (the system's dialog).
  Future<void> requestBatteryExempt() => _invoke('requestBatteryExempt', {});

  /// Notification text for [zh] / [en] by the device language.
  static String text(String zh, String en) =>
      PlatformDispatcher.instance.locale.languageCode == 'zh' ? zh : en;
}

/// What the system allows the app while it is in the background. Some
/// systems (ColorOS) freeze an app that is not exempt from battery
/// optimisation within seconds of leaving it, foreground service or not,
/// and its connections drop (traced 2026-10-25).
class BackgroundAccess {
  const BackgroundAccess({
    required this.notifications,
    required this.batteryExempt,
  });

  /// The foreground service's notification can be shown.
  final bool notifications;

  /// Exempt from battery optimisation: not frozen in the background.
  final bool batteryExempt;
}

/// The app's [BackgroundWork]; tests put in one with a fake channel.
final backgroundWorkProvider =
    Provider<BackgroundWork>((ref) => BackgroundWork.instance);
