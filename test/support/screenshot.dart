import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a widget so [shoot] can capture it.
class Shot extends StatelessWidget {
  const Shot({super.key, required this.child});

  static final GlobalKey boundaryKey = GlobalKey();

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: boundaryKey, child: child);
}

/// Where screenshots go: the `ARKLORES_SHOT_DIR` environment variable;
/// without it [shoot] does nothing.
String? get shotDir => Platform.environment['ARKLORES_SHOT_DIR'];

/// Saves the [Shot] on screen as `<dir>/<name>.png`. Text is drawn with the
/// test font (boxes), so these check layout, not typography.
Future<void> shoot(WidgetTester tester, String name) async {
  final dir = shotDir;
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = Shot.boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
    // Real time passed: the theme's font downloads (refused in tests) fail
    // now. They are noise here, not test failures.
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  while (tester.takeException() != null) {}
}
