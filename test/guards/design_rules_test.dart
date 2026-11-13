import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard for the 0.17 look (docs/DESIGN.md): work in progress is a bar of
/// cells, not a spinner; nothing casts a soft shadow or floats on an
/// elevation; nothing is coloured green or red (red is the theme's danger,
/// for deleting only, and green next to it cannot be told apart by many);
/// the stock Material switch, segmented button, bottom sheet and buttons
/// have the app's own versions.
void main() {
  test('lib/ uses no spinner, shadow, elevation, green/red or stock switch',
      () {
    final pattern = RegExp(
      r'CircularProgressIndicator|BoxShadow\(|elevation: [1-9]|'
      r'Colors\.(green|red|amber|orange)\b|\bSwitch\(|SwitchListTile|'
      r'SegmentedButton<|showModalBottomSheet<|'
      // Buttons are `AppButton` (2026-11-13: two knowledge-base cards still
      // drew the stock ones).
      r'\b(Elevated|Outlined|Filled|Text)Button(\.icon)?\(',
    );
    // The app's own versions are built from the stock ones in these files.
    const allowed = {'ef_widgets.dart', 'main.dart'};
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final name = entity.uri.pathSegments.last;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (pattern.hasMatch(lines[i]) && !allowed.contains(name)) {
          hits.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('lib/ writes no text smaller than 12 logical pixels', () {
    // A size given to the theme's text styles too (`theme.text(11)`,
    // `theme.field(size: 11.5)`: 2026-11-13, the reader's line numbers).
    // The decorative script (`eyebrow`) is not read and may be smaller.
    final pattern = RegExp(
      r'(?:fontSize: |\.(?:text|ui|heading|label)\(|'
      r'\.(?:field|label)\([^)]*\bsize: )([0-9]+(?:\.[0-9]+)?)',
    );
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.contains('generated')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in pattern.allMatches(lines[i])) {
          if (double.parse(m.group(1)!) < 12) {
            hits.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
