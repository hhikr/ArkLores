// CLI investigation driver (R11.2) — DESKTOP REPLAY OF THE REAL APP CODE.
//
// Runs the actual `InvestigationAgent` (planner loop + the same five tool
// classes + the same `EntityDisambiguator` used by the app) on the desktop
// against the real GameData DB and a real LLM provider. The ONLY thing that
// differs from the app is the data-access layer: the app uses the Flutter
// `GameDataKnowledgeStore`; the CLI implements the same `GameDataRetrieval`
// interface with `sqflite_common_ffi`, so the agent/tool/loop code is 100%
// identical. This lets you verify investigation behavior (disambiguation,
// SEARCH, READ, coverage, RESELECT, dead-loop termination) WITHOUT a phone.
//
// Usage:
//   dart run tools/run_investigation.dart \
//     --db=build/gamedata_mobile/arklores_gamedata_zh.db \
//     --query="导致特蕾西娅死亡的罪魁祸首是谁" \
//     --out=build/investigation_run.json
//
// API config is read from a gitignored `tools/api_info` file (API_KEY=/MODEL=/
// URL= lines), or --api-key / --model / --url, or the env vars
// ARKLORES_API_KEY / ARKLORES_MODEL / ARKLORES_URL. Never commit an API key.

import 'dart:convert';
import 'dart:io';

import 'package:arklores/core/agent/investigation_agent.dart';
import 'package:arklores/core/agent/react_event.dart';
import 'package:arklores/core/gamedata/game_retrieval.dart';
import 'package:arklores/core/gamedata/story_line_search.dart';
import 'package:arklores/core/llm/llm_client.dart';
import 'package:arklores/core/llm/openai_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _defaultDbPath = 'build/gamedata_mobile/arklores_gamedata_zh.db';
const _defaultQuery = '导致特蕾西娅死亡的罪魁祸首是谁';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();

  final dbPath = File(_argValue(args, '--db') ?? _defaultDbPath).absolute.path;
  final query = _argValue(args, '--query') ?? _defaultQuery;
  final outPath = _argValue(args, '--out') ?? 'build/investigation_run.json';

  if (!await File(dbPath).exists()) {
    stderr.writeln('GameData DB not found: $dbPath');
    exitCode = 2;
    return;
  }

  final config = _loadConfig(args);
  if (config == null) {
    stderr.writeln('No API config. Provide --api-key/--model/--url, env vars, '
        'or a gitignored tools/api_info file.');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(readOnly: true),
  );

  stdout.writeln('ArkLores investigation driver (reuses app InvestigationAgent)');
  stdout.writeln('DB:    $dbPath');
  stdout.writeln('Query: $query');
  stdout.writeln('Model: ${config.chatModel} (${config.chatBaseUrl})');
  stdout.writeln('---');

  final llm = OpenAICompatibleClient(config: config);
  // The SAME InvestigationAgent as the app, with an FFI-backed
  // GameDataRetrieval store. All tools + loop + disambiguator are app code.
  final agent = InvestigationAgent(
    llmClient: llm,
    gameDataStore: _FfiGameDataRetrieval(db),
  );

  final iterations = <Map<String, dynamic>>[];
  final started = DateTime.now();

  await for (final event in agent.investigate(query: query)) {
    switch (event.type) {
      case ReActEventType.toolCall:
        stdout.writeln('[tool] ${event.toolName} ${event.toolArgs}');
      case ReActEventType.toolObservation:
        stdout.writeln('       ${_firstLines(event.content, 2)}');
      case ReActEventType.finalAnswerToken:
        stdout.write(event.content);
      case ReActEventType.thought:
        break;
      case ReActEventType.error:
        stdout.writeln('[error] ${event.content}');
      case ReActEventType.complete:
        stdout.writeln();
        stdout.writeln('[complete]');
    }
    iterations.add({
      'type': event.type.name,
      'content': event.content,
      if (event.toolName != null) 'tool': event.toolName,
      if (event.toolArgs != null) 'tool_args': event.toolArgs,
    },);
  }

  final durationMs = DateTime.now().difference(started).inMilliseconds;
  await File(outPath).parent.create(recursive: true);
  await File(outPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'format': 'arklores_cli_investigation',
      'version': 1,
      'query': query,
      'model': config.chatModel,
      'base_url': config.chatBaseUrl,
      'duration_ms': durationMs,
      'iterations': iterations,
    }),
  );
  stdout.writeln('\nSession written to $outPath '
      '(${iterations.length} events, ${durationMs}ms).');
  await db.close();
  llm.dispose();
}

