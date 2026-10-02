import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard for the "no special cases" rule (CLAUDE.md, R13): product code
/// must not branch on, threshold on, prompt for or output fields about one
/// kind of question or story beat. These words only ever appeared in such
/// special cases (culprit envelopes, "at least two suspects" gates), so any
/// occurrence under lib/ fails the build.
void main() {
  test('lib/ contains no question-type special-case vocabulary', () {
    final pattern = RegExp('culprit|suspect|嫌疑|凶手|罪魁', caseSensitive: false);
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart') && !entity.path.endsWith('.arb')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) {
          hits.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
