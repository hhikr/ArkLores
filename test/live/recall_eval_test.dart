import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/coverage.dart';
import 'package:arklores/core/agent/line_picker.dart';
import 'package:arklores/core/agent/lore_tools.dart';
import 'package:arklores/core/agent/tools/search_tool.dart';
import 'package:arklores/core/gamedata/game.dart';
import 'package:arklores/core/gamedata/gamedata_knowledge_store.dart';
import 'package:arklores/core/gamedata/multi_game_retrieval.dart';
import 'package:arklores/core/llm/embedding_client.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'live_support.dart' show readApiInfo;

/// Opt-in, offline recall check of a question's first step (unified
/// refactor, phase 0): what the searches before the first turn show,
/// scored against the gold of `test/fixtures/recall_eval.json` and the
/// gold stories of `investigation_eval.json`. No model is called.
///
///   $env:ARKLORES_RUN_RECALL_EVAL='true'
///   $env:ARKLORES_GAMEDATA_DB="$PWD\build\gamedata_v5\arklores_gamedata_zh.db"
///   $env:ARKLORES_ENDFIELD_DB="$PWD\build\endfield\arklores_endfield_zh.db"
///   flutter test test/live/recall_eval_test.dart
///
/// Keywords only, unless `ARKLORES_RECALL_VECTORS` names a file of query
/// vectors (`{"model", "dims", "vectors": {query: [..]}}`): those stand in
/// for the embedding service, so a run never pays for one.
/// `ARKLORES_RECALL_EMBED=true` first embeds the queries that file lacks
/// (default `build/recall_eval/query_vectors.json`) with the real service:
/// that costs money, ask the developer first. The queries a
/// vector run needs are written to `build/recall_eval/queries.txt`.
/// The report goes to `build/recall_eval/` (`report.md`, `report.json`).
void main() {
  final enabled = Platform.environment['ARKLORES_RUN_RECALL_EVAL'] == 'true';
  final akPath = Platform.environment['ARKLORES_GAMEDATA_DB'] ?? '';
  final efPath = Platform.environment['ARKLORES_ENDFIELD_DB'] ?? '';
  final embed = Platform.environment['ARKLORES_RECALL_EMBED'] == 'true';
  final vectorsPath = Platform.environment['ARKLORES_RECALL_VECTORS'] ??
      (embed ? 'build/recall_eval/query_vectors.json' : '');
  final only = (Platform.environment['ARKLORES_RECALL_IDS'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();

  // Phase 2: `ARKLORES_RECALL_PICK=true` adds the picked variants, whose
  // line picker calls the real model of tools/api_info (costs money; the
  // tokens are reported).
  final pick = Platform.environment['ARKLORES_RECALL_PICK'] == 'true';
  final variants = (Platform.environment['ARKLORES_RECALL_VARIANTS'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();

  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  test(
    'first step recall against the gold set',
    () async {
      final cases = _loadCases();
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
      final store = MultiGameRetrieval({
        Game.arknights: GameDataKnowledgeStore(dbPath: akPath),
        if (efPath.isNotEmpty)
          Game.endfield:
              GameDataKnowledgeStore(dbPath: efPath, game: Game.endfield),
      });
      if (embed) {
        await _embedMissing(
          vectorsPath,
          {
            for (final c in cases)
              if (only.isEmpty || only.contains(c.id))
                for (final v in c.variants) ...v.searches,
          },
        );
      }
      final embedder =
          vectorsPath.isEmpty ? null : _CachedEmbedder.load(vectorsPath);
      var pickPrompt = 0;
      var pickCompletion = 0;
      var pickCalls = 0;
      final picker = !pick
          ? null
          : LinePicker(
              OpenAICompatibleClient(
                config: readApiInfo(File('tools/api_info')),
                onCompletion: (r) {
                  pickCalls++;
                  pickPrompt += r.promptTokens ?? 0;
                  pickCompletion += r.completionTokens ?? 0;
                },
              ),
            );

      // The gold must be in the libraries, or the score means nothing.
      for (final c in cases) {
        for (final g in c.gold) {
          final db = dbs[gameOfId(g.storyId ?? g.records.first)];
          if (db == null) continue;
          if (g.storyId != null) {
            final n = sqflite.Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM story_lines WHERE story_id = ? '
                'AND line_index BETWEEN ? AND ?',
                [g.storyId, g.first, g.last],
              ),
            );
            expect(
              n,
              g.whole ? greaterThan(0) : g.last - g.first + 1,
              reason: '${c.id}: ${g.storyId} L${g.first}-${g.last}',
            );
          } else {
            final n = sqflite.Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM normalized_records WHERE id IN '
                '(${List.filled(g.records.length, '?').join(',')})',
                g.records,
              ),
            );
            expect(n, greaterThan(0), reason: '${c.id}: ${g.records}');
          }
        }
      }

      final collectionOf = <String, String>{};
      Future<String?> collection(String storyId) async {
        if (collectionOf.containsKey(storyId)) return collectionOf[storyId];
        final db = dbs[gameOfId(storyId)];
        if (db == null) return null;
        final rows = await db.rawQuery(
          'SELECT collection_name FROM story_catalog WHERE story_id = ?',
          [storyId],
        );
        final name = rows.isEmpty ? '' : '${rows.single['collection_name']}';
        return collectionOf[storyId] = name;
      }

      final queries = <String>{};
      final results = <Map<String, Object?>>[];
      for (final c in cases) {
        if (only.isNotEmpty && !only.contains(c.id)) continue;
        for (final variant in [
          ...c.variants,
          if (picker != null)
            for (final v in c.variants)
              if (v.name == 'planner+coverage30' ||
                  (v.name == 'coverage30' &&
                      !c.variants.any((w) => w.name == 'planner')))
                _Variant(
                  v.name == 'coverage30' ? 'picked' : 'planner+picked',
                  v.searches,
                  v.outlines,
                  anchors: v.anchors,
                  budget: v.budget,
                  picked: true,
                ),
        ]) {
          if (variants.isNotEmpty && !variants.contains(variant.name)) continue;
          final seen = SeenLines();
          final search = SearchTool(store, seen, embeddingClient: embedder);
          final outline = OutlineTool(store);
          final watch = Stopwatch()..start();
          var chars = 0;
          for (final q in variant.searches) {
            queries.add(q);
            chars += (await search.run(q)).text.length;
          }
          for (final o in variant.outlines) {
            chars += (await outline.execute({'collection': o})).length;
          }
          if (variant.picked) {
            final tool = GatherTool(store, seen, picker: picker)
              ..question = c.query;
            chars += (await tool.execute({'names': variant.anchors})).length;
          } else if (variant.budget > 0) {
            final coverage = await CoverageBuilder(store).build(
              variant.anchors,
              budgetChars: variant.budget,
              hinted: seen.stories.toSet(),
              context: variant.context,
              perStoryChars: variant.perStoryChars,
            );
            coverage.register(seen);
            chars += coverage.render().length;
          }
          watch.stop();
          final hits = [
            for (final g in c.gold)
              g.whole
                  ? seen.stories.contains(g.storyId)
                  : g.storyId != null
                      ? seen.seenRanges(g.storyId!, g.first, g.last).isNotEmpty
                      : g.records.any(seen.hasRecord),
          ];
          final goldStories = {
            for (final g in c.gold)
              if (g.storyId != null) g.storyId!,
          };
          final shownCollections = <String>{};
          for (final s in seen.stories) {
            final name = await collection(s);
            if (name != null && name.isNotEmpty) shownCollections.add(name);
          }
          final games = {for (final s in seen.stories) gameOfId(s).key};
          results.add({
            'id': c.id,
            'source': c.source,
            'type': c.type,
            'variant': variant.name,
            'searches': variant.searches,
            'outlines': variant.outlines,
            'gold': c.gold.length,
            'gold_hit': hits.where((h) => h).length,
            'gold_missed': [
              for (final (i, g) in c.gold.indexed)
                if (!hits[i]) g.label,
            ],
            'gold_stories': goldStories.length,
            'gold_stories_hit':
                goldStories.where((s) => seen.stories.contains(s)).length,
            'gold_collections': c.collections.length,
            'gold_collections_hit':
                c.collections.where(shownCollections.contains).length,
            'min_collections': c.minCollections,
            'gold_games': c.games,
            'games_shown': games.toList()..sort(),
            'chars': chars,
            'stories_shown': seen.stories.length,
            'collections_shown': shownCollections.length,
            'ms': watch.elapsedMilliseconds,
          });
        }
      }

      final out = Directory('build/recall_eval')..createSync(recursive: true);
      File('${out.path}/queries.txt')
          .writeAsStringSync('${(queries.toList()..sort()).join('\n')}\n');
      File('${out.path}/report.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert({
          'mode': embedder == null ? 'keywords' : 'vectors',
          if (picker != null)
            'pick_usage': {
              'calls': pickCalls,
              'prompt_tokens': pickPrompt,
              'completion_tokens': pickCompletion,
            },
          'vector_misses': embedder?.misses.toList(),
          'arknights_db': akPath,
          'endfield_db': efPath,
          'results': results,
        }),
      );
      File('${out.path}/report.md').writeAsStringSync(
        _report(results, embedder == null ? '只有关键词' : '向量（缓存）+ 关键词'),
      );
      // ignore: avoid_print
      print(File('${out.path}/report.md').readAsStringSync());
      if (picker != null) {
        // ignore: avoid_print
        print('挑行用量：$pickCalls 次调用，prompt $pickPrompt，'
            'completion $pickCompletion');
      }
      expect(results, isNotEmpty);
    },
    skip: !enabled || akPath.isEmpty
        ? 'set ARKLORES_RUN_RECALL_EVAL=true and ARKLORES_GAMEDATA_DB'
        : false,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

