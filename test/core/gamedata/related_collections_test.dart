import 'dart:io';
import 'dart:typed_data';

import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/agent/tools/wiki_tools.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_catalog.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:arklores/core/wiki/wiki_lookup.dart';
import 'package:arklores/core/wiki/wiki_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

/// 0.14: which collections are related to one — shared speakers (counted in
/// SQL) and, with vectors, how alike they read. The names are made up: the
/// mechanism knows no story.
void main() {
  group('rankRelatedCollections', () {
    // Who speaks (often enough) in which collections.
    const speakers = {
      '甲': {'a', 'b'},
      '乙': {'a', 'b', 'c'},
      // Everywhere: weighs least.
      '路人': {'a', 'b', 'c', 'd', 'e', 'f'},
      // Not in the target: says nothing about it.
      '丙': {'c', 'd'},
      // An unnamed voice is nobody, wherever it speaks.
      '？？？': {'a', 'f'},
    };

    test('by speakers alone: more and rarer shared speakers first', () {
      final ranked = rankRelatedCollections('a', speakers, null);
      expect(ranked.map((r) => r.id), ['b', 'c', 'd', 'e', 'f']);
      expect(ranked.first.shared, 3);
      // The least common name first, the one who is everywhere last.
      expect(ranked.first.names, ['甲', '乙', '路人']);
      expect(ranked.first.similarity, isNull);
      expect(ranked.any((r) => r.id == 'a'), isFalse);
    });

    test('with similarity the two rankings are joined by rank', () {
      // "c" reads most like the target, "b" shares the most speakers.
      final ranked = rankRelatedCollections(
        'a',
        speakers,
        {'a': 1, 'b': 0.80, 'c': 0.95, 'd': 0.10, 'z': 0.90},
      );
      // First in one and second in the other, either way round, beats the
      // collection that only reads alike ("z": no shared speaker).
      expect(ranked.take(2).map((r) => r.id).toSet(), {'b', 'c'});
      expect(ranked.map((r) => r.id), contains('z'));
      final z = ranked.firstWhere((r) => r.id == 'z');
      expect(z.shared, 0);
      expect(z.names, isEmpty);
      expect(z.similarity, 0.90);
      expect(
        ranked.indexWhere((r) => r.id == 'z'),
        greaterThan(ranked.indexWhere((r) => r.id == 'c')),
      );
    });

    test('limit; nothing shared and no vectors is an empty list', () {
      expect(rankRelatedCollections('a', speakers, null, limit: 2), hasLength(2));
      expect(rankRelatedCollections('x', speakers, null), isEmpty);
      expect(rankRelatedCollections('a', const {}, null), isEmpty);
    });
  });

  group('over a fixture database', () {
    late Directory dir;
    late GameDataKnowledgeStore store;

    setUpAll(useSqfliteFfi);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('arklores_related');
      final path = p.join(dir.path, 'related.db');
      await _createFixture(path);
      store = GameDataKnowledgeStore(dbPath: path);
    });

    tearDown(() async {
      await store.close();
      await deleteTempDir(dir);
    });

    test('a speaker counts from ten lines on, in both collections', () async {
      final related = await store.relatedCollections('act_a');
      // "act_b" shares two speakers; "act_c" only someone with three lines
      // there; "act_d" nobody.
      expect(related.map((r) => r.id), ['act_b']);
      final b = related.single;
      expect(b.label, '后日谈');
      expect(b.releaseMonth, '2023-11');
      expect(b.shared, 2);
      expect(b.names, unorderedEquals(['甲', '乙']));
      // No vectors in this database: speakers only.
      expect(b.similarity, isNull);
      expect(await store.relatedCollections('no_such'), isEmpty);
    });

    test('outline ends with the related collections, also when the chapters '
        'do not all fit', () async {
      final out = await OutlineTool(store).execute({'collection': '前日谈'});
      expect(out, contains('activities/act_a/level_act_a_01.txt'));
      final at = out.indexOf('相关的故事集（按共有人物排列');
      expect(at, greaterThan(0));
      final section = out.substring(at);
      expect(section, contains('只是找资料的线索'));
      expect(section, contains('后日谈（act_b，上线 2023-11）共有 2 人：'));
      expect(section, isNot(contains('内容相近')));
      expect(section, isNot(contains('act_c')));
      // A collection nothing is related to has no such section.
      final alone = await OutlineTool(store).execute({'collection': '无关的事'});
      expect(alone, isNot(contains('相关的故事集')));
    });

    test('search says when a word is a collection\'s name', () async {
      final named = (await SearchTool(store, SeenLines()).run('后日谈 甲')).text;
      expect(named, contains('后日谈（0 行：这是故事集的名字，正文里不这样写）'));
      expect(
        named,
        contains('“后日谈”是故事集（act_b，1 章）：用 outline 看它的目录和相关的故事集。'),
      );
      // A word that is no collection keeps the old wording; part of a name
      // is not the name.
      final other = (await SearchTool(store, SeenLines()).run('日谈 没有的词')).text;
      expect(other, contains('日谈（0 行，原文里没有这个写法）'));
      expect(other, isNot(contains('是故事集')));
    });
  });

  test('collectionCentroids: one unit vector per collection with enough chunks',
      () async {
    useSqfliteFfi();
    final dir = await Directory.systemTemp.createTemp('arklores_centroids');
    addTearDown(() => deleteTempDir(dir));
    final path = p.join(dir.path, 'v.db');
    final db = await createGameDataDb(path, catalog: true, vectors: true);
    await db.insert('gamedata_manifest', {'key': manifestEmbeddingModel, 'value': 'm'});
    await db.insert('gamedata_manifest', {'key': manifestEmbeddingDims, 'value': '2'});
    Future<void> chunk(String story, int at, List<double> v) async {
      final q = quantize(v);
      await db.insert(storyChunkVectorsTable, {
        'chunk_id': '$story#$at',
        'story_id': story,
        'scope_id': null,
        'line_start': at,
        'line_end': at,
        'scale': q.scale,
        'vec': Uint8List.view(q.values.buffer, q.values.offsetInBytes, q.values.length),
      });
    }

    await chunk('s1', 0, [1, 0]);
    await chunk('s1', 1, [0, 1]);
    await chunk('s2', 0, [1, 0]);
    await chunk('s3', 0, [0, 1]);
    await db.close();

    final index = StoryVectorIndex.loadFile(path)!;
    final centroids = index.collectionCentroids(
      {'s1': 'x', 's2': 'x', 's3': 'y'},
      minChunks: 1,
    );
    expect(centroids.keys, unorderedEquals(['x', 'y']));
    // "x": two chunks along the first axis, one along the second.
    final x = centroids['x']!;
    expect(x[0] * x[0] + x[1] * x[1], closeTo(1, 1e-4));
    expect(x[0], greaterThan(x[1]));
    expect(centroids['y']![1], closeTo(1, 1e-3));
    // Too few chunks: no centroid.
    expect(
      index.collectionCentroids({'s1': 'x', 's3': 'y'}, minChunks: 2).keys,
      ['x'],
    );
  });

  test('wiki_search says that several words must all match', () async {
    final tool = WikiSearchTool(_EmptyWiki());
    expect(tool.description, contains('写几个词时要同时出现才算命中'));
    // Words that found nothing together are tried alone by the tool.
    expect(
      await tool.execute({'query': '甲 乙'}),
      contains('“甲”、“乙” 单独搜也没有'),
    );
    expect(
      await tool.execute({'query': '甲'}),
      isNot(contains('单独搜')),
    );
  });
}

