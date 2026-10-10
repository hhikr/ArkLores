import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:arklores/core/agent/lore_agent_loop.dart';
import 'package:arklores/core/agent/lore_agent_prompts.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/multi_game_retrieval.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;

import '../../support/gamedata_fixture.dart';
import '../../support/sqlite.dart';
import '../../support/temp_dir.dart';

/// R12 vector recall + reasoning-budget tests. The fake embedder is a
/// deterministic character histogram, so "semantic" similarity here means
/// shared characters — enough to verify plumbing, ranking and fallbacks.
void main() {
  group('chunking and quantization', () {
    test('chunkStory uses fixed windows anchored to line indexes', () {
      final lines = [
        for (var i = 0; i < 20; i++) ChunkLine(i, i.isEven ? 'A' : null, '第$i行'),
      ];
      final chunks = chunkStory('s.txt', 'activity:x', lines);
      expect(chunks.map((c) => '${c.lineStart}-${c.lineEnd}'), ['0-11', '8-19']);
      expect(chunks.first.chunkId, 's.txt#0-11');
      expect(chunks.first.text.split('\n').first, 'A：第0行');
      expect(chunks.first.text.split('\n')[1], '第1行');
    });

    test('a break line ends the windows: each part chunks as it would alone', () {
      final part = [for (var i = 0; i < 14; i++) ChunkLine(i, 'A', '第$i行')];
      final merged = [
        const ChunkLine(0, null, '通讯', isBreak: true),
        for (final l in part) ChunkLine(l.index + 1, l.speaker, l.content),
        const ChunkLine(15, null, '对话', isBreak: true),
        const ChunkLine(16, 'B', '另一段'),
      ];
      final chunks = chunkStory('m.txt', null, merged);
      expect(chunks.map((c) => '${c.lineStart}-${c.lineEnd}'), ['1-12', '9-14', '16-16']);
      // The same texts as the part alone: vectors cached by text carry over.
      expect(
        chunks.take(2).map((c) => c.text),
        chunkStory('p.txt', null, part).map((c) => c.text),
      );
      expect(chunks.map((c) => c.text).join(), isNot(contains('通讯')));
    });

    test('quantize keeps direction (cosine with original ~ 1)', () {
      const raw = [3.0, -4.0, 0.0, 1.0];
      final q = quantize(raw);
      final restored = [for (final v in q.values) v * q.scale];
      double dot(List<double> a, List<double> b) {
        var s = 0.0;
        for (var i = 0; i < a.length; i++) {
          s += a[i] * b[i];
        }
        return s;
      }

      final cosine = dot(restored, raw) /
          (math.sqrt(dot(restored, restored)) * math.sqrt(dot(raw, raw)));
      expect(cosine, closeTo(1.0, 0.001));
      expect(math.sqrt(dot(restored, restored)), closeTo(1.0, 0.01));
    });
  });

  group('vector index and hybrid FIND', () {
    late Directory tempDir;
    late String dbPath;

    setUpAll(useSqfliteFfi);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('arklores_vectors_test');
      dbPath = '${tempDir.path}/vectors.db';
      await _buildDb(dbPath, model: _FakeEmbedder.modelName);
    });

    tearDown(() => deleteTempDir(tempDir));

    test('index loads manifest info and ranks the matching chunk first',
        () async {
      final store = GameDataKnowledgeStore(dbPath: dbPath);
      final info = await store.storyVectorInfo;
      expect(info, (model: _FakeEmbedder.modelName, dims: _FakeEmbedder.dims));

      final query = (await _FakeEmbedder().embed(['藏匕首的人'])).single;
      final hits = await store.searchStoryChunksByVector(query, topK: 3);
      expect(hits.first.storyId, 'activities/x/level_x_02.txt');

      final scoped = await store.searchStoryChunksByVector(
        query,
        topK: 3,
        scopeId: 'activity:other',
      );
      expect(scoped.every((h) => h.scopeId == 'activity:other'), isTrue);
      await store.close();
    });

    test('the file loader (background isolate) reads what load() reads',
        () async {
      final fromFile = StoryVectorIndex.loadFile(dbPath)!;
      final db = await databaseFactoryFfi.openDatabase(dbPath);
      final fromDb = (await StoryVectorIndex.load(db))!;
      await db.close();
      expect(fromFile.length, fromDb.length);
      expect((fromFile.model, fromFile.dims), (fromDb.model, fromDb.dims));
      final query = (await _FakeEmbedder().embed(['藏匕首的人'])).single;
      String ranked(StoryVectorIndex i) => i
          .search(query, topK: 5)
          .map((h) => '${h.storyId}#${h.lineStart}:${h.score.toStringAsFixed(4)}')
          .join(',');
      expect(ranked(fromFile), ranked(fromDb));
    });

    // 0.14: search (which replaced FIND) on the same fixture.
    test('search finds by meaning without any keyword overlap; its lines are '
        'citable', () async {
      final seen = SeenLines();
      final result = await SearchTool(
        GameDataKnowledgeStore(dbPath: dbPath),
        seen,
        embeddingClient: _FakeEmbedder(),
      ).run('谁藏起了那把匕首呢');
      expect(result.mode, SearchMode.semantic);
      expect(result.text, contains('按意思检索'));
      expect(result.text, contains('level_x_02.txt'));
      expect(result.text, contains('意思相近'));
      expect(result.text, contains('当年我藏起了匕首。'));
      expect(seen.covers('activities/x/level_x_02.txt', 1, 1), isTrue);
    });

    // 0.14: the first searches are written by a call of its own and run by
    // code; they enter the conversation as search calls and results.
    test('the planned searches run before the first turn; a follow-up is '
        'planned with the question before it', () async {
      final store = GameDataKnowledgeStore(dbPath: dbPath);
      addTearDown(store.close);
      final llm = _Answers()
        ..plans.addAll([
          '好的。\n```json\n{"search": ["匕首 藏起", "夜里 安静"], "wiki": "匕首"}\n```',
          '{"search": "匕首 后来"}',
        ]);
      LoreConversation? saved;
      LoreAgentLoop agent() => LoreAgentLoop(
            client: llm,
            store: store,
            embeddingClient: _FakeEmbedder(),
          );
      final first = await agent()
          .run(query: '谁藏起了那把匕首呢', onConversation: (c) => saved = c)
          .toList();
      List<String> searches(List<ReActEvent> events) => [
            for (final e in events)
              if (e.type == ReActEventType.toolCall && e.toolName == 'search')
                '${e.toolArgs!['query']}',
          ];
      expect(searches(first), ['匕首 藏起', '夜里 安静']);
      final found = first
          .firstWhere((e) => e.type == ReActEventType.toolObservation)
          .content;
      expect(found, contains('按意思检索 + 关键词；关键词：匕首（1 行）'));
      expect(found, contains('level_x_02.txt'));
      expect(
        first.any((e) => e.content.contains('问答质量可能下降')),
        isFalse,
      );
      // The planning call sees the search tool's own description and the
      // question; the answering agent gets the question as asked, then the
      // searches as calls with their results.
      final plan = llm.planRequests.first;
      expect(plan.first.content, contains('一次检索所有资料'));
      expect(plan.last.content, '玩家的问题：谁藏起了那把匕首呢');
      final request = llm.requests.first;
      expect(
        request.map((m) => m.role).toList(),
        [
          MessageRole.system,
          MessageRole.user,
          MessageRole.assistant,
          MessageRole.tool,
          MessageRole.tool,
        ],
      );
      expect(request[1].content, '谁藏起了那把匕首呢');
      expect(request[2].toolCalls, hasLength(2));
      expect(request[3].content, contains('level_x_02.txt'));
      // "那后来呢" alone names nothing: the plan is written knowing the
      // question before it.
      final second =
          await agent().run(query: '那后来呢？', prior: saved).toList();
      expect(searches(second), ['匕首 后来']);
      expect(
        llm.planRequests.last.last.content,
        allOf(contains('上一问：谁藏起了那把匕首呢'), endsWith('玩家的问题：那后来呢？')),
      );
      // The first question's searches are folded in the follow-up.
      final later = llm.requests.last
          .where((m) => m.role == MessageRole.tool)
          .map((m) => m.content.startsWith('[已折叠]'))
          .toList();
      expect(later, [true, true, false]);
    });

    test('without a plan the question itself is searched by meaning',
        () async {
      final store = GameDataKnowledgeStore(dbPath: dbPath);
      addTearDown(store.close);
      final llm = _Answers();
      final events = await LoreAgentLoop(
        client: llm,
        store: store,
        embeddingClient: _FakeEmbedder(),
      ).run(query: '谁藏起了那把匕首呢').toList();
      final call = events.singleWhere((e) => e.type == ReActEventType.toolCall);
      expect(call.toolArgs, {'query': '谁藏起了那把匕首呢'});
      final found = events
          .singleWhere((e) => e.type == ReActEventType.toolObservation)
          .content;
      expect(found, contains('按意思检索'));
      expect(found, isNot(contains('关键词：')));
      expect(found, contains('level_x_02.txt'));
    });

    // 0.14 on the phone: a question about one game brought a third of its
    // search result from the other, because a common word of the query
    // occurs there too.
    test('a game whose passages are far and hold fewer of the words is '
        'left out, with its counts', () async {
      final ak = '${tempDir.path}/far_ak.db';
      final ef = '${tempDir.path}/far_ef.db';
      await _buildDb(ak, model: _FakeEmbedder.modelName, only: {
        'activities/x/level_x_02.txt': (
          'x',
          ['角色B：当年我藏起了匕首。', '角色B：匕首还藏在那里。'],
        ),
      },);
      await _buildDb(ef, model: _FakeEmbedder.modelName, only: {
        'ef/far_1.txt': (
          'm',
          ['商人们在很远的集市上叫卖各种水果蔬菜粮食和布料。', '旁人说起过一把匕首。'],
        ),
      },);
      final both = MultiGameRetrieval({
        Game.arknights: GameDataKnowledgeStore(dbPath: ak),
        Game.endfield: GameDataKnowledgeStore(dbPath: ef, game: Game.endfield),
      });
      addTearDown(() async {
        for (final s in both.stores.values) {
          await (s as GameDataKnowledgeStore).close();
        }
      });
      final spans = <String>[];
      final search = SearchTool(
        both,
        SeenLines(),
        embeddingClient: _FakeEmbedder(),
      )..onSpan = (name, _, __) => spans.add(name);
      final text = (await search.run('匕首 藏起')).text;
      expect(text, contains('## 明日方舟剧情（最相关的 1 篇）'));
      expect(text, contains('level_x_02.txt'));
      expect(text, contains('## 终末地剧情：只有意思较远的段落'));
      expect(text, contains('关键词命中 1 行、0 条资料），已略去'));
      expect(text, isNot(contains('ef/far_1.txt')));
      // Asked for by name it is searched.
      expect(
        (await search.run('匕首 藏起', game: Game.endfield)).text,
        contains('ef/far_1.txt'),
      );
      // Where a search spends its time is measured part by part.
      expect(
        spans.toSet(),
        containsAll([
          'search:embed',
          'search:vectors:arknights',
          'search:keywords:endfield',
          'search:records',
        ]),
      );
    });

    test('search falls back to keywords when the vectors are from another '
        'model, and says so', () async {
      final result = await SearchTool(
        GameDataKnowledgeStore(dbPath: dbPath),
        SeenLines(),
        embeddingClient: _FakeEmbedder(model: 'other-model'),
      ).run('匕首');
      expect(result.mode, SearchMode.keywordOnly);
      expect(result.modeNote, contains('库里的向量是'));
      expect(result.text, contains('L1 [角色B] 当年我藏起了匕首。'));
    });
  });
}
/// Answers every turn at once, without citations; records the requests.
/// The call that plans the first searches gets [plans] in turn (none left:
/// a reply that holds no plan).
class _Answers extends LLMClient {
  final List<List<Message>> requests = [];
  final List<List<Message>> planRequests = [];
  final List<String> plans = [];

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    if (messages.first.content.startsWith(loreSearchPlanRole)) {
      planRequests.add(List.of(messages));
      return planRequests.length <= plans.length
          ? plans[planRequests.length - 1]
          : '没有查到。';
    }
    requests.add(List.of(messages));
    return '没有查到。';
  }
}

