import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arklores/core/agent/lore_agent_loop.dart';
import 'package:arklores/core/agent/lore_answer_json.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/multi_game_retrieval.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/materials/material_document.dart';
import 'package:arklores/core/materials/material_provider.dart';
import 'package:arklores/core/materials/material_store.dart';
import 'package:arklores/core/userdata/user_data_store.dart';
import 'package:arklores/features/ai/investigation_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

class _Embedding implements EmbeddingClient {
  final List<String> sent = [];
  @override
  String get model => 'fixture';
  @override
  int get dimensions => 2;
  @override
  int get tokensUsed => 0;
  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    sent.addAll(texts);
    return [
      for (final _ in texts) [1, 0],
    ];
  }
}

class _Script extends LLMClient {
  _Script(this.turns);
  final List<({String text, List<ToolCall> calls})> turns;
  int next = 0;
  @override
  Future<String> chat(List<Message> messages,
          {List<Map<String, dynamic>>? tools,
          double temperature = .7,
          int maxTokens = 2048,
          List<String>? stop,}) async =>
      throw UnimplementedError();
  @override
  Stream<CompletionDelta> streamTurn(List<Message> messages,
      {List<Map<String, dynamic>>? tools,
      String? toolChoice,
      double temperature = .7,
      int maxTokens = 2048,}) async* {
    final turn = turns[next++];
    if (turn.text.isNotEmpty) yield CompletionDelta(content: turn.text);
    yield CompletionDelta(done: true, toolCalls: turn.calls);
  }
}

