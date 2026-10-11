import 'dart:io';
import 'dart:typed_data';

import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tool_call_gate.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

/// 0.14: `search` with `near` — passages of other collections that read
/// like one already read, by the vectors the database has (no embedding
/// service). The stories are made up; their vectors are set by hand.
void main() {
  const a1 = 'activities/a/level_a_01.txt';
  const a2 = 'activities/a/level_a_02.txt';
  const b = 'activities/b/level_b_01.txt';
  const c = 'activities/c/level_c_01.txt';
  const d = 'activities/d/level_d_01.txt';
  const e = 'activities/e/level_e_01.txt';

  late Directory dir;
  late GameDataKnowledgeStore store;
  late String dbPath;

  setUpAll(useSqfliteFfi);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('arklores_near');
    final path = dbPath = p.join(dir.path, 'near.db');
    final db = await createGameDataDb(path, catalog: true, vectors: true);
    await db.insert('gamedata_manifest', {'key': manifestEmbeddingModel, 'value': 'm'});
    await db.insert('gamedata_manifest', {'key': manifestEmbeddingDims, 'value': '2'});
    Future<void> story(String id, String collection, String name) async {
      await insertStory(
        db,
        id,
        [for (var i = 0; i < 20; i++) '某人：$name的第 $i 句。'],
        scopeId: collection,
      );
      await db.insert('story_catalog', {
        'story_id': id,
        'collection_id': collection,
        'collection_name': name,
        'collection_type': 'ACTIVITY',
        'story_code': 'X-1',
        'story_name': '一',
        'avg_tag': '行动前',
        'story_sort': id == a2 ? 2 : 1,
        'synopsis': '梗概。',
        'start_time': 1700000000,
      });
    }

    Future<void> chunk(String id, int start, List<double> v) async {
      final q = quantize(v);
      await db.insert(storyChunkVectorsTable, {
        'chunk_id': '$id#$start',
        'story_id': id,
        'scope_id': null,
        'line_start': start,
        'line_end': start + 11,
        'scale': q.scale,
        'vec': Uint8List.view(q.values.buffer, q.values.offsetInBytes, q.values.length),
      });
    }

    await story(a1, 'act_a', '甲集');
    await story(a2, 'act_a', '甲集');
    await story(b, 'act_b', '乙集');
    await story(c, 'act_c', '丙集');
    await story(d, 'act_d', '丁集');
    await story(e, 'act_e', '戊集');
    await chunk(a1, 0, [1, 0]);
    await chunk(a1, 8, [0.9, 0.44]);
    // The same collection: never listed, however close.
    await chunk(a2, 0, [1, 0]);
    // Two passages of one collection: the closer one is the one listed.
    await chunk(b, 0, [0.95, 0.31]);
    await chunk(b, 8, [1, 0.05]);
    // The other way: near nothing.
    await chunk(c, 0, [-1, 0]);
    // 0.75: over the line.
    await chunk(d, 0, [0.75, 0.66]);
    // "e" has no vectors.
    await db.close();
    store = GameDataKnowledgeStore(dbPath: path);
  });

  tearDown(() async {
    await store.close();
    await deleteTempDir(dir);
  });

  test('the first chunk holding the line is the passage', () {
    final index = StoryVectorIndex.loadFile(dbPath)!;
    expect(index.chunkAt(a1, 3), (lineStart: 0, lineEnd: 11));
    // Lines 8–11 are in both chunks.
    expect(index.chunkAt(a1, 9), (lineStart: 0, lineEnd: 11));
    expect(index.chunkAt(a1, 15), (lineStart: 8, lineEnd: 19));
    expect(index.chunkAt(a1, 40), isNull);
    expect(index.chunkAt(e, 0), isNull);
  });

  test('one passage per other collection, close ones only, closest first',
      () async {
    final near = (await store.storyChunksNear(a1, 3))!;
    expect((near.lineStart, near.lineEnd), (0, 11));
    expect(
      near.hits.map((h) => '${h.storyId}#${h.lineStart}'),
      ['$b#8', '$d#0'],
    );
    expect(near.hits.first.score, greaterThan(0.99));
    expect(near.hits.last.score, closeTo(0.75, 0.01));
    expect(near.hits.every((h) => h.score >= nearMinSimilarity), isTrue);
    // Nothing reads like this one.
    expect((await store.storyChunksNear(c, 0))!.hits, isEmpty);
    // No vector for the line.
    expect(await store.storyChunksNear(e, 0), isNull);
  });

  test('search near: the passages, their lines read; no embedding service',
      () async {
    final seen = SeenLines();
    final out = await SearchTool(store, seen).execute({'near': '$a1:3'});
    final lines = out.split('\n');
    expect(lines.first, '检索与《甲集 X-1 行动前《一》》 L0-11 相近的段落（按意思）：');
    expect(lines[1], startsWith('1. 《乙集 X-1 行动前《一》》 $b（意思相近 1.00）'));
    expect(out, contains('2. 《丁集 X-1 行动前《一》》 $d（意思相近 0.75）'));
    expect(out, isNot(contains(a2)));
    expect(out, isNot(contains(c)));
    expect(out, contains('L8 [某人] 乙集的第 8 句。'));
    expect(out, contains('…（L16-19 没有列出，要引用先用 read_story 读）'));
    expect(
      lines.last,
      '（只列相近程度 0.70 以上的，每个故事集一段，最多 5 段；这一段所在的故事集不列。'
      '上面列出的行可以引用，没有列出的行要先读）',
    );
    // The eight lines printed of each are read; the passage asked about and
    // the rest are not.
    expect(seen.covers(b, 8, 15), isTrue);
    expect(seen.covers(b, 16, 16), isFalse);
    expect(seen.covers(d, 0, 7), isTrue);
    expect(seen.stories, unorderedEquals([b, d]));
  });

  test('search near: nothing alike, no vector, no such story, a bad position',
      () async {
    final tool = SearchTool(store, SeenLines());
    expect(
      await tool.execute({'near': '$c:L2'}),
      startsWith('别处没有与《丙集 X-1 行动前《一》》 L0-11 相近的段落（只列相近程度 0.70 以上的'),
    );
    expect(await tool.execute({'near': '$e:0'}), contains('没有向量'));
    expect(
      await tool.execute({'near': 'activities/none/x.txt:0'}),
      startsWith('没有这个 story_id：activities/none/x.txt'),
    );
    expect(await tool.execute({'near': '甲集的开头'}), startsWith('错误：near 要写成'));
    // The story id without its extension, a range for the line.
    expect(
      await tool.execute({'near': '${a1.replaceAll('.txt', '')}:3-5'}),
      startsWith('检索与《甲集'),
    );
  });

  test('the gate: query or near, one of them', () {
    final tool = SearchTool(store, SeenLines());
    ToolCall call(String args) =>
        ToolCall(id: 'c', name: 'search', arguments: args);
    final neither = checkToolCall(call('{"game":"arknights"}'), tool, ['search']);
    expect(neither.ok, isFalse);
    expect(neither.error, startsWith('错误：search 的参数 query、near 至少要给一个'));
    expect(neither.error, contains('正确的写法：{"query":"<query>"}'));
    expect(checkToolCall(call('{"near":"$a1:3"}'), tool, ['search']).ok, isTrue);
    expect(checkToolCall(call('{"query":"甲集"}'), tool, ['search']).ok, isTrue);
    expect(tool.description, contains('near 写一段读过的剧情的位置'));
    expect(tool.parameters.containsKey('required'), isFalse);
  });
}
