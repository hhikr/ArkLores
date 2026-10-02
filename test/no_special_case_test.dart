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

  // Anti-fixture rule (CLAUDE.md): names from the live acceptance questions
  // may appear in comments only — never in code, prompts or ARB text, where
  // they would steer the model toward those questions.
  test('acceptance-case names appear in lib/ comments only', () {
    const caseNames = [
      '特蕾西娅', '特雷西斯', '特雷西亚', '巴别塔', '米格鲁', '谬因', '缪因',
      '洛伦茨', '艾丽妮', '审判官', '生路', '愚人号', '丛林症结',
      'act33side', 'act21mini', 'act17side', 'act34side',
      'enemy_1554', 'enemy_3006', 'trap_762', 'char_4229', 'char_4009',
    ];
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.dart') && !path.endsWith('.arb')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('//')) continue;
        // A trailing comment after code is still a comment.
        final code = line.contains(' // ')
            ? line.substring(0, line.indexOf(' // '))
            : line;
        for (final name in caseNames) {
          if (code.contains(name)) {
            hits.add('$path:${i + 1}: $line');
            break;
          }
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
