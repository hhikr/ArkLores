import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';

/// Keeps the app's long operations (an Ask answer, a role-play reply, a
/// knowledge-base download or build) running while the app is in the
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

  /// Notification text for [zh] / [en] by the device language.
  static String text(String zh, String en) =>
      PlatformDispatcher.instance.locale.languageCode == 'zh' ? zh : en;
}
