import 'dart:io';
import 'dart:typed_data';

import 'package:arklores/core/agent/context_ledger.dart';
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
    db = await createGameDataDb(
      path,
      catalog: true,
      vectors: true,
      manifest: {
        ...validManifest,
        manifestEmbeddingModel: 'test',
        manifestEmbeddingDims: '2',
        manifestEmbeddingChunking: chunkingSignature,
      },
    );
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
      await story(
        'activities/long/$i.txt',
        [for (var n = 0; n < 8; n++) '第$n行${'原文' * 190}'],
      );
    }
    final seen = SeenLines();
    final call = SeenLines();
    final result = await SeenLines.duringCall(
      call,
      () => SearchTool(store, seen, embeddingClient: _Embedder())
          .run('询问没有共同关键词的事情'),
    );
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

  test('a sparse semantic chunk reads twelve rows through its actual end',
      () async {
    const target = 'activities/sparse/one.txt';
    const kept = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 32];
    await story(target, [for (var n = 0; n <= 32; n++) '第$n句原文。']);
    await db.delete(
      'story_lines',
      where: 'story_id = ? AND line_index NOT IN (${kept.join(',')})',
      whereArgs: [target],
    );
    final seen = SeenLines();
    final result = await SearchTool(store, seen, embeddingClient: _Embedder())
        .run('询问没有共同关键词的事情');
    for (var n = 0; n <= 32; n++) {
      expect(seen.covers(target, n, n), kept.contains(n), reason: 'L$n');
      if (kept.contains(n)) expect(result.text, contains('L$n 第$n句原文。'));
    }
    expect(result.text, isNot(contains('没有列出，要引用先用')));
  });

  test('a sparse chunk over the character budget marks its unread tail',
      () async {
    const target = 'activities/sparse/long.txt';
    const kept = [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 35];
    String line(int n) => '第$n句${'原文' * 190}。';
    await story(target, [for (var n = 0; n <= 35; n++) line(n)]);
    await db.delete(
      'story_lines',
      where: 'story_id = ? AND line_index NOT IN (${kept.join(',')})',
      whereArgs: [target],
    );
    final seen = SeenLines();
    final call = SeenLines();
    final result = await SeenLines.duringCall(
      call,
      () => SearchTool(store, seen, embeddingClient: _Embedder())
          .run('询问没有共同关键词的事情'),
    );
    expect(result.text, contains('L33 ${line(33)}'));
    expect(result.text, contains('L35-35 未列出'));
    expect(result.text, isNot(contains('L35 ${line(35)}')));
    final displayed =
        result.text.split('\n').where((l) => l.startsWith('   L'));
    expect(displayed, hasLength(12));
    expect(
      displayed.fold<int>(0, (n, l) => n + l.length + 1),
      lessThanOrEqualTo(SearchTool.maxPassageChars),
    );
    expect(seen.covers(target, 33, 33), isTrue);
    expect(seen.covers(target, 35, 35), isFalse);
    expect(call.covers(target, 35, 35), isFalse);
  });

  test(
      'a migrated chunk shows all 33 short rows but excludes structural evidence',
      () async {
    const target = 'activities/wide/one.txt';
    await story(target, [for (var n = 0; n <= 32; n++) '第$n句原文。']);
    await db.update(
      'story_lines',
      {'kind': 'summary'},
      where: 'story_id = ? AND line_index = 0',
      whereArgs: [target],
    );
    final seen = SeenLines();
    final result = await SearchTool(store, seen, embeddingClient: _Embedder())
        .run('询问没有共同关键词的事情');
    expect(result.text, contains('第0句原文。'));
    expect(result.text, contains('L32 第32句原文。'));
    expect(result.text, isNot(contains('没有列出，要引用先用')));
    expect(seen.covers(target, 0, 0), isFalse);
    expect(seen.covers(target, 1, 32), isTrue);
  });

  test(
      'search replaces a fully present passage and keeps its heading and citations',
      () async {
    const target = 'activities/context/one.txt';
    await story(target, [for (var n = 0; n < 40; n++) '第$n句原文。']);
    final readCall = SeenLines();
    await SeenLines.duringCall(
      readCall,
      () => ReadStoryTool(store, SeenLines()).execute({
        'story_id': target,
        'count': 40,
      }),
    );
    final ledger = ContextLedger()
      ..record(0, readCall, step: 1, callKey: 'read_story');
    final seen = SeenLines.fromJson(readCall.toJson());
    final before = seen.toJson();
    const query = '询问没有共同关键词的事情';
    final original = (await SearchTool(
      store,
      SeenLines(),
      embeddingClient: _Embedder(),
    ).run(query))
        .text;
    final call = SeenLines();
    final result = await SeenLines.duringCall(
      call,
      () => SearchTool(
        store,
        seen,
        embeddingClient: _Embedder(),
        ledger: ledger,
      ).run(query),
    );
    String heading(String text) =>
        text.split('\n').firstWhere((line) => line.startsWith('1. 《'));
    expect(heading(result.text), heading(original));
    expect(heading(result.text), contains('意思相近'));
    expect(result.text, contains('（L0–L39 的原文仍在上文，第 1 步的结果）'));
    expect(result.text, isNot(contains('L0 第0句原文。')));
    expect(call.isEmpty, isTrue);
    expect(seen.toJson(), before);

    ledger.forget([0]);
    final afterForget = await SearchTool(
      store,
      seen,
      embeddingClient: _Embedder(),
      ledger: ledger,
    ).run(query);
    expect(afterForget.text, contains('L0 第0句原文。'));
  });

  test('search replaces only a useful in-context run in a mixed passage',
      () async {
    const target = 'activities/context/partial.txt';
    await story(target, [
      for (var n = 0; n < 5; n++) '甲：锚点$n ${'原文' * 20}',
    ]);
    final readCall = SeenLines();
    await SeenLines.duringCall(
      readCall,
      () => ReadStoryTool(store, SeenLines()).execute({
        'story_id': target,
        'start': 2,
        'count': 1,
      }),
    );
    final ledger = ContextLedger()
      ..record(0, readCall, step: 3, callKey: 'read_story');
    final call = SeenLines();
    final output = (await SeenLines.duringCall(
      call,
      () => SearchTool(
        store,
        SeenLines(),
        embeddingClient: _Embedder(),
        ledger: ledger,
      ).run('询问没有共同关键词的事情'),
    ))
        .text;
    expect(output, contains('L2–L2 的原文仍在上文，略去'));
    expect(output, contains('L1 [甲] 锚点1'));
    expect(output, contains('L3 [甲] 锚点3'));
    expect(call.covers(target, 2, 2), isFalse);
    expect(call.covers(target, 1, 1), isTrue);
    expect(call.covers(target, 3, 3), isTrue);
  });

  test('search prints a short source line when its pointer would be longer',
      () async {
    const target = 'activities/context/short.txt';
    await story(target, ['甲：开头', '甲：短句', '甲：结尾']);
    final readCall = SeenLines();
    await SeenLines.duringCall(
      readCall,
      () => ReadStoryTool(store, SeenLines()).execute({
        'story_id': target,
        'start': 1,
        'count': 1,
      }),
    );
    final ledger = ContextLedger()
      ..record(0, readCall, step: 1, callKey: 'read_story');
    final output = (await SearchTool(
      store,
      SeenLines(),
      embeddingClient: _Embedder(),
      ledger: ledger,
    ).run('询问没有共同关键词的事情'))
        .text;
    expect(output, contains('L1 [甲] 短句'));
    expect(output, isNot(contains('L1–L1 的原文仍在上文，略去')));
  });

  test('gather omits lines registered by the earlier search', () async {
    const target = 'activities/gather/context.txt';
    await story(target, [for (var n = 0; n < 25; n++) '锚点$n ${'原文' * 20}']);
    final seen = SeenLines();
    final searchCall = SeenLines();
    const query = '询问没有共同关键词的事情';
    await SeenLines.duringCall(
      searchCall,
      () => SearchTool(
        store,
        seen,
        embeddingClient: _Embedder(),
      ).run(query),
    );
    final ledger = ContextLedger()
      ..record(0, searchCall, step: 1, callKey: 'search');
    final before = seen.toJson();
    final result = await GatherTool(store, seen, ledger: ledger).execute({
      'names': ['锚点'],
    });
    expect(result, contains('（L0–L24 的原文仍在上文，第 1 步的结果）'));
    expect(result, isNot(contains('L0 锚点0')));
    expect(seen.toJson(), before);
  });

  test('search, gather and grep descriptions carry their fixed result notes',
      () async {
    for (var i = 0; i < 8; i++) {
      await story(
        'activities/spread/$i.txt',
        ['跨集词出现在这里。'],
        collection: 'spread-$i',
      );
    }
    const gatherStory = 'activities/gather/notes.txt';
    await story(gatherStory, ['锚点前。', '取材词命中。', '锚点后。']);

    final search = SearchTool(store, SeenLines(), embeddingClient: _Embedder());
    expect(search.description, contains('“关键词还出现在这些故事集”一节列出'));
    expect(search.description, contains('用 game 参数单独查该游戏'));
    expect(search.description, contains('资料行格式：出处 | 类别 | 标题（所属对象） | 片段'));
    expect(search.description, contains('未列出的行在 read_story 读到后才能引用'));
    final found = (await search.run('跨集词')).text;
    expect(found, contains('### 关键词还出现在这些故事集'));
    expect(found, isNot(contains('分布里的是故事集的名字')));
    expect(found, isNot(contains('上面的分布里列出、还没有段落的')));
    expect(found, isNot(contains('上面列出的行可以引用')));
    expect(found, isNot(contains('要引用先用 read_story 读')));

    final gather = GatherTool(store, SeenLines());
    expect(gather.description, contains('按上线顺序排列'));
    expect(gather.description, contains('默认取每处前后各两行原文'));
    expect(gather.description, contains('启用挑行时'));
    expect(gather.description, contains('行号可以直接引用'));
    expect(gather.description, contains('前后更多内容用 read_story'));
    final gathered = await gather.execute({'names': ['取材词']});
    expect(gathered, contains('取材词命中'));
    expect(gathered, isNot(contains('按上线顺序排列')));
    expect(gathered, isNot(contains('行号可以直接引用')));
    expect(gathered, isNot(contains('每篇只取这些名字出现')));

    final grep = GrepTool(store, SeenLines());
    expect(grep.description, contains('命中标记'));
    expect(grep.description, contains('格式为 story_id | 章节 | 命中行数'));
    expect(grep.description, contains('可用 sql 按需要的条件统计'));
    expect(grep.description, contains('未列出的命中及其所在故事'));
    final distribution = await grep.execute({'pattern': '跨集词'});
    expect(distribution, isNot(contains('主线在前，其余按上线时间')));
    expect(distribution, isNot(contains('这里只是分布')));
    final hits = await grep.execute({
      'pattern': '跨集词',
      'story_ids': ['activities/spread/0.txt'],
    });
    expect(hits, contains('* L'));
    expect(hits, isNot(contains('为命中行')));
  });

  test('read tools put fixed lookup guidance in their descriptions', () async {
    final readStory = ReadStoryTool(store, SeenLines());
    expect(readStory.description, contains('story_catalog'));
    final absentStory = await readStory.execute({'story_id': 'missing'});
    expect(absentStory, '没有这个 story_id：missing.txt。');
    expect(absentStory, isNot(contains('可以用 sql')));

    final readRecord = ReadRecordTool(store, SeenLines());
    expect(readRecord.description, contains('normalized_records / entity_documents'));
    final absentRecord = await readRecord.execute({'id': 'missing'});
    expect(absentRecord, '没有 id 为 missing 的资料。');
    expect(absentRecord, isNot(contains('按名字找资料用 search')));
  });

  test('search passage count still uses the pre-omission budget', () async {
    final ids = [for (var i = 0; i < 5; i++) 'activities/budget/$i.txt'];
    for (final id in ids) {
      await story(id, [
        for (var n = 0; n < 8; n++) '第$n句${'原文' * 190}。',
      ]);
    }
    const query = '询问没有共同关键词的事情';
    final original = (await SearchTool(
      store,
      SeenLines(),
      embeddingClient: _Embedder(),
    ).run(query))
        .text;
    final ledger = ContextLedger();
    for (final (i, id) in ids.indexed) {
      ledger.record(
        i,
        SeenLines()..addRange(id, 0, 7),
        step: i + 1,
        callKey: 'read-$i',
      );
    }
    final compacted = (await SearchTool(
      store,
      SeenLines(),
      embeddingClient: _Embedder(),
      ledger: ledger,
    ).run(query))
        .text;
    int passageCount(String text) =>
        RegExp(r'^\d+\. 《', multiLine: true).allMatches(text).length;
    expect(original, contains('篇幅已满'));
    expect(compacted, contains('篇幅已满'));
    expect(passageCount(compacted), passageCount(original));
  });

  test(
      'grep keeps hit totals and unlisted-hit guidance when its line is omitted',
      () async {
    const target = 'activities/grep/context.txt';
    await story(target, [
      '目标词 ${'原文' * 30}',
      '中间内容。',
      '目标词 ${'其他原文' * 30}',
    ]);
    const args = {
      'pattern': '目标词',
      'story_ids': [target],
      'context': 0,
      'max_hits': 1,
    };
    final original = await GrepTool(store, SeenLines()).execute(args);
    final firstLine =
        int.parse(RegExp(r'\* L(\d+)').firstMatch(original)!.group(1)!);
    final ledger = ContextLedger()
      ..record(
        0,
        SeenLines()..add(target, firstLine),
        step: 2,
        callKey: 'read_story',
      );
    final seen = SeenLines()..add(target, firstLine);
    final before = seen.toJson();
    final compacted = await GrepTool(store, seen, ledger: ledger).execute(args);
    expect(compacted, contains('（1 处）'));
    expect(compacted, contains('（L$firstLine–L$firstLine 的原文仍在上文，第 2 步的结果）'));
    expect(compacted, contains('命中超过 1 行，只列出前 1 行'));
    expect(
      compacted.substring(compacted.indexOf('没有列出的命中：')),
      original.substring(original.indexOf('没有列出的命中：')),
    );
    expect(seen.toJson(), before);
  });

  test('search, gather, and grep keep their legacy output without a ledger',
      () async {
    const target = 'activities/context/no-ledger.txt';
    await story(target, [for (var n = 0; n < 12; n++) '定位词$n ${'原文' * 10}']);
    const query = '询问没有共同关键词的事情';
    final searchWithoutLedger = await SearchTool(
      store,
      SeenLines(),
      embeddingClient: _Embedder(),
    ).run(query);
    final searchWithNullLedger = await SearchTool(
      store,
      SeenLines(),
      embeddingClient: _Embedder(),
      ledger: null,
    ).run(query);
    expect(searchWithNullLedger.text, searchWithoutLedger.text);

    final gatherWithoutLedger = await GatherTool(store, SeenLines()).execute({
      'names': ['定位词'],
    });
    final gatherWithNullLedger = await GatherTool(
      store,
      SeenLines(),
      ledger: null,
    ).execute({
      'names': ['定位词'],
    });
    expect(gatherWithNullLedger, gatherWithoutLedger);

    const args = {
      'pattern': '定位词',
      'story_ids': [target],
    };
    final grepWithoutLedger = await GrepTool(store, SeenLines()).execute(args);
    final grepWithNullLedger =
        await GrepTool(store, SeenLines(), ledger: null).execute(args);
    expect(grepWithNullLedger, grepWithoutLedger);
  });

  test('grep does not register a story omitted by its output budget', () async {
    final ids = [for (var i = 0; i < 3; i++) 'activities/long/$i.txt'];
    for (final id in ids) {
      await story(id, [for (var n = 0; n < 12; n++) '线索$n${'原文' * 190}']);
    }
    final seen = SeenLines();
    final out = await GrepTool(store, seen).execute({
      'pattern': '线索',
      'story_ids': ids,
      'context': 0,
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
      'pattern': '线索',
      'story_ids': [id],
      'context': 0,
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

  test('reading a sparse page does not invent evidence between its rows',
      () async {
    const id = 'activities/sparse/one.txt';
    await story(id, ['开头。', '待删除。', '结尾。']);
    await db.delete(
      'story_lines',
      where: 'story_id = ? AND line_index = 1',
      whereArgs: [id],
    );
    final seen = SeenLines();
    await ReadStoryTool(store, seen).execute({'story_id': id});
    expect(seen.covers(id, 0, 0), isTrue);
    expect(seen.covers(id, 1, 1), isFalse);
    expect(seen.covers(id, 2, 2), isTrue);
  });

  test('structure and summaries stay visible but cannot be cited', () async {
    const id = 'activities/structure/one.txt';
    const kinds = [
      'step',
      'stage',
      'unplaced',
      'summary',
      'section',
      'title',
      'system',
    ];
    await story(id, [for (final kind in kinds) '线索$kind', '线索原文。']);
    for (var i = 0; i < kinds.length; i++) {
      await db.update(
        'story_lines',
        {'kind': kinds[i]},
        where: 'story_id = ? AND line_index = ?',
        whereArgs: [id, i],
      );
    }
    for (final tool in ['read', 'grep', 'search', 'gather', 'sql']) {
      final seen = SeenLines();
      switch (tool) {
        case 'read':
          await ReadStoryTool(store, seen).execute({'story_id': id});
        case 'grep':
          await GrepTool(store, seen).execute({
            'pattern': '线索',
            'story_ids': [id],
          });
        case 'search':
          await SearchTool(store, seen, embeddingClient: _Embedder()).run('线索');
        case 'gather':
          (await CoverageBuilder(store).build(['线索'])).register(seen);
        case 'sql':
          // Omitting kind must not bypass the source restriction.
          await SqlTool(store, seen).execute({
            'query':
                "SELECT story_id, line_index, content FROM story_lines WHERE story_id = '$id'",
          });
      }
      for (var i = 0; i < kinds.length; i++) {
        expect(seen.covers(id, i, i), isFalse, reason: '$tool: ${kinds[i]}');
      }
      expect(seen.covers(id, kinds.length, kinds.length), isTrue, reason: tool);
    }
  });

  test('a long citation must be checked beyond its first thousand lines', () {
    final seen = SeenLines()
      ..addRange('a.txt', 0, 999)
      ..add('a.txt', 1500);
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
