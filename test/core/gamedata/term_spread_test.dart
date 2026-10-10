import 'dart:io';

import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/core/gamedata/story_line_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

/// 0.14: where a word's lines are, by collection. Every word gets the same
/// form; the names are made up.
void main() {
  group('computeTermSpread', () {
    /// One story file per collection: `id` → (the word's lines, all lines).
    (Map<String, int>, StoryGroups) corpus(
      Map<String, (int, int)> collections, {
      int? corpusLines,
    }) =>
        (
          {for (final e in collections.entries) '${e.key}/1.txt': e.value.$1},
          StoryGroups(
            groupOf: {for (final id in collections.keys) '$id/1.txt': id},
            labels: {for (final id in collections.keys) id: '《$id》'},
            groupLines: {
              for (final e in collections.entries) e.key: e.value.$2,
            },
            corpusLines: corpusLines ??
                collections.values.fold<int>(0, (n, c) => n + c.$2),
          ),
        );

    test('lists until four fifths of the lines are covered', () {
      final (perStory, groups) = corpus({
        'a': (80, 1000),
        'b': (12, 1000),
        'c': (8, 1000),
      });
      final spread = computeTermSpread(perStory, groups);
      expect(spread.lines, 100);
      expect(spread.collections, 3);
      expect(spread.chapters, 3);
      expect(spread.listed.map((p) => p.id), ['a']);
      expect(spread.dense, isEmpty);
      expect(spread.restCount, 2);
      expect(spread.restShare, closeTo(0.20, 1e-9));
      expect(
        formatTermSpread(spread),
        '100 行，3 个故事集：《a》 80 行 / 1 章；另 2 个共 20%',
      );
    });

    test('or until six are listed', () {
      final (perStory, groups) = corpus({
        for (var i = 0; i < 10; i++) 'c$i': (20 - i, 1000),
      });
      final spread = computeTermSpread(perStory, groups);
      expect(spread.listed.map((p) => p.id), ['c0', 'c1', 'c2', 'c3', 'c4', 'c5']);
      expect(spread.restCount, 4);
      // 14 + 13 + 12 + 11 of 155.
      expect(spread.restShare, closeTo(50 / 155, 1e-9));
    });

    test('one collection: nothing else to say', () {
      final (perStory, groups) = corpus({'a': (30, 200)});
      final spread = computeTermSpread(perStory, groups);
      expect(spread.restCount, 0);
      expect(formatTermSpread(spread), '30 行，1 个故事集：《a》 30 行 / 1 章');
    });

    test('several chapters of one collection count as one', () {
      final spread = computeTermSpread(
        {'x/1.txt': 5, 'x/2.txt': 7, 'y/1.txt': 0},
        const StoryGroups(
          groupOf: {'x/1.txt': 'x', 'x/2.txt': 'x', 'y/1.txt': 'y'},
          labels: {'x': '甲集', 'y': '乙集'},
          groupLines: {'x': 100, 'y': 100},
          corpusLines: 200,
        ),
      );
      expect(formatTermSpread(spread), '12 行，1 个故事集：甲集 12 行 / 2 章');
    });

    group('a short collection the word fills', () {
      // Six large collections take the six places.
      Map<String, (int, int)> large() =>
          {for (var i = 0; i < 6; i++) 'big$i': (100 - i, 5000)};

      test('is added when it has the lines, the share and the lift', () {
        final (perStory, groups) = corpus(
          {...large(), 'small': (12, 100), 'other': (40, 5000)},
          corpusLines: 100000,
        );
        final spread = computeTermSpread(perStory, groups);
        expect(spread.dense.map((p) => p.id), ['small']);
        expect(spread.dense.single.share, closeTo(0.12, 1e-9));
        expect(spread.restCount, 1);
        expect(
          formatTermSpread(spread),
          contains('；占比高的：《small》 12 行（占该篇 12%）；另 1 个共 '),
        );
      });

      test('not with fewer than ten lines', () {
        final (perStory, groups) = corpus(
          {...large(), 'small': (9, 50)},
          corpusLines: 100000,
        );
        expect(computeTermSpread(perStory, groups).dense, isEmpty);
      });

      test('not in less than a tenth of its lines', () {
        final (perStory, groups) = corpus(
          {...large(), 'small': (12, 130)},
          corpusLines: 100000,
        );
        expect(computeTermSpread(perStory, groups).dense, isEmpty);
      });

      test('not when the word is as common everywhere', () {
        // 597 + 12 lines of 12000: 5% of the corpus; 12% is not 5 times it.
        final (perStory, groups) = corpus(
          {...large(), 'small': (12, 100)},
          corpusLines: 12000,
        );
        expect(computeTermSpread(perStory, groups).dense, isEmpty);
      });

      test('at most two, the fullest first', () {
        final (perStory, groups) = corpus(
          {
            ...large(),
            's1': (20, 100),
            's2': (30, 100),
            's3': (25, 100),
          },
          corpusLines: 100000,
        );
        final spread = computeTermSpread(perStory, groups);
        expect(spread.dense.map((p) => p.id), ['s2', 's3']);
        expect(spread.restCount, 1);
      });
    });

    test('a story no collection holds is with the others', () {
      final spread = computeTermSpread(
        {'x/1.txt': 9, 'loose/1.txt': 2, 'loose/2.txt': 1},
        const StoryGroups(
          groupOf: {'x/1.txt': 'x'},
          labels: {'x': '甲集'},
          groupLines: {'x': 100, '': 30},
          corpusLines: 130,
        ),
      );
      expect(spread.collections, 2);
      expect(
        formatTermSpread(spread),
        '12 行，2 个故事集：甲集 9 行 / 1 章、其他 3 行 / 2 章',
      );
    });
  });

  group('over a fixture database', () {
    late Directory dir;
    late String path;
    late GameDataKnowledgeStore store;

    setUpAll(useSqfliteFfi);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_spread');
      path = p.join(dir.path, 'spread.db');
      await _createFixture(path);
      store = GameDataKnowledgeStore(dbPath: path);
    });

    tearDown(() async {
      await store.close();
      await deleteTempDir(dir);
    });

    test('a story outside the catalog is in its entry\'s collection', () async {
      final groups = await store.withDatabase(queryStoryGroups);
      expect(groups!.groupOf['activities/act_a/level_act_a_01.txt'], 'act_a');
      // Its entry is in the catalog's collection: one group, the catalog's
      // label.
      expect(groups.groupOf['activities/act_a/training_act_a_01.txt'], 'act_a');
      expect(groups.labels['act_a'], '前日谈');
      expect(groups.groupOf['tutorial/t_01.txt'], 'guide');
      expect(groups.labels['guide'], '入门');
      expect(groups.groupOf.containsKey('loose/x_01.txt'), isFalse);
      expect(groups.groupLines['act_a'], 31 + 4);
      expect(groups.groupLines[''], 2);
      expect(
        groups.corpusLines,
        groups.groupLines.values.fold<int>(0, (n, c) => n + c),
      );
    });

    test('the counts per story add up to the counts per term', () async {
      final termLines = <String, int>{};
      final termStories = <String, Map<String, int>>{};
      await store.withDatabase(
        (db) => queryStoryLinesLike(
          db,
          ['阿甲', '乙', '没有的词'],
          termLines: termLines,
          termStories: termStories,
        ),
      );
      Future<int> count(String term) async => (await store.withDatabase(
            (db) => db.rawQuery(
              'SELECT COUNT(*) AS n FROM story_lines '
              'WHERE content LIKE ? OR speaker LIKE ?',
              ['%$term%', '%$term%'],
            ),
          ))!
              .first['n'] as int;
      for (final term in ['阿甲', '乙', '没有的词']) {
        expect(termLines[term], await count(term), reason: term);
        expect(
          termStories[term]!.values.fold<int>(0, (n, c) => n + c),
          termLines[term],
          reason: term,
        );
      }
      expect(termStories['没有的词'], isEmpty);
    });

    test('search: one line per word with its spread', () async {
      final out = (await SearchTool(store, SeenLines()).run('阿甲 入门的 没有的词')).text;
      final head = out.split('\n');
      expect(head[0], '检索“阿甲 入门的 没有的词”：只有关键词检索（没有配置向量服务）');
      expect(head[1], '关键词：');
      expect(
        head[2],
        '阿甲（28 行，5 个故事集：前日谈 12 行 / 2 章、后日谈 11 行 / 1 章；'
        '另 3 个共 18%）',
      );
      expect(head[3], '入门的（1 行，1 个故事集：入门 1 行 / 1 章）');
      expect(head[4], '没有的词（0 行，原文里没有这个写法）');
      // The passages still follow.
      expect(out, contains('## 明日方舟剧情（最相关的'));
    });

    test('search within a collection: the counts only', () async {
      final out =
          (await SearchTool(store, SeenLines()).run('阿甲', collection: '后日谈'))
              .text;
      expect(out, contains('关键词：\n阿甲（全库 28 行）\n'));
      expect(out, isNot(contains('个故事集：')));
    });

    test('the spread is not something read', () async {
      final seen = SeenLines();
      await SearchTool(store, seen).run('没有的词 入门的');
      // Only the story whose lines were printed.
      expect(seen.stories, ['tutorial/t_01.txt']);
    });

    test('grep over the corpus: the collections before the chapters', () async {
      final out = await GrepTool(store, SeenLines()).execute({'pattern': '阿甲'});
      final lines = out.split('\n');
      expect(lines[0], startsWith('全库共 28 行命中，分布在 6 个故事'));
      expect(
        lines[1],
        '按故事集：28 行，5 个故事集：前日谈 12 行 / 2 章、后日谈 11 行 / 1 章；'
        '另 3 个共 18%',
      );
      expect(out, contains('activities/act_b/level_act_b_01.txt | '));
    });
  });
}