String? _argValue(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}

LLMConfig? _loadConfig(List<String> args) {
  final apiKey = _argValue(args, '--api-key') ??
      Platform.environment['ARKLORES_API_KEY'];
  final model = _argValue(args, '--model') ??
      Platform.environment['ARKLORES_MODEL'];
  final url = _argValue(args, '--url') ??
      Platform.environment['ARKLORES_URL'];

  if (apiKey != null && model != null && url != null) {
    return LLMConfig(chatBaseUrl: url, chatApiKey: apiKey, chatModel: model);
  }
  final file = File('tools/api_info');
  if (file.existsSync()) {
    String? fk, fm, fu;
    for (final line in file.readAsLinesSync()) {
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();
      if (key == 'API_KEY') fk = value;
      if (key == 'MODEL') fm = value;
      if (key == 'URL') fu = value;
    }
    if (fk != null) {
      return LLMConfig(
        chatBaseUrl: url ?? fu ?? '',
        chatApiKey: apiKey ?? fk,
        chatModel: model ?? fm ?? '',
      );
    }
  }
  return null;
}

String _firstLines(String text, int n) {
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
  final head = lines.take(n).join(' | ');
  return head.length > 160 ? '${head.substring(0, 157)}…' : head;
}

/// FFI-backed implementation of the same `GameDataRetrieval` the app's tools
/// consume. Mirrors `GameDataKnowledgeStore` query semantics so behavior is
/// equivalent on the desktop. Pure Dart (this file never imports Flutter).
class _FfiGameDataRetrieval implements GameDataRetrieval {
  _FfiGameDataRetrieval(this.db);
  final Database db;

  @override
  Future<bool> get isAvailable async => db.isOpen;

  @override
  Future<List<GameDataSearchResult>> search({
    required String query,
    int topK = 5,
    String? contentType,
    String? entityId,
    String searchMode = 'general',
    String? scopeId,
  }) async {
    final results = <GameDataSearchResult>[];
    final limit = topK.clamp(1, 10);
    // Entity-exact first, then bound records.
    if (entityId != null && entityId.isNotEmpty) {
      final recs = await db.query(
        'normalized_records',
        where: 'entity_id = ?',
        whereArgs: [entityId],
        limit: limit,
      );
      for (final r in recs) {
        results.add(GameDataSearchResult(
          id: '${r['id']}',
          score: 9000,
          retrievalType: 'entity_records',
          sourceKind: 'GameData',
          sourceType: 'game_data',
          contentType: '${r['content_type'] ?? ''}',
          entityId: entityId,
          title: '${r['title'] ?? r['entity_name'] ?? ''}',
          section: r['section'] as String?,
          content: '${r['content'] ?? ''}',
          sourcePath: r['source_path'] as String?,
          rawId: r['raw_id'] as String?,
          rankingReason: 'structured entity record match',
        ),);
      }
      if (results.isEmpty) {
        final e = await db.query(
          'entities',
          where: 'id = ?',
          whereArgs: [entityId],
          limit: 1,
        );
        if (e.isNotEmpty) {
          results.add(GameDataSearchResult(
            id: entityId,
            score: 8000,
            retrievalType: 'entity_exact',
            sourceKind: 'GameData',
            sourceType: e.first['source_type'] as String? ?? 'game_data',
            contentType: '${e.first['source_type'] ?? ''}',
            entityId: entityId,
            title: '${e.first['name'] ?? ''}',
            section: '${e.first['entity_type'] ?? ''}',
            content: '${e.first['name'] ?? ''}',
            sourcePath: e.first['source_path'] as String?,
            rawId: entityId,
            rankingReason: 'entity exact match',
          ),);
        }
      }
    }
    return results;
  }

