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

  test('citation-first entries render like text-first entries in every chunk size', () {
    for (final flat in [false, true]) {
      String ordered(bool citeFirst) => jsonEncode({
        'entries': [
          for (final entry in [
            {'text': '星灯是城里的守灯人。', 'cite': flat ? [a, 1, 3] : [[a, 1, 3]]},
            {'heading': '经过'},
            {'text': '他点亮钟楼。', 'cite': flat ? ['record', 'ab12'] : [['record', 'ab12']]},
          ])
            if (citeFirst && entry.containsKey('text'))
              {'cite': entry['cite'], 'text': entry['text']}
            else
              entry,
        ],
        'coverage': 'full',
      });
      final textFirst = ordered(false);
      final citeFirst = ordered(true);
      final expected = loreAnswerMarkdown(textFirst)!;
      expect(loreAnswerMarkdown(citeFirst), expected, reason: 'flat=$flat');
      for (final size in [1, 3, 7, citeFirst.length]) {
        final stream = LoreAnswerStream();
        final live = StringBuffer();
        for (var i = 0; i < citeFirst.length; i += size) {
          final end = (i + size).clamp(0, citeFirst.length);
          live.write(stream.add(citeFirst.substring(i, end)));
        }
        expect(stream.finish(), expected, reason: 'flat=$flat, chunk=$size');
        expect(expected, startsWith(live.toString().trim()));
        expect(stream.droppedCites, 0);
      }
    }
  });

  test('text streams immediately and early citations wait until its end', () {
    final textFirst = LoreAnswerStream();
    expect(textFirst.add('{"entries":[{"text":"星灯'), '星灯');
    expect(textFirst.add('点亮钟楼。","cite":['), '点亮钟楼。');
    expect(textFirst.add('["$a",1,3]'), ' `$a:1-3`');
    textFirst.add(']}]}');

    final citeFirst = LoreAnswerStream();
    expect(citeFirst.add('{"entries":[{"cite":[["$a",1,3]],'), isEmpty);
    expect(citeFirst.add('"text":"星灯'), '星灯');
    expect(citeFirst.add('点亮钟楼。'), '点亮钟楼。');
    expect(citeFirst.add('"}]}'), ' `$a:1-3`');
    expect(citeFirst.finish(), textFirst.finish());
  });

  test('the fact-check verdict comes first; escapes are decoded', () {
    final md = loreAnswerMarkdown(
      r'{"entries":[{"text":"他说\"不\"了","cite":["' '$a' r':4"]}],'
      r'"verdict":"refuted","coverage":"full"}',
    )!;
    expect(md, '[FACT_CHECK_VERDICT:refuted]\n\n他说"不"了 `$a:4`\n\n[COVERAGE: full]');
  });

  // 0.14 live: one reply of a weaker model held prose quoting the format's
  // skeleton, a partial version in a code block, and then the whole answer.
  test('of several JSON answers in one reply the last complete one is read',
      () {
    final whole = jsonEncode({
      'entries': [
        {
          'text': '甲做了第一件事。',
          'cite': [
            ['a/b.txt', 1, 2],
          ],
        },
        {'heading': '后来'},
        {
          'text': '甲做了第二件事。',
          'cite': [
            ['record', 'r1'],
          ],
        },
      ],
      'coverage': 'full',
    });
    final reply = 'The required format is {"entries": [条目, ...], '
        '"coverage": "full 或 gaps"}. I must follow it.\n\n'
        '```json\n{"entries": [{"text": "只有一条。", "cite": [["a/b.txt", 1, 1]]}], '
        '"coverage": "full"}\n```\n\nMore notes in English.\n\n$whole';
    final md = loreAnswerMarkdown(reply)!;
    expect(md, contains('甲做了第一件事。'));
    expect(md, contains('甲做了第二件事。'));
    expect(md, isNot(contains('只有一条')));
    expect(md, isNot(contains('full 或 gaps')));
    // One answer as before: the same markdown.
    expect(loreAnswerMarkdown(whole), md);
  });

  // 0.14 phone: a bracket too many closed the object after its first entry
  // (`…}]},{"heading":…},…],"coverage":"full"}`); twelve entries were lost
  // and the one sentence left was shown as the answer.
  test('entries after an early closing bracket are read on', () {
    final whole = jsonEncode({
      'entries': [
        {
          'text': '甲做了第一件事。',
          'cite': [
            ['a/b.txt', 1, 2],
          ],
        },
        {'heading': '后来'},
        {
          'text': '甲做了第二件事。',
          'cite': [
            ['record', 'r1'],
          ],
        },
      ],
      'coverage': 'gaps',
      'gaps': '后面没有读完。',
    });
    final first = whole.indexOf('},{') + 1;
    final broken = '${whole.substring(0, first)}]}${whole.substring(first)}';
    expect(() => jsonDecode(broken), throwsFormatException);

    final parsed = loreAnswerParsed(broken)!;
    expect(parsed.markdown, loreAnswerMarkdown(whole));
    expect(parsed.cutShort, isFalse);
    expect(parsed.repaired, whole);
    expect(loreAnswerParsed(whole)!.repaired, isNull);

    // Chunk by chunk (the streamed answer) reads on the same way.
    final stream = LoreAnswerStream();
    for (var i = 0; i < broken.length; i += 5) {
      stream.add(broken.substring(i, (i + 5).clamp(0, broken.length)));
    }
    expect(stream.finish(), parsed.markdown);
  });

  test('entries that cannot be read on are reported, not dropped silently',
      () {
    const reply = '{"entries": [{"text": "甲做了第一件事。", '
        '"cite": [["a/b.txt", 1, 2]]}], "coverage": "full"}\n'
        '{"text": "甲做了第二件事。", "cite": [["a/b.txt", 3, 4]]}';
    final parsed = loreAnswerParsed(reply)!;
    expect(parsed.markdown, isNot(contains('第二件事')));
    expect(parsed.cutShort, isTrue);
    // Words after the answer are not entries.
    expect(
      loreAnswerParsed('{"entries": [{"text": "甲。", "cite": '
              '[["a/b.txt", 1, 2]]}]}\n以上就是答案。')!
          .cutShort,
      isFalse,
    );
  });

  test('quotes written without a backslash stay in the text', () {
    // 0.14 live: every quotation in the answer in plain quotes; each entry
    // was cut at its first one and the rest of its text lost.
    const reply = '{"entries":[{"text":"甲说"先走",乙说"再等等"，于是分开。",'
        '"cite":[["a/b.txt",1,2]]},'
        '{"heading":"所谓"约定""},'
        '{"text":"He said "go", then left." , "cite":[["a/b.txt",3,4]]}],'
        '"coverage":"gaps","gaps":"“约定”的"内容"没有读到。"}';
    final parsed = loreAnswerParsed(reply)!;
    expect(
      parsed.markdown,
      '甲说"先走",乙说"再等等"，于是分开。 `a/b.txt:1-2`\n\n'
      '## 所谓"约定"\n\n'
      '- He said "go", then left. `a/b.txt:3-4`\n\n'
      '“约定”的"内容"没有读到。\n\n'
      '[COVERAGE: gaps]',
    );
    expect(parsed.cutShort, isFalse);
    // What reads the answer as a whole gets valid JSON.
    final decoded = jsonDecode(parsed.repaired!) as Map<String, dynamic>;
    final entries = (decoded['entries'] as List).cast<Map<String, dynamic>>();
    expect(entries, hasLength(3));
    expect(entries.first['text'], '甲说"先走",乙说"再等等"，于是分开。');
    // The same text chunk by chunk.
    final stream = LoreAnswerStream();
    for (var i = 0; i < reply.length; i += 3) {
      stream.add(reply.substring(i, (i + 3).clamp(0, reply.length)));
    }
    expect(stream.finish(), parsed.markdown);
    // A well-formed answer is not touched.
    expect(loreAnswerParsed(answer)!.repaired, isNull);
  });

  test('markdown answers are not JSON answers', () {
    expect(loreAnswerMarkdown('星灯点亮钟楼 `$a:1`。'), isNull);
    expect(loreAnswerMarkdown('集合 {1, 2} 不是答案'), isNull);
  });
}