class _Gold {
  _Gold.lines(String this.storyId, this.first, this.last, this.note)
      : records = const [],
        whole = false;
  _Gold.story(String this.storyId, this.note)
      : records = const [],
        whole = true,
        first = 0,
        last = 0;
  _Gold.records(this.records, this.note)
      : storyId = null,
        whole = false,
        first = 0,
        last = 0;

  final String? storyId;
  final int first;
  final int last;
  final List<String> records;
  final String note;

  /// Any line of the story counts.
  final bool whole;

  String get label => whole
      ? '$storyId（整篇）'
      : storyId != null
          ? '$storyId L$first${last == first ? '' : '-$last'}'
              '${note.isEmpty ? '' : '（$note）'}'
          : 'record:${records.join('|')}${note.isEmpty ? '' : '（$note）'}';
}

class _Variant {
  const _Variant(
    this.name,
    this.searches,
    this.outlines, {
    this.anchors = const [],
    this.budget = 0,
    this.context = CoverageBuilder.defaultContext,
    this.perStoryChars = CoverageBuilder.defaultPerStoryChars,
    this.picked = false,
  });
  final String name;
  final List<String> searches;
  final List<String> outlines;

  /// Material gathered by [CoverageBuilder] for these anchors (none when
  /// [budget] is 0), after the searches.
  final List<String> anchors;
  final int budget;
  final int context;
  final int perStoryChars;