/// Finds nothing.
class _EmptyWiki implements WikiLookup {
  @override
  Future<List<WikiSearchHit>> search(Game game, String query, {int limit = 8}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Four collections: "act_a" and "act_b" share 甲 and 乙 (ten lines each in
/// both); 甲 has three lines in "act_c"; "act_d" has its own people.
Future<void> _createFixture(String path) async {
  final db = await createGameDataDb(path, catalog: true);
  List<String> lines(Map<String, int> speakers) => [
        '开场的旁白。',
        for (final MapEntry(key: who, value: n) in speakers.entries)
          for (var i = 0; i < n; i++) '$who：第 $i 句。',
      ];
  final stories = {
    'activities/act_a/level_act_a_01.txt':
        ('act_a', '前日谈', 1690000000, lines({'甲': 10, '乙': 12, '丁': 11})),
    'activities/act_b/level_act_b_01.txt':
        ('act_b', '后日谈', 1700000000, lines({'甲': 11, '乙': 10, '戊': 15})),
    'activities/act_c/level_act_c_01.txt':
        ('act_c', '路过的事', 1710000000, lines({'甲': 3, '己': 12})),
    'activities/act_d/level_act_d_01.txt':
        ('act_d', '无关的事', 1720000000, lines({'庚': 12})),
  };
  for (final MapEntry(key: id, value: s) in stories.entries) {
    await insertStory(db, id, s.$4, scopeId: s.$1);
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
      'start_time': s.$3,
    });
  }
  await db.close();
}
