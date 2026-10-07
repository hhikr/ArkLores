import 'dart:convert';

import 'package:arklores/core/agent/lore_answer_json.dart';
import 'package:arklores/features/ai/investigation_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// R17c: the JSON final answer and its markdown. Fixture names are fictional.
void main() {
  const a = 'activities/act_x/level_act_x_01_beg.txt';
  final answer = jsonEncode({
    'entries': [
      {
        'text': '星灯是城里的守灯人。',
        'cite': [
          [a, 1, 3],
        ],
      },
      {'heading': '一、经过'},
      {
        'text': '他点亮了钟楼，\n随后离开。',
        'cite': [
          [a, 10, 12],
          ['record', 'ab12'],
        ],
      },
      {
        'text': '他回来时城门已关。',
        'cite': [
          [a, 20, 20],
        ],
      },
    ],
    'coverage': 'gaps',
    'gaps': '后续章节没有读完。',
  });

  test('entries become paragraphs, then list items under headings', () {
    final md = loreAnswerMarkdown('好的。\n$answer')!;
    expect(
      md,
      '星灯是城里的守灯人。 `$a:1-3`\n\n'
      '## 一、经过\n\n'
      '- 他点亮了钟楼， 随后离开。 `$a:10-12` `record:ab12`\n'
      '- 他回来时城门已关。 `$a:20`\n\n'
      '后续章节没有读完。\n\n'
      '[COVERAGE: gaps]',
    );
    // The display puts each entry's chain under it.
    final blocks = splitAnswerBlocks(md);
    expect(blocks[2].markdown, '- 他点亮了钟楼， 随后离开。');
    expect(blocks[2].records, ['ab12']);
  });

  test('streaming chunk by chunk gives the same markdown', () {
    final whole = loreAnswerMarkdown(answer)!;
    for (final size in [1, 3, 7]) {
      final stream = LoreAnswerStream();
      final live = StringBuffer();
      for (var i = 0; i < answer.length; i += size) {
        live.write(stream.add(
          answer.substring(i, i + size > answer.length ? answer.length : i + size),
        ),);
      }
      expect(stream.finish(), whole, reason: 'chunk $size');
      // What streamed is the answer without the closing coverage line.
      expect(whole, startsWith(live.toString().trim()));
    }
  });

  test('the fact-check verdict comes first; escapes are decoded', () {
    final md = loreAnswerMarkdown(
      r'{"entries":[{"text":"他说\"不\"了","cite":["' '$a' r':4"]}],'
      r'"verdict":"refuted","coverage":"full"}',
    )!;
    expect(md, '[FACT_CHECK_VERDICT:refuted]\n\n他说"不"了 `$a:4`\n\n[COVERAGE: full]');
  });

  test('markdown answers are not JSON answers', () {
    expect(loreAnswerMarkdown('星灯点亮钟楼 `$a:1`。'), isNull);
    expect(loreAnswerMarkdown('集合 {1, 2} 不是答案'), isNull);
  });

  test('quoted passages copied from the cited lines are found', () {
    const source = '星灯：我会一直守着这座城，直到最后一盏灯熄灭。\n守卫：钟楼？';
    expect(
      quotedSourceLines(
        '星灯说“我会一直守着这座城”，人称“守灯人”。'
        '他发誓「直到最后一盏灯熄灭为止」。',
        source,
      ),
      ['我会一直守着这座城', '直到最后一盏灯熄灭为止'],
    );
    // Short phrases and text not in the lines are not counted.
    expect(quotedSourceLines('那座“钟楼”和“完全无关的一句话呢”', source), isEmpty);
  });
}
