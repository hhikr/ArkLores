import 'package:arklores/core/agent/story_answer.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/features/ai/investigation_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a story answer: its markers, its citations (made readable,
/// grouped, split per block). Fixture paths are fictional.
void main() {
  const a = 'activities/act_x/level_act_x_01_beg.txt';
  const b = 'activities/act_x/level_act_x_02_end.txt';

  group('markers', () {
    test('markers are stripped', () {
      final content =
          '${formatStoryAnswerEnvelope(StoryAnswerStatus.answered, confidence: '0.8')}\n'
          '证据：activities/act_fixture/level_fixture_c5.txt:0 与 '
          'activities/act_fixture/level_fixture_c1.txt:2。\n\n'
          'Coverage: read=1 | mapped=1 | skipped=0';
      expect(isStoryAnswer(content), isTrue);
      final stripped = stripStoryAnswerMarkers(content);
      expect(stripped, isNot(contains('STORY_ANSWER')));
      expect(stripped, isNot(contains('Coverage: read=')));
      expect(stripped, contains('证据'));

      const legacy = '[INVESTIGATION_VERDICT: culprit=x | confidence=0.5 | '
          'basis=b]\n正文';
      expect(isStoryAnswer(legacy), isTrue);
      expect(stripStoryAnswerMarkers(legacy), '正文');
    });

    test('the coverage line of old sessions still parses', () {
      final line =
          parseCoverageReportLine('Coverage: read=2 | mapped=1 | skipped=0')!;
      expect(line.read, '2');
      expect(line.mapped, '1');
      expect(line.skipped, '0');
    });
  });

  group('citations', () {
    test('cited story and record ids, in order of first citation', () {
      const id = 'activities/act_fx/level_act_fx_02_beg.txt';
      expect(extractCitedStoryIds('`$id:1` b/c.txt:2-5'), {id, 'b/c.txt'});
      expect(
        extractCitedRecordIds('甲 `record:aa1`，乙 `record:bb2`，再提甲 `record:aa1`。'),
        ['aa1', 'bb2'],
      );
    });

    test('grouped: collection → chapter → merged line ranges', () {
      const a1 = 'activities/act_x/level_x_01.txt';
      const a2 = 'activities/act_x/level_x_02.txt';
      const main = 'obt/main/level_main_01.txt';
      StoryCatalogEntry chapter(String id, int sort, String code, String tag) =>
          StoryCatalogEntry(
            storyId: id,
            collectionId: 'act_x',
            collectionName: '甲活动',
            collectionType: 'ACTIVITY',
            storySort: sort,
            storyCode: code,
            avgTag: tag,
          );
      final groups = groupCitations(
        '见 $a2:5、$a1:3-4、$a1:5 与 `$main:0`；又见 $a1:9。',
        {a1: chapter(a1, 1, 'X-1', '行动前'), a2: chapter(a2, 2, 'X-2', '行动后')},
      );
      expect(groups.map((g) => g.label), ['甲活动', '主线']);
      final x = groups.first;
      expect(x.chapters.map((c) => c.label), ['X-1 行动前', 'X-2 行动后']);
      // 3-4 and 5 are adjacent: one range; 9 stays separate.
      expect(x.chapters.first.ranges.map((r) => r.rawRef(a1)),
          ['$a1:3-5', '$a1:9'],);
      expect(x.citationCount, 3);
      expect(groups.last.chapters.single.label, 'level_main_01');
      expect(citedRangeText(x.chapters.first.ranges.first, (s, e) => '$s-$e'),
          '4-6',);
    });
  });

  // R17b: the answer is split into blocks with their citations taken out;
  // the UI shows each block's sources below it.

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
