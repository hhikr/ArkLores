import 'package:arklores/features/ai/investigation_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// R17b: answer markdown split into blocks with their citations taken out
/// (the UI shows each block's evidence chain below it). Fixture paths are
/// fictional.
void main() {
  const a = 'activities/act_x/level_act_x_01_beg.txt';
  const b = 'activities/act_x/level_act_x_02_end.txt';

  test('paragraphs, headings and list items become separate blocks', () {
    final blocks = splitAnswerBlocks(
      '开头一句话。 `$a:3-5`\n'
      '\n'
      '## 一、经过\n'
      '- 第一件事 `$a:10-12`\n'
      '  续行说明。\n'
      '- 第二件事（`$b:0`；`$a:13`）\n'
      '  - 嵌套的细节 `$b:4-6`\n'
      '\n'
      '1. 有序第一\n'
      '2. 有序第二 `record:ab12`\n',
    );
    expect([for (final x in blocks) x.markdown], [
      '开头一句话。',
      '## 一、经过',
      '- 第一件事\n  续行说明。',
      '- 第二件事',
      '- 嵌套的细节',
      '1. 有序第一',
      '2. 有序第二',
    ]);
    expect([for (final x in blocks) x.indent], [0, 0, 0, 0, 1, 0, 0]);

    // Citations stay with their block; adjacent ranges of a story merge.
    final second = blocks[3];
    expect([for (final s in second.stories) s.storyId], [b, a]);
    expect(second.stories.last.ranges.single.start, 13);
    expect(blocks[2].stories.single.ranges.single.end, 12);
    expect(blocks[6].records, ['ab12']);
    expect(blocks[1].hasCitations, isFalse);
  });

  test('framing around removed citations is cleaned up', () {
    String clean(String s) => splitAnswerBlocks(s).single.markdown;
    expect(clean('他离开了〔`$a:1`〕。'), '他离开了。');
    expect(clean('他离开了（出处：`$a:1`、`$a:4-5`）。'), '他离开了。');
    expect(clean('他离开了 `$a:1` ， 然后回来 `$a:9`。'), '他离开了， 然后回来。');
    expect(clean('出处：`$a:1`'), '');
    // Brackets with real words stay.
    expect(clean('他（独自）离开了 `$a:1`'), '他（独自）离开了');
  });

  test('merges overlapping ranges within a block', () {
    final block = splitAnswerBlocks('事件 `$a:10-20` 与 `$a:15-30`，另见 `$a:40`。').single;
    final ranges = block.stories.single.ranges;
    expect([for (final r in ranges) (r.start, r.end)], [(10, 30), (40, 40)]);
  });

  test('tables and code blocks stay whole', () {
    final blocks = splitAnswerBlocks(
      '| 时间 | 事件 |\n'
      '|---|---|\n'
      '| 早 | 出发 `$a:1` |\n'
      '后记\n'
      '\n'
      '```\n'
      'x\n'
      '\n'
      'y\n'
      '```\n',
    );
    expect(blocks, hasLength(3));
    expect(blocks[0].markdown, startsWith('| 时间'));
    expect(blocks[0].markdown.split('\n'), hasLength(3));
    expect(blocks[0].stories.single.storyId, a);
    expect(blocks[1].markdown, '后记');
    expect(blocks[2].markdown, '```\nx\n\ny\n```');
  });
}