/// "act_a" (a catalog chapter and a training file that is only an entry),
/// "act_b", "act_c", a tutorial that is only an entry, and a file nothing
/// holds.
Future<void> _createFixture(String path) async {
  final db = await createGameDataDb(path, catalog: true);
  List<String> lines(Map<String, int> speakers) => [
        '开场的旁白。',
        for (final MapEntry(key: who, value: n) in speakers.entries)
          for (var i = 0; i < n; i++) '$who：第 $i 句。',
      ];
  final catalog = {
    'activities/act_a/level_act_a_01.txt':
        ('act_a', '前日谈', lines({'阿甲': 10, '乙': 20})),
    'activities/act_b/level_act_b_01.txt':
        ('act_b', '后日谈', lines({'阿甲': 11, '戊': 15})),
    'activities/act_c/level_act_c_01.txt':
        ('act_c', '路过的事', lines({'阿甲': 3, '己': 12})),
  };
  for (final MapEntry(key: id, value: s) in catalog.entries) {
    await insertStory(db, id, s.$3, scopeId: s.$1);
    await db.insert('story_catalog', {
      'story_id': id,
      'collection_id': s.$1,
      'collection_name': s.$2,
      'collection_type': 'ACTIVITY',
      'story_code': 'X-1',
      'story_name': '一',
      'avg_tag': '行动前',
      'story_sort': 1,
      'synopsis': '梗概。',
      'start_time': 1700000000,
    });
  }
  final loose = {
    'activities/act_a/training_act_a_01.txt': lines({'阿甲': 2, '丁': 1}),
    'tutorial/t_01.txt': ['入门的第一句。', '阿甲：第二句。', '丁：第三句。'],
    'loose/x_01.txt': ['没人管的一句。', '阿甲：又一句。'],
  };
  for (final MapEntry(key: id, value: text) in loose.entries) {
    await insertStory(db, id, text);
  }
  await db.insert('collections', {'id': 'act_a', 'kind': 'sidestory', 'name': '前日谈（条目）'});
  await db.insert('collections', {'id': 'guide', 'kind': 'system', 'name': '入门'});
  await db.insert('entries', {
    'id': 'story:activities/act_a/training_act_a_01.txt',
    'type': 'story',
    'collection_id': 'act_a',
  });
  await db.insert('entries', {
    'id': 'story:tutorial/t_01.txt',
    'type': 'story',
    'collection_id': 'guide',
  });
  await db.close();
}
