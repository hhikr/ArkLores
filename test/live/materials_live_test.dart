import 'dart:convert';
import 'dart:io';
import 'package:arklores/core/agent/lore_agent_loop.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/multi_game_retrieval.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:arklores/core/materials/material_provider.dart';
import 'package:arklores/core/materials/material_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../support/sqlite.dart';
import 'ask_pipeline_live_test.dart' show readEmbeddingCsv;
import 'live_support.dart' show readApiInfo;

void main() {
  final enabled = Platform.environment['ARKLORES_RUN_MATERIALS'] == 'true';
  test(
    'real semantic recall and cross-source answers',
    () async {
      useSqfliteFfi();
      final root =
          Platform.environment['ARKLORES_MATERIALS_SOURCE_ROOT'] ?? '.';
      final api = readApiInfo(File('$root/tools/api_info'))
          .copyWith(chatModel: 'glm-5.3-flash');
      final config = readEmbeddingCsv(File('$root/tools/embedding-apiKey.csv'));
      expect(api.isValid, isTrue);
      expect(config.isValid, isTrue);
      final embed = OpenAICompatibleEmbeddingClient(config: config);
      final client = OpenAICompatibleClient(config: api);
      final store =
          await MaterialStore.open(databaseFactoryFfi, inMemoryDatabasePath);
      final raw = jsonDecode(utf8.decode(gzip.decode(
              await File('assets/materials/terra.json.gz').readAsBytes(),),),)
          as Map<String, dynamic>;
      await store.installPackage(raw);
      final snapshot = await snapshotMaterials(store);
      final ark = GameDataKnowledgeStore(
          dbPath: '$root/build/gamedata_rebuild/arklores_gamedata_zh.db',);
      final endfield = GameDataKnowledgeStore(
          dbPath: '$root/build/endfield/arklores_endfield_zh.db',
          game: Game.endfield,);
      final games =
          MultiGameRetrieval({Game.arknights: ark, Game.endfield: endfield});
      final reports = <Map<String, Object?>>[];
      try {
        for (final item in [
          (query: '那种晶体为什么在受灾后反而越来越多？', gold: '自然增长'),
          (query: '同样的电子设备为何在各国普及情况悬殊？', gold: '源石电子'),
        ]) {
          final v = (await embed.embed([item.query])).single;
          final hits = snapshot.search('',
              vector: v, model: embed.model, dims: embed.dimensions, limit: 8,);
          final texts = hits.map((h) => h.chunk.text).join('\n');
          reports.add({
            'query': item.query,
            'gold': item.gold,
            'hits': hits
                .map((h) => {
                      'document': h.chunk.document.title,
                      'start': h.chunk.start,
                      'end': h.chunk.end,
                      'text': h.chunk.text,
                    },)
                .toList(),
          });
          expect(texts, contains(item.gold));
        }
        final shared = await SearchTool(games, SeenLines(),
                embeddingClient: embed, materials: snapshot,)
            .run('源石 自然增长');
        expect(shared.text, contains('material:'));
        expect(shared.text, contains('.txt'));
        const question = '请结合《大地巡旅》和游戏原文，说明源石自然增长是什么，以及这些记述有哪些认识局限。分清原文记述与推测。';
        final events = await LoreAgentLoop(
                client: client,
                planClient: client,
                store: games,
                embeddingClient: embed,
                materials: snapshot,
                )
            .run(query: question)
            .toList();
        final answers = events
            .where((e) => e.type == ReActEventType.finalAnswerReplace)
            .toList();
        expect(answers, isNotEmpty,
            reason: events.map((e) => '${e.type}: ${e.content}').join('\n'),);
        final answer = answers.last.content;
        reports.add({
          'question': question,
          'answer': answer,
          'steps': events
              .where((e) =>
                  e.type == ReActEventType.toolObservation ||
                  e.type == ReActEventType.recordNote,)
              .map((e) => {'type': e.type.name, 'content': e.content})
              .toList(),
        });
        await Directory('build/materials').create(recursive: true);
        await File('build/materials/live-evaluation.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
        expect(answer, contains('material:'));
        expect(answer, contains('.txt:'));
      } finally {
        await store.db.close();
        await ark.close();
        await endfield.close();
        embed.dispose();
        client.dispose();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