  /// Gathered through `gather` with a [LinePicker] (phase 2).
  final bool picked;
}

/// The coverage variants of a case: the anchors alone at three budgets,
/// and after the planner's searches.
List<_Variant> _coverageVariants(List<String> anchors, _Variant? planner) => [
      if (anchors.isNotEmpty)
        for (final k in [15, 30, 60])
          _Variant('coverage$k', const [], const [],
              anchors: anchors, budget: k * 1000,),
      if (anchors.isNotEmpty && planner != null)
        _Variant('planner+coverage30', planner.searches, planner.outlines,
            anchors: anchors, budget: 30000,),
      // Phase 2: the wider pool a line picker would read (each anchor line
      // with eight lines either side, up to 12k characters a story).
      if (anchors.isNotEmpty)
        for (final k in [60, 120])
          _Variant(
            '${planner != null ? 'planner+' : ''}wide$k',
            planner?.searches ?? const [],
            planner?.outlines ?? const [],
            anchors: anchors,
            budget: k * 1000,
            context: 8,
            perStoryChars: 12000,
          ),
      // Phase 2 (after picking lost lines, 2026-10-19): what the answering
      // model could be given directly — more lines around each place, a
      // little more room.
      if (anchors.isNotEmpty && planner != null)
        for (final (ctx, k) in [(2, 45), (4, 30), (4, 45), (8, 45)])
          _Variant(
            'planner+c$ctx-$k',
            planner.searches,
            planner.outlines,
            anchors: anchors,
            budget: k * 1000,
            context: ctx,
            perStoryChars: 1500 * (ctx + 1),
          ),
    ];

