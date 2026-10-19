import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/scene_cards.dart';
import 'live_support.dart' show readApiInfo;

/// Opt-in: writes scene cards (phase 3 P3, `scene_cards.dart`) for the
/// stories of every collection that holds a gold story of
/// `test/fixtures/recall_eval.json`, with the real model of `tools/api_info`,
/// then embeds them (`tools/embedding-apiKey.csv`). Both cost money: estimate
/// the tokens first (CLAUDE.md).
///
///   $env:ARKLORES_RUN_SCENE_CARDS='true'
///   $env:ARKLORES_GAMEDATA_DB="$PWD\build\gamedata_1008\arklores_gamedata_zh.db"
///   $env:ARKLORES_ENDFIELD_DB="$PWD\build\endfield\arklores_endfield_zh.db"
///   $env:ARKLORES_SCENE_CARDS_LIMIT='5'   # optional: only the first n stories
///   flutter test test/live/scene_cards_test.dart
///
/// Each card is kept in `build/scene_cards/cards/` (a run resumes where the
/// last stopped); vectors go to `build/scene_cards/vectors.json`.
void main() {
  final env = Platform.environment;
  final enabled = env['ARKLORES_RUN_SCENE_CARDS'] == 'true';
  final akPath = env['ARKLORES_GAMEDATA_DB'] ?? '';
  final efPath = env['ARKLORES_ENDFIELD_DB'] ?? '';
  final limit = int.tryParse(env['ARKLORES_SCENE_CARDS_LIMIT'] ?? '');
  final workers = int.tryParse(env['ARKLORES_SCENE_CARDS_WORKERS'] ?? '') ?? 3;

  setUpAll(sqfliteFfiInit);

  test(
    'scene cards for the gold collections',
    () async {
      final dbs = {
        Game.arknights: await databaseFactoryFfi.openDatabase(
          akPath,
          options: OpenDatabaseOptions(readOnly: true),
        ),
        if (efPath.isNotEmpty)
          Game.endfield: await databaseFactoryFfi.openDatabase(
            efPath,
            options: OpenDatabaseOptions(readOnly: true),
          ),
      };
      addTearDown(() async {
        for (final db in dbs.values) {
          await db.close();
        }
      });

      // The stories: every story of a collection that holds gold.
      final recall = jsonDecode(
        File('test/fixtures/recall_eval.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final gold = <String>{
        for (final c in (recall['cases'] as List).cast<Map<String, dynamic>>())
          for (final g in (c['gold'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
            if (g['story_id'] != null) '${g['story_id']}',
      };
      final stories = <({String id, String title})>[];
      for (final MapEntry(key: game, value: db) in dbs.entries) {
        final ids = [
          for (final s in gold)
            if (gameOfId(s) == game) s,
        ];
        if (ids.isEmpty) continue;
        final rows = await db.rawQuery(
          'SELECT story_id, collection_name, story_code, story_name '
          'FROM story_catalog WHERE collection_id IN ('
          'SELECT collection_id FROM story_catalog WHERE story_id IN '
          '(${List.filled(ids.length, '?').join(',')})) '
          'ORDER BY collection_id, story_sort',
          ids,
        );
        for (final r in rows) {
          stories.add((
            id: '${r['story_id']}',
            title: [
              r['collection_name'],
              r['story_code'],
              r['story_name'],
            ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
          ),);
        }
      }
      final todo = limit == null ? stories : stories.take(limit).toList();

      final out = Directory('build/scene_cards/cards')
        ..createSync(recursive: true);
      File fileOf(String id) => File(
            '${out.path}/${id.replaceAll(RegExp(r'[^\w\-.]'), '_')}.json',
          );

      var prompt = 0;
      var completion = 0;
      var calls = 0;
      var failed = 0;
      final client = OpenAICompatibleClient(
        config: readApiInfo(File('tools/api_info')),
        onCompletion: (r) {
          calls++;
          prompt += r.promptTokens ?? 0;
          completion += r.completionTokens ?? 0;
        },
      );
      var next = 0;
      var done = 0;
      Future<void> worker() async {
        while (next < todo.length) {
          final story = todo[next++];
          final file = fileOf(story.id);
          if (file.existsSync()) {
            done++;
            continue;
          }
          final db = dbs[gameOfId(story.id)]!;
          final rows = await db.rawQuery(
            'SELECT line_index, speaker, content FROM story_lines '
            'WHERE story_id = ? ORDER BY line_index',
            [story.id],
          );
          final lines = [
            for (final r in rows)
              (
                line: r['line_index'] as int,
                speaker: '${r['speaker'] ?? ''}',
                content: '${r['content'] ?? ''}',
              ),
          ];
          SceneCard? card;
          for (var attempt = 0; attempt < 2 && card == null; attempt++) {
            try {
              final reply = await client.chatCompletion(
                [
                  Message.system(sceneCardPrompt),
                  Message.user(
                    '《${story.title}》\n${sceneCardStoryText(lines)}',
                  ),
                ],
                temperature: 0.2,
                maxTokens: 4096,
              );
              card = parseSceneCard(
                reply.content,
                storyId: story.id,
                title: story.title,
                lines: lines,
              );
            } on LLMException catch (e) {
              // ignore: avoid_print
              print('${story.id}: $e');
            }
          }
          done++;
          if (card == null) {
            failed++;
            continue;
          }
          file.writeAsStringSync(
            const JsonEncoder.withIndent(' ').convert(card.toJson()),
          );
          if (done % 10 == 0) {
            // ignore: avoid_print
            print('$done/${todo.length}：$calls 次调用，prompt $prompt，'
                'completion $completion');
          }
        }
      }

      await Future.wait([for (var i = 0; i < workers; i++) worker()]);
      // ignore: avoid_print
      print('卡片：${todo.length} 篇，失败 $failed；$calls 次调用，'
          'prompt $prompt，completion $completion');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      File('build/scene_cards/usage_$stamp.json').writeAsStringSync(
        jsonEncode({
          'stories': todo.length,
          'failed': failed,
          'calls': calls,
          'prompt_tokens': prompt,
          'completion_tokens': completion,
        }),
      );

      await _embedCards([
        for (final s in todo)
          if (fileOf(s.id).existsSync())
            SceneCard.fromJson(
              jsonDecode(fileOf(s.id).readAsStringSync())
                  as Map<String, dynamic>,
            ),
      ]);
    },
    skip: !enabled || akPath.isEmpty
        ? 'set ARKLORES_RUN_SCENE_CARDS=true and ARKLORES_GAMEDATA_DB'
        : false,
    timeout: const Timeout(Duration(hours: 3)),
  );
}

/// Embeds the cards `build/scene_cards/vectors.json` has no vector for
/// (by story id; a card whose text changed is embedded again).
Future<void> _embedCards(List<SceneCard> cards) async {
  final values = <String, String>{};
  for (final line in File('tools/embedding-apiKey.csv').readAsLinesSync()) {
    final i = line.indexOf(',');
    if (i > 0) {
      values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
  }
  final config = defaultEmbeddingConfig.copyWith(
    baseUrl: values['openAiCompatible'],
    apiKey: values['apiKey'],
  );
  final file = File('build/scene_cards/vectors.json');
  final json = file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  final vectors = (json['vectors'] as Map<String, dynamic>?) ?? {};
  final texts = (json['texts'] as Map<String, dynamic>?) ?? {};
  final missing = [
    for (final c in cards)
      if (!vectors.containsKey(c.storyId) ||
          texts[c.storyId] != c.embeddingText)
        c,
  ];
  final client = OpenAICompatibleEmbeddingClient(config: config);
  for (var i = 0; i < missing.length; i += 10) {
    final batch = missing.skip(i).take(10).toList();
    final got = await client.embed([for (final c in batch) c.embeddingText]);
    for (final (k, c) in batch.indexed) {
      vectors[c.storyId] = got[k];
      texts[c.storyId] = c.embeddingText;
    }
  }
  file.writeAsStringSync(
    jsonEncode({
      'model': config.model,
      'dims': config.dimensions,
      'vectors': vectors,
      'texts': texts,
    }),
  );
  // ignore: avoid_print
  print('向量：新算 ${missing.length} 张（${client.tokensUsed} token），'
      '共 ${vectors.length} 张');
}
