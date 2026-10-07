import 'package:arklores/core/agent/lore_answer_json.dart';
import 'package:arklores/core/agent/lore_answer_stages.dart';
import 'package:arklores/core/agent/story_answer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The citation shapes models write in a JSON answer (placeholders only).
void main() {
  const a = 'x/story_a.txt';
  const b = 'x/story_b.txt';

  group('loreCitationRefs', () {
    test('nested tuples', () {
      expect(
        loreCitationRefs([
          [a, 1, 3],
          ['record', 'r1'],
        ]),
        ['$a:1-3', 'record:r1'],
      );
    });

    test('flat list, one or several in a row', () {
      expect(loreCitationRefs([a, 5, 9]), ['$a:5-9']);
      expect(loreCitationRefs([a, 5, 9, b, 2, 2]), ['$a:5-9', '$b:2']);
      expect(loreCitationRefs([a, 7]), ['$a:7']);
    });

    test('record flat and plain strings', () {
      expect(loreCitationRefs(['record', 'r1']), ['record:r1']);
      expect(loreCitationRefs(['$a:3-5', '$b:1']), ['$a:3-5', '$b:1']);
    });

    test('L prefix, range string, missing .txt, reversed range', () {
      expect(loreCitationRefs([a, 'L12', 'L14']), ['$a:12-14']);
      expect(loreCitationRefs([a, '12-30']), ['$a:12-30']);
      expect(
        loreCitationRefs([
          ['x/story_a', 4, 2],
        ]),
        ['x/story_a.txt:2-4'],
      );
    });

    test('unreadable items are counted', () {
      var dropped = 0;
      final refs = loreCitationRefs(
        [
          {'file': a},
          7,
          a,
        ],
        onDropped: () => dropped++,
      );
      expect(refs, isEmpty);
      expect(dropped, 3);
    });
  });

  group('JSON answer to markdown', () {
    test('flat cites stream like nested ones', () {
      const flat = '{"entries": [{"heading": "H"}, '
          '{"text": "T1", "cite": ["$a", 1, 2]}, '
          '{"text": "T2", "cite": ["$a", 4, 4, "$b", 9, 9]}]}';
      const nested = '{"entries": [{"heading": "H"}, '
          '{"text": "T1", "cite": [["$a", 1, 2]]}, '
          '{"text": "T2", "cite": [["$a", 4, 4], ["$b", 9, 9]]}]}';
      final parsed = loreAnswerParsed(flat)!;
      expect(parsed.markdown, loreAnswerMarkdown(nested));
      expect(parsed.markdown, contains('T1 `$a:1-2`'));
      expect(parsed.markdown, contains('`$a:4` `$b:9`'));
      expect(parsed.dropped, 0);
    });

    test('streaming in small chunks gives the same answer', () {
      const json = '{"entries": [{"text": "T", "cite": ["$a", 1, 2]}]}';
      final stream = LoreAnswerStream();
      for (var i = 0; i < json.length; i += 3) {
        stream.add(json.substring(i, i + 3 > json.length ? json.length : i + 3));
      }
      expect(stream.finish(), 'T `$a:1-2`');
    });

    test('coverage and gaps', () {
      final md = loreAnswerMarkdown(
        '{"entries": [{"text": "T", "cite": [["$a", 1, 1]]}], '
        '"coverage": "full", "gaps": "后半部分"}',
      )!;
      expect(md, contains('[COVERAGE: gaps]'));
    });
  });

  group('staging reads the same shapes', () {
    test('loreAnswerEntries accepts a flat cite', () {
      final entries = loreAnswerEntries(
        '{"entries": [{"text": "T", "cite": ["$a", "L3", "L5"]}]}',
      )!;
      expect(entries.single.cites, ['$a:3-5']);
    });

    test('normalizeAnswerCites rewrites to the nested form', () {
      final out = normalizeAnswerCites(
        '{"entries": [{"text": "T", "cite": ["$a", 1, 2, "record", "r1"]}], '
        '"coverage": "full"}',
      );
      expect(out, contains('"cite":[["$a",1,2],["record","r1"]]'));
      expect(out, contains('"coverage":"full"'));
      expect(normalizeAnswerCites('not json'), 'not json');
    });

    test('from accepts range strings', () {
      final stages = parseLoreStages(
        '{"stages": [{"text": "S", "from": "1-3"}, {"text": "U", "from": [4, "5"]}]}',
        5,
      )!;
      expect(stages[0].from, [1, 2, 3]);
      expect(stages[1].from, [4, 5]);
    });
  });

  test('an unknown fact-check verdict word is uncertain and stripped', () {
    final out = normalizeFactCheckBody(
      '[FACT_CHECK_VERDICT:partially_supported]\n正文',
      nothingRead: false,
      hasValidCitation: true,
    );
    expect(out, startsWith('[FACT_CHECK_VERDICT:uncertain]\n正文'));
  });
}
