import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/story_vectors.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/chunk_prefix.dart';
import '../support/scene_cards.dart' show cosineSimilarity;
import 'live_support.dart' show readApiInfo;

/// Opt-in experiment for phase 5 P6 (`chunk_prefix.dart`): the stories of
/// every collection holding gold of the chosen cases of
/// `test/fixtures/recall_eval.json` get a model-written sentence a chunk,
/// their chunks are embedded again with it, and
/// - copies of both libraries with those vectors replaced are written to
///   `build/chunk_prefix/` (run `recall_eval_test.dart` against them);
/// - the gold chunks' ranks among the same chunks, old vectors against new,
///   go to `build/chunk_prefix/ab.md`.
/// Writing the sentences and the vectors costs money: estimate first.
///
///   $env:ARKLORES_RUN_CHUNK_PREFIX='true'
///   $env:ARKLORES_GAMEDATA_DB="$PWD\build\gamedata_1008\arklores_gamedata_zh.db"
///   $env:ARKLORES_ENDFIELD_DB="$PWD\build\endfield\arklores_endfield_zh.db"
///   $env:ARKLORES_CHUNK_PREFIX_CASES='zhenlong,yan_infected'   # default: below
///   $env:ARKLORES_CHUNK_PREFIX_LIMIT='3'                       # first n stories
///   flutter test test/live/chunk_prefix_test.dart
void main() {
  final env = Platform.environment;
  final enabled = env['ARKLORES_RUN_CHUNK_PREFIX'] == 'true';
  final akPath = env['ARKLORES_GAMEDATA_DB'] ?? '';
  final efPath = env['ARKLORES_ENDFIELD_DB'] ?? '';
  final limit = int.tryParse(env['ARKLORES_CHUNK_PREFIX_LIMIT'] ?? '');
  final workers = int.tryParse(env['ARKLORES_CHUNK_PREFIX_WORKERS'] ?? '') ?? 3;
  // The cases no searching by name reaches (refactor plan, phase 3).
  final caseIds = (env['ARKLORES_CHUNK_PREFIX_CASES'] ??
          'zhenlong,yan_infected,yan_infected_wei,longmen_yan,amiya_cautus,'
              'perlica_admin,island_purge')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  const out = 'build/chunk_prefix';

  setUpAll(sqfliteFfiInit);

  test(
    'chunk prefixes for the gold collections',
    () async {
      final paths = {
        Game.arknights: akPath,
        if (efPath.isNotEmpty) Game.endfield: efPath,
      };
      final dbs = {
        for (final MapEntry(:key, :value) in paths.entries)
          key: await databaseFactoryFfi.openDatabase(
            value,
            options: OpenDatabaseOptions(readOnly: true),
          ),
      };
      addTearDown(() async {
        for (final db in dbs.values) {
          await db.close();
        }
      });

      final recall = jsonDecode(
        File('test/fixtures/recall_eval.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final cases = [
        for (final c in (recall['cases'] as List).cast<Map<String, dynamic>>())
          if (caseIds.contains(c['id'])) c,
      ];
      final gold = <String>{
        for (final c in cases)
          for (final g in (c['gold'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
            if (g['story_id'] != null) '${g['story_id']}',
      };

      // The stories, their lines and their chunks as the library has them.
      final stories = <_Story>[];
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
          final id = '${r['story_id']}';
          final lines = [
            for (final l in await db.rawQuery(
              'SELECT line_index, speaker, content, kind FROM story_lines '
              'WHERE story_id = ? ORDER BY line_index',
              [id],
            ))
              if (l['kind'] != 'system' && l['kind'] != sectionLineKind)
                (
                  line: l['line_index'] as int,
                  speaker: '${l['speaker'] ?? ''}',
                  content: '${l['content'] ?? ''}',
                ),
          ];
          final chunks = [
            for (final c in await db.rawQuery(
              'SELECT line_start, line_end FROM $storyChunkVectorsTable '
              'WHERE story_id = ? ORDER BY line_start',
              [id],
            ))
              (c['line_start'] as int, c['line_end'] as int),
          ];
          stories.add(
            _Story(
              id,
              [r['collection_name'], r['story_code'], r['story_name']]
                  .where((v) => v != null && '$v'.isNotEmpty)
                  .join(' · '),
              lines,
              chunks,
            ),
          );
        }
      }
      final todo = limit == null ? stories : stories.take(limit).toList();
      // ignore: avoid_print
      print('${todo.length} 篇，'
          '${todo.fold(0, (n, s) => n + s.chunks.length)} 块');

      // 1. The sentences, one call a story (a second for what it left out).
      Directory('$out/prefixes').createSync(recursive: true);
      var calls = 0;
      var prompt = 0;
      var completion = 0;
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
      var missingSentences = 0;
      Future<void> worker() async {
        while (next < todo.length) {
          final story = todo[next++];
          final file = story.prefixFile(out);
          if (file.existsSync() || story.chunks.isEmpty) {
            done++;
            continue;
          }
          final got = <String, String>{};
          for (var attempt = 0; attempt < 2; attempt++) {
            final left = [
              for (final (a, b) in story.chunks)
                if (!got.containsKey('$a-$b')) (a, b),
            ];
            if (left.isEmpty) break;
            try {
              final reply = await client.chatCompletion(
                [
                  Message.system(chunkPrefixPrompt),
                  Message.user(
                    chunkPrefixRequest(story.title, story.lines, left),
                  ),
                ],
                temperature: 0.2,
                maxTokens: 8192,
              );
              got.addAll(parseChunkPrefixes(reply.content, left));
            } on LLMException catch (e) {
              // ignore: avoid_print
              print('${story.id}: $e');
            }
          }
          missingSentences += story.chunks.length - got.length;
          file.writeAsStringSync(
            const JsonEncoder.withIndent(' ').convert({
              'story_id': story.id,
              'title': story.title,
              'prefixes': got,
            }),
          );
          done++;
          if (done % 10 == 0) {
            // ignore: avoid_print
            print('$done/${todo.length}：$calls 次调用，prompt $prompt，'
                'completion $completion');
          }
        }
      }

      await Future.wait([for (var i = 0; i < workers; i++) worker()]);
      // ignore: avoid_print
      print('前缀：$calls 次调用，prompt $prompt，completion $completion；'
          '没写出前缀的块 $missingSentences');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      File('$out/usage_$stamp.json').writeAsStringSync(
        jsonEncode({
          'stories': todo.length,
          'calls': calls,
          'prompt_tokens': prompt,
          'completion_tokens': completion,
          'chunks_without_sentence': missingSentences,
        }),
      );

      // 2. The vectors of the prefixed chunks.
      final texts = <String, String>{
        for (final s in todo)
          if (s.prefixFile(out).existsSync())
            for (final (a, b) in s.chunks)
              '${s.id}#$a-$b': prefixedChunkText(
                s.title,
                ((jsonDecode(s.prefixFile(out).readAsStringSync())
                    as Map<String, dynamic>)['prefixes'] as Map)['$a-$b']
                    as String?,
                chunkText(s.lines, a, b),
              ),
      };
      final vectors = await _embed(texts, '$out/vectors.json');

      // 3. Copies of the libraries with those vectors.
      for (final MapEntry(key: game, value: path) in paths.entries) {
        final copy = '$out/${File(path).uri.pathSegments.last}';
        File(path).copySync(copy);
        final db = await databaseFactoryFfi.openDatabase(File(copy).absolute.path);
        var n = 0;
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (final MapEntry(:key, :value) in vectors.entries) {
            if (gameOfId(key.split('#').first) != game) continue;
            final q = quantize(value);
            batch.update(
              storyChunkVectorsTable,
              {'scale': q.scale, 'vec': Uint8List.view(q.values.buffer)},
              where: 'chunk_id = ?',
              whereArgs: [key],
            );
            n++;
          }
          await batch.commit(noResult: true);
        });
        await db.close();
        // ignore: avoid_print
        print('$copy：换了 $n 块的向量');
      }

      // 4. Old against new, among the same chunks.
      await _compare(cases, dbs, vectors, out);
    },
    skip: !enabled || akPath.isEmpty
        ? 'set ARKLORES_RUN_CHUNK_PREFIX=true and ARKLORES_GAMEDATA_DB'
        : false,
    timeout: const Timeout(Duration(hours: 4)),
  );
}