  @override
  Future<String?> resolveEntityId(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final direct = await db.query(
      'entities',
      where: 'id = ?',
      whereArgs: [value],
      limit: 1,
    );
    if (direct.isNotEmpty) return '${direct.first['id']}';
    if (!value.contains(':')) {
      final prefixed = await db.query(
        'entities',
        where: 'id = ? OR id LIKE ?',
        whereArgs: [value, '%:$value'],
        limit: 1,
      );
      if (prefixed.isNotEmpty) return '${prefixed.first['id']}';
    }
    return null;
  }

  @override
  Future<List<GameDataEntityCandidate>> findEntityCandidates(
    String query, {
    int limit = 8,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    // Merge name-exact and alias-exact hits (deduped by id), mirroring the
    // real store's candidate query so ambiguity input produces the SAME
    // candidate list the app would show.
    final byId = <String, GameDataEntityCandidate>{};
    final nameRows = await db.query(
      'entities',
      where: 'name = ?',
      whereArgs: [q],
      limit: limit,
    );
    for (final r in nameRows) {
      byId['${r['id']}'] = GameDataEntityCandidate(
        entityId: '${r['id']}',
        name: '${r['name'] ?? ''}',
        entityType: '${r['entity_type'] ?? ''}',
        sourceType: '${r['source_type'] ?? ''}',
        matchedAlias: '${r['name'] ?? ''}',
        matchType: 'name_exact',
        confidence: 1.0,
      );
    }
    final aliasRows = await db.rawQuery(
      'SELECT e.id, e.name, e.entity_type, e.source_type '
      'FROM entity_aliases ea JOIN entities e ON e.id = ea.entity_id '
      'WHERE ea.alias = ? LIMIT ?',
      [q, limit],
    );
    for (final r in aliasRows) {
      final id = '${r['id']}';
      // For an id whose own name is exactly the query (already added as
      // name_exact), keep the higher-confidence name_exact and skip the
      // weaker alias entry.
      byId[id] = byId[id] ??
          GameDataEntityCandidate(
            entityId: id,
            name: '${r['name'] ?? ''}',
            entityType: '${r['entity_type'] ?? ''}',
            sourceType: '${r['source_type'] ?? ''}',
            matchedAlias: q,
            matchType: 'alias_exact',
            confidence: 0.8,
          );
    }
    return byId.values.toList(growable: false);
  }

  @override
  Future<List<StoryCoverageEntry>> searchStoryCoverage({
    required String entityId,
    String? scopeFilter,
  }) async {
    final scope = scopeFilter?.trim();
    final rows = scope != null && scope.isNotEmpty
        ? await db.query(
            'entity_story_mentions',
            where: 'entity_id = ? AND scope_id = ?',
            whereArgs: [entityId, scope],
            limit: 500,
          )
        : await db.query(
            'entity_story_mentions',
            where: 'entity_id = ?',
            whereArgs: [entityId],
            limit: 500,
          );
    return [
      for (final r in rows)
        StoryCoverageEntry(
          entityId: '${r['entity_id'] ?? ''}',
          storyId: '${r['story_id'] ?? ''}',
          scopeId: '${r['scope_id'] ?? ''}',
          lineStart: (r['line_start'] as num).toInt(),
          lineEnd: (r['line_end'] as num).toInt(),
          mentionCount: (r['mention_count'] as num).toInt(),
          matchedAlias: r['matched_alias'] as String?,
        ),
    ];
  }

  @override
  Future<StoryLinesPage> readStoryLines({
    required String storyId,
    int? startLine,
    int? endLine,
    int? maxLines,
    String? pageToken,
  }) async {
    var fromLine = startLine ?? 0;
    if (pageToken != null && pageToken.trim().isNotEmpty) {
      fromLine = int.tryParse(pageToken.trim()) ?? 0;
    }
    final exists = await db.query(
      'story_scopes',
      where: 'story_id = ?',
      whereArgs: [storyId],
      limit: 1,
    );
    if (exists.isEmpty) return const StoryLinesPage(lines: [], storyFound: false);
    final limit = (maxLines ?? 30).clamp(1, 100);
    // Windowed query with parameters.
    final winRows = await db.rawQuery(
      'SELECT line_index, speaker, content FROM story_lines '
      'WHERE story_id = ? AND line_index >= ? '
      '${endLine != null ? 'AND line_index <= ?' : ''} '
      'ORDER BY line_index LIMIT ?',
      endLine != null
          ? [storyId, fromLine, endLine, limit + 1]
          : [storyId, fromLine, limit + 1],
    );
    final hasMore = winRows.length > limit;
    final page = hasMore ? winRows.sublist(0, limit) : winRows;
    final lines = [
      for (final r in page)
        StoryLineEntry(
          lineIndex: (r['line_index'] as num).toInt(),
          speaker: r['speaker'] as String?,
          content: '${r['content'] ?? ''}',
        ),
    ];
    final next = hasMore && lines.isNotEmpty ? '${lines.last.lineIndex + 1}' : null;
    return StoryLinesPage(
      lines: lines,
      storyFound: true,
      nextPageToken: next,
    );
  }

  @override
  Future<List<StoryChapterProfile>> getStoryMap({
    List<String>? storyIds,
    String? scopeId,
  }) async {
    List<Map<String, Object?>> rows;
    final ids = storyIds
        ?.map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (ids != null && ids.isNotEmpty) {
      rows = await db.query(
        'story_chapter_profiles',
        where: 'story_id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids,
        limit: 100,
      );
    } else if (scopeId != null && scopeId.trim().isNotEmpty) {
      rows = await db.query(
        'story_chapter_profiles',
        where: 'scope_id = ?',
        whereArgs: [scopeId.trim()],
        limit: 100,
      );
    } else {
      return const [];
    }
    return [
      for (final r in rows)
        StoryChapterProfile(
          storyId: '${r['story_id'] ?? ''}',
          scopeId: '${r['scope_id'] ?? ''}',
          title: r['title'] as String?,
          lineStart: (r['line_start'] as num).toInt(),
          lineEnd: (r['line_end'] as num).toInt(),
          speakerSet: _stringList(r['speaker_set']),
          entityDensity: _intMap(r['entity_density']),
          summary: r['summary'] as String?,
        ),
    ];
  }

  @override
  Future<List<Map<String, Object?>>> searchStoryLinesLikeInStories(
    String term,
    List<String> storyIds, {
    int limit = 500,
  }) async {
    if (storyIds.isEmpty) return const [];
    final escaped = term
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final placeholders = List.filled(storyIds.length, '?').join(',');
    return db.rawQuery(
      'SELECT story_id, line_index, speaker, content FROM story_lines '
      'WHERE content LIKE ? ESCAPE \'\\\' AND story_id IN ($placeholders) '
      'ORDER BY story_id, line_index LIMIT ?',
      ['%$escaped%', ...storyIds, limit],
    );
  }

  @override
  Future<List<StoryLineHit>> searchStoryLinesLike(
    List<String> terms, {
    String? scopeId,
    int storyLimit = 8,
    int linesPerStory = 3,
  }) =>
      queryStoryLinesLike(
        db,
        terms,
        scopeId: scopeId,
        storyLimit: storyLimit,
        linesPerStory: linesPerStory,
      );
}

List<String> _stringList(Object? raw) {
  if (raw is! String) return const [];
  try {
    final d = jsonDecode(raw);
    if (d is List) return d.map((e) => '$e').toList();
  } catch (_) {}
  return const [];
}

Map<String, int> _intMap(Object? raw) {
  if (raw is! String) return const {};
  try {
    final d = jsonDecode(raw);
    if (d is Map) {
      return {
        for (final e in d.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
      };
    }
  } catch (_) {}
  return const {};
}