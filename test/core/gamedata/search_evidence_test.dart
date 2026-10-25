import 'dart:io';
import 'dart:typed_data';

import 'package:arklores/core/agent/coverage.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

void main() {
  late Directory dir;
  late Database db;
  late GameDataKnowledgeStore store;

  setUpAll(useSqfliteFfi);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('search_evidence');
    final path = '${dir.path}/test.db';
    db = await createGameDataDb(path, catalog: true, vectors: true, manifest: {
      ...validManifest,
      manifestEmbeddingModel: 'test',
      manifestEmbeddingDims: '2',
      manifestEmbeddingChunking: chunkingSignature,
    },);
    store = GameDataKnowledgeStore(dbPath: path);
  });
  tearDown(() async {
    await store.close();
    await db.close();
    await deleteTempDir(dir);
  });

  Future<void> story(
    String id,
    List<String> lines, {
    String collection = 'outside',
    List<double> vector = const [1, 0],
  }) async {
    await insertStory(db, id, lines, scopeId: collection);
    await db.insert('story_catalog', {
      'story_id': id,
      'collection_id': collection,
      'collection_name': collection,
      'collection_type': 'ACTIVITY',
      'story_name': id,
      'story_sort': 1,
    });
    final q = quantize(vector);
    await db.insert(storyChunkVectorsTable, {
      'chunk_id': '$id#0-${lines.length - 1}',
      'story_id': id,
      'scope_id': 'activity:$collection',
      'line_start': 0,
      'line_end': lines.length - 1,
      'scale': q.scale,
      'vec': Uint8List.view(q.values.buffer),
    });
  }

  test('collection keyword search ranks within the collection', () async {
    for (var i = 0; i < 70; i++) {
      await story('activities/out/$i.txt', ['灯塔 灯火', '灯塔 灯火']);
    }
    const target = 'activities/target/one.txt';
    await story(target, ['灯塔在这里。'], collection: 'target');
    final seen = SeenLines();
    final result =
        await SearchTool(store, seen).run('灯塔 灯火', collection: 'target');
    expect(result.text, contains(target));
    expect(result.text, isNot(contains('activities/out/')));
    expect(seen.covers(target, 0, 0), isTrue);
  });

  test('collection semantic search ranks within the collection', () async {
    for (var i = 0; i < 130; i++) {
      await story('activities/out/$i.txt', ['外面的台词。']);
    }
    const target = 'activities/target/one.txt';
    await story(target, ['范围内的原文。'], collection: 'target', vector: [0.8, 0.6]);
    final seen = SeenLines();
    final result = await SearchTool(store, seen, embeddingClient: _Embedder())
        .run('询问范围内没有同词的事情', collection: 'target');
    expect(result.text, contains(target));
    expect(seen.covers(target, 0, 0), isTrue);
  });

  test('passages omitted by the output budget never become citable', () async {
    for (var i = 0; i < 5; i++) {
      await story('activities/long/$i.txt',
          [for (var n = 0; n < 8; n++) '第$n行${'原文' * 190}'],);
    }
    final seen = SeenLines();
    final call = SeenLines();
    final result = await SeenLines.duringCall(
        call,
        () => SearchTool(store, seen, embeddingClient: _Embedder())
            .run('询问没有共同关键词的事情'),);
    expect(result.text, contains('篇幅已满'));
    for (var i = 0; i < 5; i++) {
      final id = 'activities/long/$i.txt';
      final printed = result.text.contains(id);
      expect(seen.covers(id, 0, 0), printed, reason: id);
      expect(call.covers(id, 0, 0), printed, reason: 'call: $id');
    }
  });

  test('a matched semantic chunk includes its final lines', () async {
    const target = 'activities/target/one.txt';
    await story(target, [for (var n = 0; n < 12; n++) '第$n句原文。']);
    final seen = SeenLines();
    final result = await SearchTool(store, seen, embeddingClient: _Embedder())
        .run('询问没有共同关键词的事情');
    expect(result.text, contains('L11 第11句原文。'));
    expect(seen.covers(target, 0, 11), isTrue);
  });

  test('a sparse semantic chunk reads twelve rows through its actual end', () async {
    const target = 'activities/sparse/one.txt';
    const kept = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 32];
    await story(target, [for (var n = 0; n <= 32; n++) '第$n句原文。']);
    await db.delete('story_lines',
        where: 'story_id = ? AND line_index NOT IN (${kept.join(',')})',
        whereArgs: [target],);
    final seen = SeenLines();
    final result = await SearchTool(store, seen, embeddingClient: _Embedder())
        .run('询问没有共同关键词的事情');
    for (var n = 0; n <= 32; n++) {
      expect(seen.covers(target, n, n), kept.contains(n), reason: 'L$n');
      if (kept.contains(n)) expect(result.text, contains('L$n 第$n句原文。'));
    }
    expect(result.text, isNot(contains('没有列出，要引用先用')));
  });

  test('a sparse chunk over the character budget marks its unread tail', () async {
    const target = 'activities/sparse/long.txt';
    const kept = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 35];
    String line(int n) => '第$n句${'原文' * 190}。';
    await story(target, [for (var n = 0; n <= 35; n++) line(n)]);
    await db.delete('story_lines',
        where: 'story_id = ? AND line_index NOT IN (${kept.join(',')})',
        whereArgs: [target],);
    final seen = SeenLines();
    final call = SeenLines();
    final result = await SeenLines.duringCall(call, () =>
        SearchTool(store, seen, embeddingClient: _Embedder())
            .run('询问没有共同关键词的事情'),);
    expect(result.text, contains('L33 ${line(33)}'));
    expect(result.text, contains('L35-35 没有列出'));
    expect(result.text, isNot(contains('L35 ${line(35)}')));
    final displayed = result.text.split('\n').where((l) => l.startsWith('   L'));
    expect(displayed, hasLength(12));
    expect(displayed.fold<int>(0, (n, l) => n + l.length + 1),
        lessThanOrEqualTo(SearchTool.maxPassageChars),);
    expect(seen.covers(target, 33, 33), isTrue);
    expect(seen.covers(target, 35, 35), isFalse);
    expect(call.covers(target, 35, 35), isFalse);
  });

  test('a migrated chunk shows all 33 short rows but excludes structural evidence', () async {
    const target = 'activities/wide/one.txt';
    await story(target, [for (var n = 0; n <= 32; n++) '第$n句原文。']);
    await db.update('story_lines', {'kind': 'summary'},
        where: 'story_id = ? AND line_index = 0', whereArgs: [target],);
    final seen = SeenLines();
    final result = await SearchTool(store, seen, embeddingClient: _Embedder())
        .run('询问没有共同关键词的事情');
    expect(result.text, contains('第0句原文。'));
    expect(result.text, contains('L32 第32句原文。'));
    expect(result.text, isNot(contains('没有列出，要引用先用')));
    expect(seen.covers(target, 0, 0), isFalse);
    expect(seen.covers(target, 1, 32), isTrue);
  });

  test('grep does not register a story omitted by its output budget', () async {
    final ids = [for (var i = 0; i < 3; i++) 'activities/long/$i.txt'];
    for (final id in ids) {
      await story(id, [for (var n = 0; n < 12; n++) '线索$n${'原文' * 190}']);
    }
    final seen = SeenLines();
    final out = await GrepTool(store, seen).execute({
      'pattern': '线索', 'story_ids': ids, 'context': 0,
    });
    expect(out, contains('篇幅已满'));
    for (final id in ids) {
      expect(seen.covers(id, 0, 0), out.contains('》 $id'), reason: id);
    }
  });

  test('grep pages a large first story at complete line boundaries', () async {
    const id = 'activities/long/one.txt';
    await story(id, [for (var n = 0; n < 30; n++) '线索$n${'原文' * 190}']);
    final seen = SeenLines();
    final out = await GrepTool(store, seen).execute({
      'pattern': '线索', 'story_ids': [id], 'context': 0,
    });
    expect(out, isNot(contains('L29 ')));
    expect(seen.covers(id, 29, 29), isFalse);
    expect(out, contains('start='));
    for (var n = 0; n < 30; n++) {
      if (seen.covers(id, n, n)) {
        expect(out, contains('线索$n${'原文' * 190}'));
      }
    }
  });

  test('reading a sparse page does not invent evidence between its rows', () async {
    const id = 'activities/sparse/one.txt';
    await story(id, ['开头。', '待删除。', '结尾。']);
    await db.delete('story_lines', where: 'story_id = ? AND line_index = 1',
        whereArgs: [id],);
    final seen = SeenLines();
    await ReadStoryTool(store, seen).execute({'story_id': id});
    expect(seen.covers(id, 0, 0), isTrue);
    expect(seen.covers(id, 1, 1), isFalse);
    expect(seen.covers(id, 2, 2), isTrue);
  });

  test('structure and summaries stay visible but cannot be cited', () async {
    const id = 'activities/structure/one.txt';
    const kinds = ['step', 'stage', 'unplaced', 'summary', 'section', 'title', 'system'];
    await story(id, [for (final kind in kinds) '线索$kind', '线索原文。']);
    for (var i = 0; i < kinds.length; i++) {
      await db.update('story_lines', {'kind': kinds[i]},
          where: 'story_id = ? AND line_index = ?', whereArgs: [id, i],);
    }
    for (final tool in ['read', 'grep', 'search', 'gather', 'sql']) {
      final seen = SeenLines();
      switch (tool) {
        case 'read':
          await ReadStoryTool(store, seen).execute({'story_id': id});
        case 'grep':
          await GrepTool(store, seen).execute({'pattern': '线索', 'story_ids': [id]});
        case 'search':
          await SearchTool(store, seen, embeddingClient: _Embedder()).run('线索');
        case 'gather':
          (await CoverageBuilder(store).build(['线索'])).register(seen);
        case 'sql':
          // Omitting kind must not bypass the source restriction.
          await SqlTool(store, seen).execute({
            'query': "SELECT story_id, line_index, content FROM story_lines WHERE story_id = '$id'",
          });
      }
      for (var i = 0; i < kinds.length; i++) {
        expect(seen.covers(id, i, i), isFalse, reason: '$tool: ${kinds[i]}');
      }
      expect(seen.covers(id, kinds.length, kinds.length), isTrue, reason: tool);
    }
  });

  test('a long citation must be checked beyond its first thousand lines', () {
    final seen = SeenLines()..addRange('a.txt', 0, 999)..add('a.txt', 1500);
    expect(seen.covers('a.txt', 0, 1500), isFalse);
    expect(seen.seenRanges('a.txt', 0, 1500), [(0, 999), (1500, 1500)]);
  });
}

class _Embedder extends EmbeddingClient {
  @override
  String get model => 'test';
  @override
  int get dimensions => 2;
  @override
  Future<List<List<double>>> embed(List<String> texts) async => [
        for (final _ in texts) [1, 0],
      ];
}