class _Story {
  _Story(this.id, this.title, this.lines, this.chunks);
  final String id;
  final String title;
  final List<PrefixLine> lines;
  final List<(int, int)> chunks;

  File prefixFile(String out) => File(
        '$out/prefixes/${id.replaceAll(RegExp(r'[^\w\-.]'), '_')}.json',
      );
}

/// Vectors of [texts] by chunk id, from the file at [path] where its text
/// is unchanged, else from the embedding service (costs money).
Future<Map<String, List<double>>> _embed(
  Map<String, String> texts,
  String path,
) async {
  final values = <String, String>{};
  for (final line in File('tools/embedding-apiKey.csv').readAsLinesSync()) {
    final i = line.indexOf(',');
    if (i > 0) {
      values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
  }
  final client = OpenAICompatibleEmbeddingClient(
    config: defaultEmbeddingConfig.copyWith(
      baseUrl: values['openAiCompatible'],
      apiKey: values['apiKey'],
    ),
  );
  final file = File(path);
  final json = file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  final vectors = <String, List<double>>{
    for (final MapEntry(:key, :value)
        in ((json['vectors'] as Map<String, dynamic>?) ?? {}).entries)
      key: [for (final x in value as List) (x as num).toDouble()],
  };
  final kept = (json['texts'] as Map<String, dynamic>?) ?? {};
  final missing = [
    for (final MapEntry(:key, :value) in texts.entries)
      if (!vectors.containsKey(key) || kept[key] != value) key,
  ];
  var next = 0;
  Future<void> worker() async {
    while (next < missing.length) {
      final batch = missing.skip(next).take(10).toList();
      next += batch.length;
      final got = await client.embed([for (final k in batch) texts[k]!]);
      for (final (i, k) in batch.indexed) {
        vectors[k] = got[i];
      }
    }
  }

  await Future.wait([for (var i = 0; i < 5; i++) worker()]);
  file.writeAsStringSync(
    jsonEncode({'vectors': vectors, 'texts': texts}),
  );
  // ignore: avoid_print
  print('向量：新算 ${missing.length} 块（${client.tokensUsed} token），'
      '共 ${vectors.length} 块');
  return vectors;
}

/// For each gold line of [cases]: the best rank, among the chunks that got
/// a new vector, of a chunk holding it — with the library's vectors and
/// with the new ones — for the question and each planned search.
Future<void> _compare(
  List<Map<String, dynamic>> cases,
  Map<Game, Database> dbs,
  Map<String, List<double>> fresh,
  String out,
) async {
  final queries = (jsonDecode(
    File('build/recall_eval/query_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>)['vectors'] as Map<String, dynamic>;
  List<double>? queryVector(String q) => queries[q] == null
      ? null
      : [for (final x in queries[q] as List) (x as num).toDouble()];

  // The library's vectors of the same chunks.
  final old = <String, List<double>>{};
  for (final id in fresh.keys) {
    final db = dbs[gameOfId(id.split('#').first)]!;
    final rows = await db.rawQuery(
      'SELECT scale, vec FROM $storyChunkVectorsTable WHERE chunk_id = ?',
      [id],
    );
    if (rows.isEmpty) continue;
    final scale = (rows.single['scale'] as num).toDouble();
    final bytes = rows.single['vec'] as Uint8List;
    final ints = Int8List.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    old[id] = [for (final v in ints) v * scale];
  }
  // The new ones quantized as the library would keep them.
  final fresh8 = {
    for (final MapEntry(:key, :value) in fresh.entries)
      key: () {
        final q = quantize(value);
        return [for (final v in q.values) v * q.scale];
      }(),
  };

  int? rankOf(
    Map<String, List<double>> vectors,
    List<double> q,
    bool Function(String chunk) isGold,
  ) {
    final scored = [
      for (final MapEntry(:key, :value) in vectors.entries)
        (key, cosineSimilarity(q, value)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (i, (k, _)) in scored.indexed) {
      if (isGold(k)) return i + 1;
    }
    return null;
  }

  final b = StringBuffer()
    ..writeln('# 检索块前缀：同一批块里金标块的排名（旧向量 → 加前缀）')
    ..writeln()
    ..writeln('候选：加了前缀的 ${fresh.length} 块。排名越小越好；'
        '“问题”是用问题原文检索，“检索词”是拟定的检索词里最好的一个。')
    ..writeln()
    ..writeln('| 题 | 金标 | 问题：旧 → 新 | 检索词：旧 → 新 |')
    ..writeln('| --- | --- | --- | --- |');
  var better = 0;
  var worse = 0;
  final top20 = [0, 0];
  var golds = 0;
  for (final c in cases) {
    final planned = [
      for (final s in ((c['planner'] as Map?)?['search'] as List? ?? const []))
        '$s',
    ];
    for (final g in (c['gold'] as List? ?? const [])
        .cast<Map<String, dynamic>>()) {
      if (g['story_id'] == null) continue;
      final story = '${g['story_id']}';
      final first = (g['lines'] as List)[0] as int;
      final last = (g['lines'] as List)[1] as int;
      bool isGold(String chunk) {
        final (s, range) = (chunk.split('#').first, chunk.split('#').last);
        final a = int.parse(range.split('-').first);
        final z = int.parse(range.split('-').last);
        return s == story && a <= last && first <= z;
      }

      int? best(Map<String, List<double>> vectors, List<String> qs) {
        int? r;
        for (final q in qs) {
          final v = queryVector(q);
          if (v == null) continue;
          final k = rankOf(vectors, v, isGold);
          if (k != null && (r == null || k < r)) r = k;
        }
        return r;
      }

      final qOld = best(old, ['${c['query']}']);
      final qNew = best(fresh8, ['${c['query']}']);
      final pOld = best(old, planned);
      final pNew = best(fresh8, planned);
      golds++;
      final o = [qOld, pOld].whereType<int>().fold<int?>(
            null,
            (m, x) => m == null || x < m ? x : m,
          );
      final n = [qNew, pNew].whereType<int>().fold<int?>(
            null,
            (m, x) => m == null || x < m ? x : m,
          );
      if (o != null && n != null) {
        if (n < o) better++;
        if (n > o) worse++;
        if (o <= 20) top20[0]++;
        if (n <= 20) top20[1]++;
      }
      b.writeln('| ${c['id']} | $story L$first-$last | $qOld → $qNew | '
          '$pOld → $pNew |');
    }
  }
  b
    ..writeln()
    ..writeln('金标 $golds 处：排名变好 $better、变差 $worse；'
        '前 20 名内（问题与检索词取好的那个）旧 ${top20[0]} → 新 ${top20[1]}。');
  File('$out/ab.md').writeAsStringSync(b.toString());
  // ignore: avoid_print
  print(b.toString());
}
