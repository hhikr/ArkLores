import 'package:arklores/core/agent/loop_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('read index merges paged reads of the same story', () {
    final memory = LoopMemory()
      ..noteRead('activities/x/level_x_09_beg.txt', 0, 100)
      ..noteRead('activities/x/level_x_09_beg.txt', 100, 200)
      ..noteRead('activities/x/level_x_10_end.txt', 0, 50);
    final block = memory.buildBlock();
    expect(block, contains('activities/x/level_x_09_beg.txt:0-200'));
    expect(block, contains('activities/x/level_x_10_end.txt:0-50'));
  });

  test('tracks mapped scopes and collected evidence', () {
    final memory = LoopMemory()
      ..noteMapped('activity:act33side')
      ..noteMapped('obt:main')
      ..noteEvidence('enemy:enemy_1276_telex');
    final block = memory.buildBlock();
    expect(block, contains('已查地图: activity:act33side, obt:main'));
    expect(block, contains('已收集证据: enemy:enemy_1276_telex'));
  });

  test('thought notes are cut to a guardrail length', () {
    final memory = LoopMemory()..noteThought(3, '关键结论：${'很长的内容' * 100}');
    final block = memory.buildBlock();
    expect(block, contains('[3]'));
    expect(block, contains('关键结论'));
    expect(block.length, lessThan(400));
  });

  test('empty memory renders an empty block', () {
    expect(LoopMemory().buildBlock(), isEmpty);
  });
}
