import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:arklores/core/agent/tools/agent_tool.dart';
import 'package:arklores/core/agent/tools/search_story_lines.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:arklores/core/llm/completion_budget.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/temp_dir.dart';

/// R12 vector recall + reasoning-budget tests. The fake embedder is a
/// deterministic character histogram, so "semantic" similarity here means
/// shared characters — enough to verify plumbing, ranking and fallbacks.
void main() {
  group('completeWithHeadroom', () {
    test('retries an empty truncated reply with a larger ceiling', () async {
      final llm = _BudgetLLM(emptyBelow: 2000);
      final result = await completeWithHeadroom(
        llm,
        [Message.user('q')],
        temperature: 0,
        maxTokens: 1024,
      );
      expect(result.content, 'DONE');
      expect(llm.budgets, [1024, 4096]);
    });

    test('does not retry a complete reply', () async {
      final llm = _BudgetLLM(emptyBelow: 0);
      await completeWithHeadroom(
        llm,
        [Message.user('q')],
        temperature: 0,
        maxTokens: 1024,
      );
      expect(llm.budgets, [1024]);
    });
  });

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

    setUpAll(() {
      sqfliteFfiInit();
      sqflite.databaseFactory = databaseFactoryFfi;
    });

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

    test('FIND fuses semantic hits even without keyword overlap', () async {
      final tool = SearchStoryLinesTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
        embeddingClient: _FakeEmbedder(),
      );
      // No line contains this exact phrase -> keyword leg is empty.
      final result =
          await tool.execute({'query': '谁藏起了那把匕首呢'}) as ToolExecutionResult;
      expect(result.observation, contains('semantic + keyword'));
      expect(result.observation, contains('level_x_02.txt'));
      expect(result.observation, contains('(semantic '));
      // No literal hit anywhere -> stated plainly, per story too.
      expect(result.observation, contains('没有任何一行包含这些词'));
      expect(result.observation, contains('无字面命中'));
    });

    test('FIND falls back to keyword when the model does not match', () async {
      final tool = SearchStoryLinesTool(
        gameDataStore: GameDataKnowledgeStore(dbPath: dbPath),
        embeddingClient: _FakeEmbedder(model: 'other-model'),
      );
      final result =
          await tool.execute({'query': '匕首'}) as ToolExecutionResult;
      expect(result.observation, contains('keyword only: vectors are'));
      expect(result.observation, contains('L1: 角色B：当年我藏起了匕首。'));
      expect(result.observation, isNot(contains('没有任何一行包含这些词')));
    });
  });
}

/// Three stories; level_x_02 is about hiding a dagger.
Future<void> _buildDb(String path, {required String model}) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  await db.execute(
    'CREATE TABLE story_lines (story_id TEXT, line_index INTEGER, '
    'speaker TEXT, content TEXT)',
  );
  await db.execute(
    'CREATE TABLE story_scopes (story_id TEXT, scope_type TEXT, scope_id TEXT)',
  );
  await db.execute('CREATE TABLE gamedata_manifest (key TEXT PRIMARY KEY, value TEXT)');
  await db.execute(storyChunkVectorsDdl);
  const stories = {
    'activities/x/level_x_01.txt': ('activity', 'x', ['天气晴朗。', '大家在吃饭。']),
    'activities/x/level_x_02.txt': ('activity', 'x', ['夜里很安静。', '当年我藏起了匕首。']),
    'activities/o/level_o_01.txt': ('activity', 'other', ['商人在叫卖。', '城门打开了。']),
  };
  final embedder = _FakeEmbedder();
  for (final entry in stories.entries) {
    final (type, value, lines) = entry.value;
    await db.insert('story_scopes', {
      'story_id': entry.key,
      'scope_type': type,
      'scope_id': value,
    });
    final chunkLines = <ChunkLine>[];
    for (var i = 0; i < lines.length; i++) {
      final speaker = lines[i].contains('匕首') ? '角色B' : null;
      await db.insert('story_lines', {
        'story_id': entry.key,
        'line_index': i,
        'speaker': speaker,
        'content': lines[i],
      });
      chunkLines.add(ChunkLine(i, speaker, lines[i]));
    }
    for (final chunk in chunkStory(entry.key, '$type:$value', chunkLines)) {
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
  for (final kv in {
    manifestEmbeddingModel: model,
    manifestEmbeddingDims: '${_FakeEmbedder.dims}',
    manifestEmbeddingChunking: chunkingSignature,
  }.entries) {
    await db.insert('gamedata_manifest', {'key': kv.key, 'value': kv.value});
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

/// Returns empty+length below [emptyBelow] tokens, 'DONE' otherwise.
class _BudgetLLM extends LLMClient {
  _BudgetLLM({required this.emptyBelow});
  final int emptyBelow;
  final List<int> budgets = [];

  @override
  Future<ChatCompletionResult> chatCompletion(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async {
    budgets.add(maxTokens);
    return maxTokens < emptyBelow
        ? const ChatCompletionResult(content: '', finishReason: 'length')
        : const ChatCompletionResult(content: 'DONE', finishReason: 'stop');
  }

  @override
  Future<String> chat(
    List<Message> messages, {
    List<Map<String, dynamic>>? tools,
    double temperature = 0.7,
    int maxTokens = 2048,
    List<String>? stop,
  }) async =>
      (await chatCompletion(messages, maxTokens: maxTokens)).content;
}
