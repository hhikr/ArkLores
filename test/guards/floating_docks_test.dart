import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard for the floating docks (2026-10): every page's top bar is a
/// floating pill (`FloatingScaffold` / `FloatingTopBar`), so a plain
/// Material `AppBar` anywhere under lib/ is a page that was missed.
void main() {
  test('lib/ builds no AppBar', () {
    final pattern = RegExp(r'\b(Sliver)?AppBar\(');
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//')) continue;
        if (pattern.hasMatch(line)) {
          hits.add('${entity.path}:${i + 1}: $line');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