void main() {
  test('existing notes migrate intact without enabling or embedding them',
      () async {
    final target =
        await MaterialStore.open(databaseFactoryFfi, inMemoryDatabasePath);
    try {
      final now = DateTime(2026, 10, 23);
      final note = UserMaterial(
          id: 'legacy',
          title: '旧笔记',
          body: List.filled(2000, '原文').join(),
          createdAt: now,
          updatedAt: now,);
      await target.synchronizePersonal([note]);
      final migrated = (await target.sources()).single;
      expect(migrated.id, 'personal/legacy');
      expect(migrated.enabled, isFalse);
      expect((await target.documents()).single.body, note.body);
      expect(await target.vectors(), isEmpty);
      await target
          .saveSource(migrated.copyWith(enabled: true, policy: '自定义说明'));
      await target.synchronizePersonal([note]);
      expect((await target.sources()).single.policy, '自定义说明');
      expect((await target.sources()).single.enabled, isTrue);
    } finally {
      await target.db.close();
    }
  });
  test('cancelled vector work remains pending and can resume', () async {
    final target =
        await MaterialStore.open(databaseFactoryFfi, inMemoryDatabasePath);
    try {
      await target.saveSource(
          const MaterialSource(id: 'sample', title: '资料', enabled: true),);
      await target.saveDocument(parseMaterial(
          id: 'sample/doc', sourceId: 'sample', title: '资料', body: '完整正文。',),);
      final client = _Embedding();
      await target.updateVectors('sample', client, cancelled: () => true);
      expect(client.sent, isEmpty);
      expect((await target.status('sample')).state, 'pending');
      await target.updateVectors('sample', client);
      expect(await target.pending('sample', client), 0);
    } finally {
      await target.db.close();
    }
  });
  setUpAll(useSqfliteFfi);
  late MaterialStore store;
  late Directory dir;
  late GameDataKnowledgeStore game;
  const source = MaterialSource(id: 'book', title: '地理资料', enabled: true);
  late MaterialDocument doc;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('materials_test');
    store = await MaterialStore.open(
        databaseFactoryFfi, '${dir.path}/materials.db',);
    await store.saveSource(source);
    doc = parseMaterial(
        id: 'book/chapter',
        sourceId: 'book',
        title: '城市',
        body:
            '# 城市\n\n${List.filled(1700, '甲').join()}\n\n## 机动平台\n\n星灯见到整座城市避开风暴。',);
    await store.saveDocument(doc);
    final db = await createGameDataDb('${dir.path}/game.db',
        catalog: true,
        vectors: true,
        manifest: {
          ...validManifest,
          manifestEmbeddingModel: 'fixture',
          manifestEmbeddingDims: '2',
          manifestEmbeddingChunking: chunkingSignature,
        },);
    await insertStory(db, 'a/story.txt', ['星灯：城镇移动以避开风暴。']);
    final q = quantize([1, 0]);
    await db.insert(storyChunkVectorsTable, {
      'chunk_id': 'a',
      'story_id': 'a/story.txt',
      'scope_id': 'a',
      'line_start': 0,
      'line_end': 0,
      'scale': q.scale,
      'vec': Uint8List.view(q.values.buffer),
    });
    await db.close();
    game = GameDataKnowledgeStore(dbPath: '${dir.path}/game.db');
  });
  tearDown(() async {
    await game.close();
    await store.db.close();
    await deleteTempDir(dir);
  });
  test('full text survives chunking; tail beyond old draft limit is searchable',
      () async {
    expect(doc.body.length, greaterThan(1700));
    expect(doc.blocks.map((b) => b.text).join(), contains('星灯见到整座城市避开风暴。'));
    final snapshot = await snapshotMaterials(store);
    final seen = SeenLines();
    final result = snapshot.render(snapshot.search('星灯'), seen.add);
    expect(result, contains('机动平台'));
    expect(result, contains('避开风暴'));
    expect(seen.isEmpty, isFalse);
    expect(snapshot.read(doc.pageId, doc.blocks.length - 1, 30, seen.add),
        contains('避开风暴'),);
  });
  test(
    'source selection applies to search, read and scoped SQL snapshots',
    () async {
      final before = await snapshotMaterials(store);
      await store.saveSource(source.copyWith(enabled: false));
      final after = await snapshotMaterials(store);
      expect(before.search('星灯'), isNotEmpty);
      expect(after.search('星灯'), isEmpty);
      expect(after.read(doc.pageId, 0, 2, (_, __) {}), contains('没有这份已启用资料'));
      expect(
          (await after.sql('SELECT * FROM material_documents')).rows, isEmpty,);
      expect(
          (await before.sql('SELECT title FROM material_documents'))
              .rows
              .single
              .single,
          '城市',);
      expect((await before.sql('SELECT * FROM versions')).error, isNotNull);
      expect((await before.sql('DELETE FROM material_documents')).error,
          isNotNull,);
      expect(
          (await before.sql(
                  'WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n) SELECT sum(x) FROM n',))
              .error,
          contains('中止'),);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );
  test(
      'incremental vectors reuse unchanged blocks and never bind old content to new text',
      () async {
    final client = _Embedding();
    await store.updateVectors('book', client);
    final initial = client.sent.length;
    expect(initial, greaterThan(1));
    await store.updateVectors('book', client);
    expect(client.sent.length, initial);
    final newer = parseMaterial(
        id: doc.id,
        sourceId: doc.sourceId,
        title: doc.title,
        body: doc.body.replaceAll('避开风暴', '避开地震'),);
    await store.saveDocument(newer);
    expect(await store.pending('book', client), 1);
    final snapshot = await snapshotMaterials(store);
    expect(snapshot.documents.single.version, isNot(doc.version));
    expect(
        snapshot.vectorAt(newer.pageId, newer.blocks.length - 1, 'fixture', 2),
        isNull,);
    await store.updateVectors('book', client);
    expect(client.sent.length, initial + 1);
    await store.deletePersonal('book');
    expect((await store.version(doc.pageId))!.body, doc.body);
    expect((await store.documents()), isEmpty);
  });
  test(
      'query vectors work without installed game databases and join the same search tool',
      () async {
    final client = _Embedding();
    await store.updateVectors('book', client);
    final snapshot = await snapshotMaterials(store);
    final empty = MultiGameRetrieval({
      Game.arknights: GameDataKnowledgeStore(dbPath: '${dir.path}/missing.db'),
    });
    final search = SearchTool(empty, SeenLines(),
        embeddingClient: client, materials: snapshot,);
    expect(await search.keywordOnlyReason(), isNull);
    final result = await search.run('大都市如何躲过自然灾害');
    expect(result.mode, SearchMode.semantic);
    expect(result.text, contains('material:book/chapter@'));
  });
  test(
      'search, grep, gather, SQL and near can combine game and material evidence',
      () async {
    final client = _Embedding();
    await store.updateVectors('book', client);
    final snapshot = await snapshotMaterials(store), seen = SeenLines();
    final games = MultiGameRetrieval({Game.arknights: game});
    final tools = {
      for (final t in loreTools(games, seen,
          embeddingClient: client, materials: snapshot,))
        t.name: t,
    };
    final search = await tools['search']!.execute({'query': '星灯'});
    expect(search, contains('a/story.txt'));
    expect(search, contains(doc.pageId));
    final grep = await tools['grep']!.execute({'pattern': '星灯'});
    expect(grep, contains(doc.pageId));
    expect(grep, contains('a/story.txt'));
    expect(
        await tools['gather']!.execute({
          'names': ['星灯'],
        }),
        contains(doc.pageId),);
    final sql = await tools['sql']!.execute({
      'source': 'materials',
      'query':
          'SELECT id,version,paragraph,content FROM material_blocks WHERE content LIKE \'%星灯%\'',
    });
    expect(sql, contains('避开风暴'));
    final near = await tools['search']!
        .execute({'near': '${doc.pageId}:${doc.blocks.length - 1}'});
    expect(near, contains('a/story.txt'));
    final reverse = await tools['search']!.execute({'near': 'a/story.txt:0'});
    expect(reverse, contains(doc.pageId));
  });
  test(
      'read citations, reject unread paragraphs and render material references',
      () async {
    final snapshot = await snapshotMaterials(store);
    Future<String> run(int paragraph) async {
      final answer = jsonEncode({
        'entries': [
          {
            'text': '城市能够移动。',
            'cite': [
              [doc.pageId, paragraph, paragraph],
            ],
          }
        ],
        'coverage': 'full',
      });
      final client = _Script([
        (
          text: '',
          calls: [
            ToolCall(
                id: 'read',
                name: 'read_material',
                arguments:
                    jsonEncode({'id': doc.pageId, 'start': 0, 'count': 1}),),
          ]
        ),
        (text: answer, calls: []),
        (text: answer, calls: []),
      ]);
      final events = await LoreAgentLoop(
              client: client,
              store: game,
              materials: snapshot,
              preSearch: false,)
          .run(query: '城市如何移动？')
          .toList();
      return events
          .where((e) => e.type == ReActEventType.finalAnswerReplace)
          .last
          .content;
    }

    final valid = await run(0);
    expect(valid, contains('${doc.pageId}:0'));
    final invalid = await run(999);
    expect(invalid, isNot(contains('${doc.pageId}:999')));
    final json = loreAnswerMarkdown(jsonEncode({
      'entries': [
        {
          'text': '资料说明',
          'cite': [
            [doc.pageId, 0, 1],
          ],
        }
      ],
    }),)!;
    expect(json, isNot(contains('.txt')));
    final blocks = splitAnswerBlocks(json);
    expect(blocks.single.materials.single.pageId, doc.pageId);
  });
  test(
      'author attribution uses confirmed metadata and keeps unknown annotations unknown',
      () {
    final d = parseMaterial(
        id: 'sample',
        sourceId: 'book',
        title: '小节',
        body: '学者的说法。\n\n补充说明。',
        regions: [
          {'text': '学者的说法。', 'kind': '正文'},
          {'text': '补充说明。', 'kind': '手写批注'},
        ],
        defaultAuthor: '甲作者',);
    expect(d.blocks.first.author, '甲作者');
    expect(d.blocks.last.author, isEmpty);
    expect(d.blocks.last.kind, '手写批注');
  });
  test('bundled package contains complete vectors and no working records',
      () async {
    final raw =
        gzip.decode(await File('assets/materials/terra.json.gz').readAsBytes());
    final package = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    expect((package['documents'] as List).length, 96);
    expect(package.keys.toSet(), {'format', 'source', 'documents', 'vectors'});
    await store.installPackage(package);
    final client = _Embedding();
    final chunks = await store.chunks('terra');
    final vectors = await store.vectors();
    final have = {
      for (final v in vectors)
        if (v.model == 'qwen3.7-text-embedding' && v.dims == 512) v.hash,
    };
    expect(chunks.every((c) => have.contains(c.hash)), isTrue);
    expect(client.sent, isEmpty);
    for (final d in package['documents'] as List) {
      expect((d as Map).keys.toSet(),
          {'id', 'source', 'title', 'body', 'order', 'blocks'},);
    }
  });
}