/// Three stories; level_x_02 is about hiding a dagger. Or [only] these.
Future<void> _buildDb(
  String path, {
  required String model,
  Map<String, (String, List<String>)>? only,
}) async {
  final db = await createGameDataDb(
    path,
    vectors: true,
    manifest: {
      ...validManifest,
      manifestEmbeddingModel: model,
      manifestEmbeddingDims: '${_FakeEmbedder.dims}',
      manifestEmbeddingChunking: chunkingSignature,
    },
  );
  final stories = only ??
      const {
        'activities/x/level_x_01.txt': ('x', ['天气晴朗。', '大家在吃饭。']),
        'activities/x/level_x_02.txt': ('x', ['夜里很安静。', '角色B：当年我藏起了匕首。']),
        'activities/o/level_o_01.txt': ('other', ['商人在叫卖。', '城门打开了。']),
      };
  final embedder = _FakeEmbedder();
  for (final MapEntry(key: id, value: (scope, lines)) in stories.entries) {
    await insertStory(db, id, lines, scopeId: scope);
    final chunkLines = [
      for (final r in await db.query('story_lines',
          where: 'story_id = ?', whereArgs: [id], orderBy: 'line_index',))
        ChunkLine(r['line_index']! as int, r['speaker'] as String?,
            r['content']! as String,),
    ];
    for (final chunk in chunkStory(id, 'activity:$scope', chunkLines)) {
      final q = quantize((await embedder.embed([chunk.text])).single);
      await db.insert(storyChunkVectorsTable, {
        'chunk_id': chunk.chunkId,
        'story_id': chunk.storyId,
        'scope_id': chunk.scopeId,
        'line_start': chunk.lineStart,
        'line_end': chunk.lineEnd,
        'scale': q.scale,
        'vec': Uint8List.view(q.values.buffer),
      });
    }
  }
  await db.close();
}

/// Deterministic character-histogram embedder.
class _FakeEmbedder implements EmbeddingClient {
  _FakeEmbedder({this.model = modelName});
  static const String modelName = 'fake-embed';
  static const int dims = 64;

  @override
  final String model;

  @override
  int get dimensions => dims;

  @override
  int get tokensUsed => 0;

  @override
  Future<List<List<double>>> embed(List<String> texts) async => [
        for (final text in texts)
          () {
            final v = List<double>.filled(dims, 0);
            for (final rune in text.runes) {
              if (rune < 0x4e00) continue; // CJK only
              v[rune % dims] += 1;
            }
            return v;
          }(),
      ];
}

