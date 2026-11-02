import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/lore_agent_loop.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/multi_game_retrieval.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/materials/material_provider.dart'
    show snapshotMaterials;
import 'package:arklores/core/materials/material_snapshot.dart';
import 'package:arklores/core/materials/material_store.dart';
import 'package:arklores/core/wiki/wiki_lookup.dart';
import 'package:arklores/core/wiki/wiki_page.dart';
import 'package:arklores/core/wiki/wiki_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;

import '../support/sqlite.dart';
import '../support/temp_dir.dart';
import '../support/token_replay.dart';

void main() {
  final env = Platform.environment;
  test(
    'replay recorded tool calls through the production loop',
    () async {
      useSqfliteFfi();
      final sessionPath = env['ARKLORES_REPLAY_SESSION'] ?? '';
      expect(
        p.isAbsolute(sessionPath),
        isTrue,
        reason: 'ARKLORES_REPLAY_SESSION',
      );
      final session = jsonDecode(File(sessionPath).readAsStringSync())
          as Map<String, dynamic>;
      final saved = session['lore_conversation'] as Map<String, dynamic>;
      final messages = [
        for (final m in saved['messages'] as List)
          Message.fromJson(m as Map<String, dynamic>),
      ];
      final wikiEnabled = env['ARKLORES_REPLAY_WIKI'] == 'true';
      final merge = env['ARKLORES_REPLAY_MERGE_READS'] == 'true';
      final materialsEnabled = env['ARKLORES_REPLAY_MATERIALS'] != 'false';
      final materials = materialsEnabled ? await _loadBuiltinMaterials() : null;
      if (materials != null) {
        expect(materials.sources, hasLength(1));
        expect(materials.sources.single.builtin, isTrue);
        expect(materials.documents, isNotEmpty);
        expect(materials.vectors, isNotEmpty);
      }
      final originalScript = replayScript(messages, wiki: wikiEnabled);
      final script = merge ? mergeReplayReads(originalScript) : originalScript;
      final requests = <Map<String, Object?>>[];
      final planner = ReplayLLM(
        [
          Message.assistant(
            jsonEncode(replayPlan(messages, wiki: wikiEnabled)),
          ),
        ],
        phase: 'planner',
        requests: requests,
      );
      final model = ReplayLLM(script, phase: 'main', requests: requests);
      final stores = <Game, GameDataKnowledgeStore>{};
      for (final (game, key) in [
        (Game.arknights, 'ARKLORES_GAMEDATA_DB'),
        (Game.endfield, 'ARKLORES_ENDFIELD_DB'),
      ]) {
        final path = env[key] ?? '';
        if (game == Game.endfield && path.isEmpty) continue;
        expect(
          p.isAbsolute(path) && File(path).existsSync(),
          isTrue,
          reason: key,
        );
        final store = GameDataKnowledgeStore(dbPath: path, game: game);
        stores[game] = store;
        addTearDown(store.close);
      }
      final embedding = await _ReplayEmbedding.load();
      if (embedding != null) addTearDown(embedding.dispose);
      final httpClient = http.Client();
      addTearDown(httpClient.close);
      final wiki = !wikiEnabled
          ? null
          : WikiLookup(
              sources: {
                WikiSite.prts: PrtsWikiSource(httpClient),
                WikiSite.warfarin: WarfarinWikiSource(httpClient),
              },
            );
      final tools = <Map<String, Object?>>[];
      final notes = <String>[];
      LoreConversation? result;
      String? failure;
      var activeRequest = 0;
      final pending = <Map<String, Object?>>[];
      try {
        await for (final event in LoreAgentLoop(
          client: model,
          planClient: planner,
          store: MultiGameRetrieval(stores),
          embeddingClient: embedding,
          materials: materials,
          wiki: wiki,
        ).run(
          query: '${saved['question']}',
          onConversation: (c) => result = c,
        )) {
          if (event.type == ReActEventType.toolCall) {
            activeRequest = requests.length;
            final row = <String, Object?>{
              'request_index': activeRequest,
              'tool': event.toolName,
              'arguments': event.toolArgs,
              'planned': event.planned,
              'blocked': event.inContext,
            };
            tools.add(row);
            pending.add(row);
          } else if (event.type == ReActEventType.toolObservation) {
            final index =
                pending.indexWhere((r) => r['tool'] == event.toolName);
            if (index < 0) throw StateError('observation without call');
            final row = pending.removeAt(index);
            row['result_chars'] = replayChars(event.content);
            row['result'] = event.content;
            row['blocked'] = row['blocked'] == true ||
                event.content.startsWith(inContextPrefix);
            row['error'] = event.content.startsWith('错误：');
          } else if (event.type == ReActEventType.recordNote ||
              event.type == ReActEventType.error) {
            notes.add(event.content);
          }
        }
      } catch (e) {
        failure = '$e';
      }
      final ratio = (saved['last_prompt_tokens'] as num) /
          (saved['last_prompt_chars'] as num);
      final total = requests.fold(0, (n, r) => n + (r['total_chars'] as int));
      final usage = ((session['turns'] as List).first
          as Map<String, dynamic>)['usage'] as Map<String, dynamic>;
      final byTool = <String, int>{};
      for (final t in tools) {
        byTool.update(
          '${t['tool']}',
          (n) => n + (t['result_chars'] as int? ?? 0),
          ifAbsent: () => t['result_chars'] as int? ?? 0,
        );
      }
      final firstBatchSearchChars = tools
          .where((t) => t['planned'] == true && t['tool'] == 'search')
          .fold<int>(0, (sum, t) => sum + (t['result_chars'] as int? ?? 0));
      final sourceExplanation =
          materials?.sources.map((s) => s.policy).firstOrNull ?? '';
      final sourceExplanationOccurrences = sourceExplanation.isEmpty
          ? 0
          : tools.fold<int>(
              0,
              (sum, t) =>
                  sum + _occurrences('${t['result'] ?? ''}', sourceExplanation),
            );
      final table =
          StringBuffer('| 请求 | 阶段 | 系统 | 工具说明 | 对话 | 消息数 | 工具与结果字数（* 已拦下） |\n'
              '| --- | --- | --- | --- | --- | --- | --- |\n');
      for (final r in requests) {
        table.writeln(
            '| ${r['index']} | ${r['phase']} | ${r['system_chars']} | '
            '${r['tool_schema_chars']} | ${r['dialogue_chars']} | ${r['message_count']} | '
            '${tools.where((t) => t['request_index'] == r['index']).map((t) => "${t['tool']}:${t['result_chars']}${t['blocked'] == true ? '*' : ''}").join(', ')} |');
      }
      final report = <String, Object?>{
        'session': sessionPath,
        'wiki': wikiEnabled,
        'merge_reads': merge,
        'materials': materials == null
            ? {
                'enabled': false,
                'scope': '已关闭（ARKLORES_REPLAY_MATERIALS=false）',
                'personal_imports': '未加载用户导入资料',
              }
            : {
                'enabled': true,
                'scope': '只有预置资料',
                'personal_imports': '未加载用户导入资料；未调用 synchronizePersonal',
                'source_ids': materials.sources.map((s) => s.id).toList(),
                'document_count': materials.documents.length,
                'vector_count': materials.vectors.length,
                'vector_model': materials.vectors.firstOrNull?.model,
                'vector_dimensions': materials.vectors.firstOrNull?.dims,
              },
        'first_batch_search_result_chars': firstBatchSearchChars,
        'source_explanation': {
          'occurrences_in_tool_results': sourceExplanationOccurrences,
          'chars_each': replayChars(sourceExplanation),
          'chars_total':
              replayChars(sourceExplanation) * sourceExplanationOccurrences,
        },
        'databases': {
          for (final g in stores.keys)
            g.name: env[g == Game.arknights
                ? 'ARKLORES_GAMEDATA_DB'
                : 'ARKLORES_ENDFIELD_DB'],
        },
        'embedding_mode': embedding == null
            ? 'keyword_only_no_key_or_cache'
            : 'cached_vectors',
        'embedding_tokens_billed': embedding?.tokensUsed ?? 0,
        'embedding_queries': embedding?.queries.toList() ?? [],
        'requests': requests,
        'tools': tools,
        'result_chars_by_tool': byTool,
        'totals': {
          'requests': requests.length,
          'chars': total,
          'token_per_char': ratio,
          'estimated_prompt_tokens': (total * ratio).round(),
          'recorded_prompt_tokens': usage['prompt_tokens'],
          'difference_ratio':
              total * ratio / (usage['prompt_tokens'] as num) - 1,
        },
        'duplicates': replayDuplicates([
          for (final t in tools) Message.toolResult('', '${t['result'] ?? ''}'),
        ]),
        'recorded_duplicates': replayDuplicates(messages),
        'script_messages_original': originalScript.length,
        'script_messages_replayed': model.next,
        'recorded_main_requests': (usage['llm_calls'] as int) - 1,
        'request_count_difference':
            requests.length - (usage['llm_calls'] as int),
        'planned_calls': [
          for (final t in tools)
            if (t['planned'] == true)
              {'tool': t['tool'], 'arguments': t['arguments']},
        ],
        'seen': result?.seen.toJson(),
        'notes': notes,
        'failure': failure,
        'conversation_saved': result != null,
        'table': table.toString(),
      };
      final out = File(
        env['ARKLORES_REPLAY_OUT'] ??
            'build/token_replay/${p.basenameWithoutExtension(sessionPath)}.${DateTime.now().millisecondsSinceEpoch}.json',
      );
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      // ignore: avoid_print
      print(
        '${table}Totals: ${jsonEncode(report['totals'])}\nResults: $byTool\nReport: ${out.absolute.path}',
      );
      expect(failure, isNull);
      expect(model.next, script.length);
      expect(
        requests.where((r) => r['phase'] == 'main'),
        hasLength(script.length),
      );
      expect(result, isNotNull);
    },
    skip: env['ARKLORES_RUN_TOKEN_REPLAY'] != 'true',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<MaterialSnapshot> _loadBuiltinMaterials() async {
  final tempDir =
      await Directory.systemTemp.createTemp('token_replay_materials');
  MaterialStore? store;
  try {
    store = await MaterialStore.open(
      databaseFactoryFfi,
      p.join(tempDir.path, 'materials.db'),
    );
    final bytes = await File('assets/materials/terra.json.gz').readAsBytes();
    final package =
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    await store.installPackage(package);
    return await snapshotMaterials(store);
  } finally {
    try {
      await store?.db.close();
    } finally {
      await deleteTempDir(tempDir);
    }
  }
}

int _occurrences(String text, String value) {
  if (value.isEmpty) return 0;
  var count = 0;
  var start = 0;
  while (true) {
    final index = text.indexOf(value, start);
    if (index < 0) return count;
    count++;
    start = index + value.length;
  }
}

/// Cache misses use only the embedding endpoint; no chat client is constructed.
class _ReplayEmbedding implements EmbeddingClient {
  _ReplayEmbedding(this.vectors, this.client);
  final Map<String, dynamic> vectors;
  final OpenAICompatibleEmbeddingClient? client;
  final queries = <String>{};
  static final file = File('build/token_replay/query_vectors.json');
  static Future<_ReplayEmbedding?> load() async {
    final values = <String, String>{};
    final csv = File('tools/embedding-apiKey.csv');
    if (csv.existsSync()) {
      for (final line in csv.readAsLinesSync()) {
        final at = line.indexOf(',');
        if (at > 0) {
          values[line.substring(0, at).trim()] = line.substring(at + 1).trim();
        }
      }
    }
    final config = defaultEmbeddingConfig.copyWith(
      baseUrl: values['openAiCompatible'],
      apiKey: values['apiKey'],
    );
    final cache = file.existsSync()
        ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
    if (cache.isNotEmpty &&
        (cache['model'] != config.model ||
            cache['dims'] != config.dimensions)) {
      throw StateError('Replay vector cache model/dimensions mismatch');
    }
    if (!config.isValid && cache.isEmpty) return null;
    return _ReplayEmbedding(
      Map<String, dynamic>.from(cache['vectors'] as Map? ?? {}),
      config.isValid ? OpenAICompatibleEmbeddingClient(config: config) : null,
    );
  }

  @override
  String get model => defaultEmbeddingConfig.model;
  @override
  int get dimensions => defaultEmbeddingConfig.dimensions;
  @override
  int get tokensUsed => client?.tokensUsed ?? 0;
  void dispose() => client?.dispose();
  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    queries.addAll(texts);
    final missing =
        texts.where((t) => !vectors.containsKey(t)).toSet().toList();
    if (missing.isNotEmpty) {
      if (client == null) throw StateError('Missing replay query vector');
      final got = await client!.embed(missing);
      for (final (i, q) in missing.indexed) {
        vectors[q] = got[i];
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({'model': model, 'dims': dimensions, 'vectors': vectors}),
      );
    }
    return [
      for (final t in texts)
        [for (final x in vectors[t] as List) (x as num).toDouble()],
    ];
  }
}
