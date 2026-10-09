import 'dart:convert';

import 'package:arklores/core/agent/lore_answer_stages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = 'activities/act_x/level_act_x_01_beg.txt';
  const b = 'obt/main/level_main_x-01.txt';

  final detail = jsonEncode({
    'entries': [
      {
        'text': '甲到了城门。',
        'cite': [
          [a, 1, 2],
        ],
      },
      {'heading': '后来'},
      {
        'text': '甲见了乙。',
        'cite': [
          [a, 3, 3],
          ['record', 'r1'],
        ],
      },
      {
        'text': '乙离开了。',
        'cite': [
          [b, 10, 12],
        ],
      },
      {
        'text': '甲回到城里。',
        'cite': ['$b:20-21'],
      },
    ],
    'coverage': 'full',
  });

  test('entries keep text, headings and citation refs', () {
    final entries = loreAnswerEntries('前言 $detail 尾巴')!;
    expect(entries.where((e) => e.isText), hasLength(4));
    expect(entries[1].heading, '后来');
    expect(entries[2].cites, ['$a:3', 'record:r1']);
    expect(entries[4].cites, ['$b:20-21']);
    expect(numberedEntries(entries), '1. 甲到了城门。\n【后来】\n2. 甲见了乙。\n'
        '3. 乙离开了。\n4. 甲回到城里。');
    expect(loreAnswerEntries('没有 JSON'), isNull);
    expect(loreAnswerEntries('{"entries": [ 坏的'), isNull);
  });

  test('citations of one story merge when they overlap or touch', () {
    expect(
      mergeCitationRefs([
        '$a:3', 'record:r1', '$a:1-2', '$b:20', '$a:5-6', '$a:3', '$b:18-19',
      ]),
      ['$a:1-3', '$a:5-6', '$b:18-20', 'record:r1'],
    );
  });

  test('stages keep only valid entry numbers', () {
    final stages = parseLoreStages(
      jsonEncode({
        'stages': [
          {'heading': '开始', 'text': '甲来了又见了乙。', 'from': [1, 2, 9]},
          {'text': '没有条目的段落。', 'from': [0, 7]},
          {'text': '乙离开。', 'from': ['3']},
        ],
      }),
      4,
    )!;
    expect(stages, hasLength(2));
    expect(stages[0].from, [1, 2]);
    expect(stages[1].heading, isNull);
    expect(stages[1].from, [3]);
    expect(parseLoreStages('{"stages": []}', 4), isNull);
    expect(parseLoreStages('不是 JSON', 4), isNull);
  });

  // 0.14 live (a weaker model): thinking first, a first version, prose, then
  // the version meant; the whole text up to its last brace is not JSON.
  test('a reply with thinking, prose and two versions gives the last one', () {
    final stages = parseLoreStages(
      'Thinking about it.\n```json\n{"stages": [{"text": "first", "from": [1]}]}\n```\n'
      'Some prose (1, 2) with {braces}.\n'
      '{"stages": [{"heading": "开始", "text": "甲来了。", "from": [1, 2]}]}\n'
      'trailing {"stages": [{"text": "cut',
      4,
    )!;
    expect(stages.single.text, '甲来了。');
    expect(stages.single.from, [1, 2]);
  });

  test('every citation of the detailed answer lands in some paragraph', () {
    final entries = loreAnswerEntries(detail)!;
    final markdown = stagedAnswerMarkdown(
      const [
        LoreAnswerStage(heading: '开始', text: '甲来了又见了乙。', from: [1, 2]),
        LoreAnswerStage(text: '乙离开。', from: [3]),
      ],
      entries,
    );
    // Entry 4 is in no paragraph: its citation goes to the paragraph of
    // the nearest earlier entry (3).
    expect(
      markdown,
      '## 开始\n\n甲来了又见了乙。 `$a:1-3` `record:r1`\n\n'
      '乙离开。 `$b:10-12` `$b:20-21`',
    );
  });

  test('review replies and answers without citations', () {
    expect(parseReviewIssues('{"ok": true}'), isEmpty);
    expect(parseReviewIssues('好的：{"issues": ["问题一", " ", "问题二"]}'),
        ['问题一', '问题二'],);
    expect(parseReviewIssues('无法解析'), isEmpty);
    expect(
      parseReviewIssues(jsonEncode({
        'issues': [for (var i = 0; i < 8; i++) 'q$i'],
      }),),
      hasLength(3),
    );
    expect(
      withoutCitations('甲到了城门。 `$a:1-2`\n\n- 乙 `record:r1` `$b:3`'),
      '甲到了城门。\n\n- 乙',
    );
  });
}