class _Case {
  _Case({
    required this.id,
    required this.query,
    required this.source,
    required this.type,
    required this.gold,
    required this.collections,
    required this.minCollections,
    required this.games,
    required this.variants,
  });

  final String id;
  final String query;
  final String source;
  final String type;
  final List<_Gold> gold;
  final List<String> collections;
  final int? minCollections;
  final List<String> games;
  final List<_Variant> variants;
}

List<String> _strings(Object? v) =>
    [for (final s in v is List ? v : const []) '$s'];

List<_Case> _loadCases() {
  final recall = jsonDecode(
    File('test/fixtures/recall_eval.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = <_Case>[];
  for (final c in (recall['cases'] as List).cast<Map<String, dynamic>>()) {
    final anchors = _strings(c['anchors']);
    final planner = c['planner'] as Map<String, dynamic>?;
    cases.add(
      _Case(
        id: '${c['id']}',
        query: '${c['query']}',
        source: 'recall',
        type: '${c['type']}',
        gold: [
          for (final g
              in (c['gold'] as List? ?? const []).cast<Map<String, dynamic>>())
            if (g['story_id'] != null)
              _Gold.lines(
                '${g['story_id']}',
                (g['lines'] as List)[0] as int,
                (g['lines'] as List)[1] as int,
                '${g['note'] ?? ''}',
              )
            else
              _Gold.records(_strings(g['record_any']), '${g['note'] ?? ''}'),
        ],
        collections: _strings(c['gold_collections']),
        minCollections: c['min_collections'] as int?,
        games: _strings(c['gold_games']),
        variants: () {
          final plan = planner == null
              ? null
              : _Variant(
                  'planner',
                  _strings(planner['search']),
                  _strings(planner['outline']),
                );
          return [
            if (plan != null) plan,
            if (anchors.isNotEmpty)
              _Variant('anchors', [anchors.join(' ')], []),
            ..._coverageVariants(anchors, plan),
          ];
        }(),
      ),
    );
  }
  // The older set: gold stories, each anchored at a line (`L12 ...`).
  final anchorsOf = (recall['investigation_anchors'] as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, _strings(v)));
  final investigation = jsonDecode(
    File('test/fixtures/investigation_eval.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final lineOf = RegExp(r'^L(\d+)');
  for (final c
      in (investigation['cases'] as List).cast<Map<String, dynamic>>()) {
    final anchors = anchorsOf['${c['id']}'] ?? const <String>[];
    final gold = <_Gold>[];
    for (final g in (c['gold_stories'] as List).cast<Map<String, dynamic>>()) {
      final m = lineOf.firstMatch('${g['anchor']}');
      // An anchor without a line: the whole story is the gold.
      gold.add(
        m == null
            ? _Gold.story('${g['story_id']}', '')
            : _Gold.lines(
                '${g['story_id']}',
                int.parse(m.group(1)!),
                int.parse(m.group(1)!),
                '',
              ),
      );
    }
    cases.add(
      _Case(
        id: '${c['id']}',
        query: '${c['query']}',
        source: 'investigation',
        type: '${c['type']}',
        gold: gold,
        collections: const [],
        minCollections: null,
        games: const [],
        variants: [
          if (anchors.isNotEmpty) _Variant('anchors', [anchors.join(' ')], []),
          ..._coverageVariants(anchors, null),
        ],
      ),
    );
  }
  return cases;
}

String _report(List<Map<String, Object?>> results, String mode) {
  final b = StringBuffer()
    ..writeln('# 第一步召回（$mode）')
    ..writeln()
    ..writeln('“命中”= 第一步展示过金标里的任意一行（资料：展示过那条资料）。')
    ..writeln();
  int sum(Iterable<Map<String, Object?>> rs, String k) =>
      rs.fold(0, (n, r) => n + (r[k] as int));
  int median(List<int> xs) {
    if (xs.isEmpty) return 0;
    final s = [...xs]..sort();
    return s[s.length ~/ 2];
  }

  int p90(List<int> xs) {
    if (xs.isEmpty) return 0;
    final s = [...xs]..sort();
    return s[((s.length - 1) * 0.9).round()];
  }

  for (final source in ['recall', 'investigation']) {
    for (final variant in _variantNames) {
      final rs = [
        for (final r in results)
          if (r['source'] == source && r['variant'] == variant) r,
      ];
      if (rs.isEmpty) continue;
      final scored = [
        for (final r in rs)
          if ((r['gold'] as int) > 0) r,
      ];
      final withCollections = [
        for (final r in rs)
          if ((r['gold_collections'] as int) > 0) r,
      ];
      final cross = [
        for (final r in rs)
          if ((r['gold_games'] as List).length > 1) r,
      ];
      final chars = [for (final r in rs) r['chars'] as int];
      final ms = [for (final r in rs) r['ms'] as int];
      b
        ..writeln('## ${source == 'recall' ? '日志题' : '旧调查题'} · '
            '${_variantLabels[variant]}')
        ..writeln()
        ..writeln('- 题数 ${rs.length}；有行级金标 ${scored.length} 题')
        ..writeln('- 金标命中 ${sum(scored, 'gold_hit')}/${sum(scored, 'gold')}'
            '（${_pct(sum(scored, 'gold_hit'), sum(scored, 'gold'))}）；'
            '金标全中的题 ${scored.where((r) => r['gold_hit'] == r['gold']).length}/${scored.length}；'
            '一条都没中的题 ${scored.where((r) => r['gold_hit'] == 0).length}')
        ..writeln(
            '- 金标故事 ${sum(scored, 'gold_stories_hit')}/${sum(scored, 'gold_stories')}'
            '（${_pct(sum(scored, 'gold_stories_hit'), sum(scored, 'gold_stories'))}）');
      if (withCollections.isNotEmpty) {
        b.writeln('- 要求的故事集 ${sum(withCollections, 'gold_collections_hit')}/'
            '${sum(withCollections, 'gold_collections')}；够数的题 '
            '${withCollections.where((r) => (r['gold_collections_hit'] as int) >= (r['min_collections'] as int? ?? r['gold_collections'] as int)).length}/${withCollections.length}');
      }
      if (cross.isNotEmpty) {
        b.writeln('- 跨游戏题两边都展示了的 '
            '${cross.where((r) => (r['games_shown'] as List).length > 1).length}/${cross.length}');
      }
      b
        ..writeln('- 展示的字数：中位 ${median(chars)}，p90 ${p90(chars)}；'
            '每题平均 ${(sum(rs, 'stories_shown') / rs.length).toStringAsFixed(1)} 篇、'
            '${(sum(rs, 'collections_shown') / rs.length).toStringAsFixed(1)} 个故事集')
        ..writeln('- 耗时：中位 ${median(ms)} ms，p90 ${p90(ms)} ms')
        ..writeln()
        ..writeln('| 题 | 类型 | 金标 | 故事集 | 游戏 | 字数 | 没中的金标 |')
        ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
      for (final r in rs) {
        final missed = (r['gold_missed'] as List).join('；');
        b.writeln('| ${r['id']} | ${r['type']} | '
            '${r['gold_hit']}/${r['gold']} | '
            '${(r['gold_collections'] as int) > 0 ? '${r['gold_collections_hit']}/${r['gold_collections']}' : ''} | '
            '${(r['games_shown'] as List).join('+')} | ${r['chars']} | '
            '${missed.length > 160 ? '${missed.substring(0, 160)}…' : missed} |');
      }
      b.writeln();
    }
  }
  return b.toString();
}

const _variantNames = [
  'planner',
  'anchors',
  'coverage15',
  'coverage30',
  'coverage60',
  'planner+coverage30',
  'wide60',
  'wide120',
  'planner+wide60',
  'planner+wide120',
  'picked',
  'planner+picked',
  'planner+c2-45',
  'planner+c4-30',
  'planner+c4-45',
  'planner+c8-45',
];

const _variantLabels = {
  'planner': '拟定的检索（真实会话记录）',
  'anchors': '锚点合成一次检索',
  'coverage15': '按锚点取材，1.5 万字',
  'coverage30': '按锚点取材，3 万字',
  'coverage60': '按锚点取材，6 万字',
  'planner+coverage30': '拟定的检索 + 按锚点取材 3 万字',
  // Only the cases without a planner record (the others are `planner+wide*`).
  'wide60': '宽取材（前后 8 行，每篇 1.2 万字），6 万字（只有没有拟定记录的题）',
  'wide120': '宽取材，12 万字（只有没有拟定记录的题）',
  'planner+wide60': '拟定的检索 + 宽取材 6 万字',
  'planner+wide120': '拟定的检索 + 宽取材 12 万字',
  'picked': '宽取材 12 万字后挑行（真实模型），给 3 万字',
  'planner+picked': '拟定的检索 + 宽取材后挑行（真实模型），给 3 万字',
  'planner+c2-45': '拟定的检索 + 取材（前后 2 行）4.5 万字',
  'planner+c4-30': '拟定的检索 + 取材（前后 4 行）3 万字',
  'planner+c4-45': '拟定的检索 + 取材（前后 4 行）4.5 万字',
  'planner+c8-45': '拟定的检索 + 取材（前后 8 行）4.5 万字',
};

String _pct(int a, int b) =>
    b == 0 ? '-' : '${(100 * a / b).toStringAsFixed(0)}%';

/// Embeds the [queries] the file at [path] has no vector for (the real
/// service, configured by the gitignored `tools/embedding-apiKey.csv`; this
/// costs money) and writes them into it.
Future<void> _embedMissing(String path, Set<String> queries) async {
  final values = <String, String>{};
  final csv = File('tools/embedding-apiKey.csv');
  if (csv.existsSync()) {
    for (final line in csv.readAsLinesSync()) {
      final i = line.indexOf(',');
      if (i > 0) {
        values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
      }
    }
  }
  final config = defaultEmbeddingConfig.copyWith(
    baseUrl: values['openAiCompatible'],
    apiKey: values['apiKey'],
  );
  expect(config.isValid, isTrue, reason: 'tools/embedding-apiKey.csv');
  final file = File(path);
  final json = file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  if (json['model'] != null &&
      (json['model'] != config.model || json['dims'] != config.dimensions)) {
    fail('$path holds ${json['model']} vectors, not ${config.model}');
  }
  final vectors = (json['vectors'] as Map<String, dynamic>?) ?? {};
  final missing = [
    for (final q in queries)
      if (!vectors.containsKey(q)) q,
  ];
  final client = OpenAICompatibleEmbeddingClient(config: config);
  for (var i = 0; i < missing.length; i += 10) {
    final batch = missing.skip(i).take(10).toList();
    final got = await client.embed(batch);
    for (final (k, q) in batch.indexed) {
      vectors[q] = got[k];
    }
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    jsonEncode({
      'model': config.model,
      'dims': config.dimensions,
      'vectors': vectors,
    }),
  );
  // ignore: avoid_print
  print('embedded ${missing.length} queries '
      '(${client.tokensUsed} tokens billed), ${vectors.length} in $path');
}

/// Query vectors from a file instead of the embedding service.
class _CachedEmbedder implements EmbeddingClient {
  _CachedEmbedder(this.model, this.dimensions, this.vectors);

  factory _CachedEmbedder.load(String path) {
    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    return _CachedEmbedder(
      '${json['model']}',
      json['dims'] as int,
      {
        for (final MapEntry(:key, :value)
            in (json['vectors'] as Map<String, dynamic>).entries)
          key: [for (final x in value as List) (x as num).toDouble()],
      },
    );
  }

  @override
  final String model;

  @override
  final int dimensions;

  final Map<String, List<double>> vectors;

  final Set<String> misses = {};

  @override
  Future<List<List<double>>> embed(List<String> texts) async => [
        for (final t in texts)
          vectors[t] ??
              (() {
                misses.add(t);
                throw StateError('no cached vector for "$t"');
              })(),
      ];

  @override
  int get tokensUsed => 0;
}
