import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'build/gamedata_schema.dart' show storyLinesIndexName, storyLinesIndexSql;
import 'game_retrieval.dart';
import 'gamedata_query_plan.dart';
import 'name_similarity.dart';
import 'readonly_sql.dart';
import 'story_catalog.dart';
import 'story_line_search.dart';
import 'story_vectors.dart';

export 'gamedata_models.dart';

class GameDataKnowledgeStore implements GameDataRetrieval {

  GameDataKnowledgeStore({this.dbPath});
  final String? dbPath;
  sqflite.Database? _db;

  /// File identity captured when [_db] was opened. When the underlying DB file
  /// is replaced (installer swap or an in-app rebuild), the cached handle would
  /// keep serving the stale file; [_open] reopens when this stamp changes.
  FileStat? _openedFileStat;

  @override
  Future<bool> get isAvailable async {
    final path = await _resolveDbPath();
    return path != null && File(path).existsSync();
  }

  @override
  Future<List<GameDataSearchResult>> search({
    required String query,
    int topK = 5,
    String? contentType,
    String? entityId,
    String searchMode = 'general',
    String? scopeId,
  }) async {
    final plan =
        GameDataQueryPlan.from(query, explicitContentType: contentType);
    final cleanQuery = plan.originalQuery;
    if (cleanQuery.isEmpty) return const [];
    final db = await _open();
    if (db == null) return const [];

    final limit = topK.clamp(1, 10);
    final byId = <String, GameDataSearchResult>{};
    final effectiveContentType = plan.effectiveContentType;

    final summaryMode = searchMode == 'summary' || searchMode == 'roleplay';
    if (searchMode == 'evidence' &&
        scopeId != null &&
        scopeId.trim().isNotEmpty &&
        entityId != null &&
        entityId.trim().isNotEmpty) {
      return _searchScopedStoryEvidence(
        db,
        query: cleanQuery,
        scopeId: scopeId,
        entityId: entityId,
        limit: limit,
      );
    }

    if (entityId == null) {
      for (final result in await _searchEntities(
        db,
        plan.entityQuery,
        limit: limit,
        contentType: effectiveContentType,
      )) {
        byId[result.id] = result;
      }
    }

    final entityIds = <String>{
      if (entityId != null && entityId.trim().isNotEmpty) entityId.trim(),
      for (final result in byId.values)
        if (result.entityId != null) result.entityId!,
    };
    final entityNames = <String>{
      for (final result in byId.values) result.title,
      if (entityId != null && entityId.trim().isNotEmpty)
        ...await _entityNamesById(db, entityId.trim()),
    };

    for (final id in entityIds.take(5)) {
      for (final result in await _documentsForEntity(
        db,
        id,
        limit: limit,
        contentType: effectiveContentType,
      )) {
        byId.putIfAbsent(result.id, () => result);
      }
      if (summaryMode) {
        for (final result in await _searchStoryChunksLike(
          db,
          plan.entityQuery,
          entityNames: entityNames,
          limit: limit,
        )) {
          byId.putIfAbsent(result.id, () => result);
        }
      }
      for (final result in await _chunksForEntity(
        db,
        id,
        limit: limit,
        contentType: effectiveContentType,
      )) {
        byId.putIfAbsent(result.id, () => result);
      }
      for (final result in await _recordsForEntity(
        db,
        id,
        limit: limit,
        contentType: effectiveContentType,
      )) {
        byId.putIfAbsent(result.id, () => result);
      }
    }

    for (final searchQuery in plan.searchQueries) {
      if (effectiveContentType == null) {
        for (final result in await _searchDocumentsFts(
          db,
          searchQuery,
          limit: limit * 2,
          entityId: entityId,
        )) {
          byId.putIfAbsent(result.id, () => result);
        }

        for (final result in await _searchDocumentsLike(
          db,
          searchQuery,
          limit: limit * 2,
          entityId: entityId,
        )) {
          byId.putIfAbsent(result.id, () => result);
        }
      }

      for (final result in await _searchRecordsLike(
        db,
        searchQuery,
        limit: limit * 2,
        contentType: effectiveContentType,
        entityId: entityId,
      )) {
        byId.putIfAbsent(result.id, () => result);
      }
    }

    if (effectiveContentType != null) {
      for (final result in await _recordsByContentType(
        db,
        effectiveContentType,
        limit: limit,
      )) {
        byId.putIfAbsent(result.id, () => result);
      }
    }

    if (summaryMode || plan.hasStoryIntent) {
      for (final result in await _searchStoryChunksLike(
        db,
        plan.entityQuery,
        entityNames: entityNames,
        limit: limit * 2,
      )) {
        byId.putIfAbsent(result.id, () => result);
      }
    }

    for (final searchQuery in plan.searchQueries) {
      for (final result in await _searchChunksFts(
        db,
        searchQuery,
        limit: limit * 2,
        contentType: effectiveContentType,
        entityId: entityId,
      )) {
        byId.putIfAbsent(result.id, () => result);
      }

      for (final result in await _searchChunksLike(
        db,
        searchQuery,
        limit: limit * 2,
        contentType: effectiveContentType,
        entityId: entityId,
      )) {
        byId.putIfAbsent(result.id, () => result);
      }
    }

    if (effectiveContentType != null) {
      for (final result in await _chunksByContentType(
        db,
        effectiveContentType,
        limit: limit,
      )) {
        byId.putIfAbsent(result.id, () => result);
      }
    }

    final results = byId.values.toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        if (score != 0) return score;
        return a.title.compareTo(b.title);
      });
    return results.take(limit).toList();
  }

  /// Resolves [raw] (an entity id, possibly suffix-only, or an exact entity
  /// name/alias) to a canonical entity id.
  ///
  /// Order of attempt:
  ///   1. exact `entities.id` match;
  ///   2. if [raw] contains no namespace prefix (`:`), try prefixing each known
  ///      namespace (`enemy:`, `char:` …) at most once;
  ///   3. exact `entities.name` / `entity_aliases.alias` match.
  /// Returns null when nothing resolves.
  @override
  Future<String?> resolveEntityId(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final db = await _open();
    if (db == null) return null;

    final direct = await db.rawQuery(
      'SELECT id FROM entities WHERE id = ? LIMIT 1',
      [value],
    );
    if (direct.isNotEmpty) return '${direct.first['id']}';

    if (!value.contains(':')) {
      // Suffix-only id: match any namespace prefix once (e.g. `enemy_1554_lrtsia`
      // -> `enemy:enemy_1554_lrtsia`). Substring LIKE would over-match
      // (`char_002` matching `char_002_amiya`); anchor to the suffix end.
      final suffix = value.replaceAll('%', r'\%').replaceAll('_', r'\_');
      final prefixed = await db.rawQuery(
        "SELECT id FROM entities WHERE id = ? OR id LIKE ? ESCAPE '\\' LIMIT 1",
        [value, '%:$suffix'],
      );
      if (prefixed.isNotEmpty) return '${prefixed.first['id']}';
    }

    final hasAliasTable = await _hasTable(db, 'entity_aliases');
    if (hasAliasTable) {
      final byName = await db.rawQuery(
        '''
        SELECT e.id
        FROM entities e
        LEFT JOIN entity_aliases ea ON ea.entity_id = e.id
        WHERE e.name = ? OR ea.alias = ?
        GROUP BY e.id
        ORDER BY CASE WHEN e.name = ? THEN 0 ELSE 1 END
        LIMIT 1
        ''',
        [value, value, value],
      );
      if (byName.isNotEmpty) return '${byName.first['id']}';
    }
    return null;
  }

  @override
  Future<List<GameDataEntityCandidate>> findEntityCandidates(
    String query, {
    int limit = 8,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    final db = await _open();
    if (db == null) return const [];

    final hasAliasTable = await _hasTable(db, 'entity_aliases');
    if (!hasAliasTable) {
      final rows = await db.rawQuery(
        '''
        SELECT id, name, entity_type, source_type, source_path
        FROM entities
        WHERE name = ? OR name LIKE ? OR aliases LIKE ?
        ORDER BY CASE WHEN name = ? THEN 0 ELSE 1 END, name
        LIMIT ?
        ''',
        [cleanQuery, '%$cleanQuery%', '%$cleanQuery%', cleanQuery, limit],
      );
      return rows
          .map((row) => GameDataEntityCandidate(
                entityId: row['id'] as String,
                name: row['name'] as String,
                entityType: row['entity_type'] as String,
                sourceType: row['source_type'] as String,
                sourcePath: row['source_path'] as String?,
                matchedAlias: row['name'] as String,
                matchType:
                    row['name'] == cleanQuery ? 'name_exact' : 'legacy_like',
                confidence: row['name'] == cleanQuery ? 1.0 : 0.6,
              ),)
          .toList();
    }

    final rows = await db.rawQuery(
      '''
      SELECT e.id, e.name, e.entity_type, e.source_type, e.source_path,
             COALESCE(ea.alias, e.name) AS matched_alias,
             COALESCE(ea.alias_type, 'name') AS alias_type,
             COALESCE(ea.confidence, 1.0) AS confidence,
             MIN(CASE
               WHEN e.name = ? THEN 0
               WHEN ea.alias = ? AND ea.alias_type = 'canonical' THEN 1
               WHEN ea.alias = ? THEN 2
               WHEN e.name LIKE ? THEN 3
               WHEN ea.alias LIKE ? THEN 4
               ELSE 5
             END) AS rank
      FROM entities e
      LEFT JOIN entity_aliases ea ON ea.entity_id = e.id
      WHERE e.name = ?
         OR e.name LIKE ?
         OR ea.alias = ?
         OR ea.alias LIKE ?
      GROUP BY e.id, e.name, e.entity_type, e.source_type, e.source_path
      ORDER BY rank, confidence DESC, e.entity_type, e.name
      LIMIT ?
      ''',
      [
        cleanQuery,
        cleanQuery,
        cleanQuery,
        '%$cleanQuery%',
        '%$cleanQuery%',
        cleanQuery,
        '%$cleanQuery%',
        cleanQuery,
        '%$cleanQuery%',
        limit,
      ],
    );
    return rows
        .map((row) => GameDataEntityCandidate(
              entityId: row['id'] as String,
              name: row['name'] as String,
              entityType: row['entity_type'] as String,
              sourceType: row['source_type'] as String,
              sourcePath: row['source_path'] as String?,
              matchedAlias: row['matched_alias'] as String,
              matchType: candidateMatchType(row['rank'] as int?),
              confidence: (row['confidence'] as num?)?.toDouble() ?? 1.0,
            ),)
        .toList();
  }

  /// Returns every appearance run of [entityId] across stories
  /// (schema v3 `entity_story_mentions`), optionally limited to [scopeFilter]
  /// (canonical scope key, e.g. `activity:act21mini`).
  ///
  /// Empty when the coverage tables are absent (old schema) or the entity has
  /// no recorded mentions.
  @override
  Future<List<StoryCoverageEntry>> searchStoryCoverage({
    required String entityId,
    String? scopeFilter,
  }) async {
    final db = await _open();
    if (db == null || !await _hasTable(db, 'entity_story_mentions')) {
      return const [];
    }
    var sql = '''
      SELECT m.entity_id, m.story_id, m.scope_id, m.line_start, m.line_end,
             m.mention_count, m.matched_alias, p.title
      FROM entity_story_mentions m
      LEFT JOIN story_chapter_profiles p ON p.story_id = m.story_id
      WHERE m.entity_id = ?
    ''';
    final args = <Object?>[entityId.trim()];
    final scope = scopeFilter?.trim();
    if (scope != null && scope.isNotEmpty) {
      sql += ' AND m.scope_id = ?';
      args.add(scope);
    }
    sql += ' ORDER BY m.scope_id, m.story_id, m.line_start';
    final rows = await db.rawQuery(sql, args);
    return [
      for (final row in rows)
        StoryCoverageEntry(
          entityId: '${row['entity_id']}',
          storyId: '${row['story_id']}',
          scopeId: '${row['scope_id']}',
          title: row['title'] as String?,
          lineStart: (row['line_start'] as num).toInt(),
          lineEnd: (row['line_end'] as num).toInt(),
          mentionCount: (row['mention_count'] as num).toInt(),
          matchedAlias: row['matched_alias'] as String?,
        ),
    ];
  }

  /// Reads raw story lines (schema 2 `story_lines`) for [storyId].
  ///
  /// Window semantics: [startLine]/[endLine] bound the range; [maxLines]
  /// limits the page size; [pageToken] (opaque, from a previous page)
  /// continues from that line. Returns [StoryLinesPage] with the next
  /// continuation token when more lines remain.
  @override
  Future<StoryLinesPage> readStoryLines({
    required String storyId,
    int? startLine,
    int? endLine,
    int? maxLines,
    String? pageToken,
  }) async {
    final db = await _open();
    if (db == null) {
      return const StoryLinesPage(lines: [], storyFound: false);
    }
    var fromLine = startLine;
    if (pageToken != null && pageToken.trim().isNotEmpty) {
      fromLine = int.tryParse(pageToken.trim());
    }
    if (fromLine == null || fromLine < 0) fromLine = 0;

    final storyExists = await db.rawQuery(
      'SELECT scope_type, scope_id FROM story_scopes WHERE story_id = ? LIMIT 1',
      [storyId],
    );
    if (storyExists.isEmpty) {
      return const StoryLinesPage(lines: [], storyFound: false);
    }
    final scopeType = '${storyExists.first['scope_type'] ?? ''}'.trim();
    final scopeValue = '${storyExists.first['scope_id'] ?? ''}'.trim();
    final scopeId = scopeType.isEmpty
        ? null
        : scopeValue.isEmpty
            ? scopeType
            : '$scopeType:$scopeValue';

    // R16: 500 so a whole chapter fits one READ (the tool's observation
    // budget still bounds what is returned).
    final limit = (maxLines ?? 30).clamp(1, 500);
    final windowEnd = endLine;
    var sql = 'SELECT line_index, speaker, content FROM story_lines '
        'WHERE story_id = ? AND line_index >= ?';
    final args = <Object?>[storyId, fromLine];
    if (windowEnd != null) {
      sql += ' AND line_index <= ?';
      args.add(windowEnd);
    }
    sql += ' ORDER BY line_index LIMIT ?';
    args.add(limit + 1); // +1 to detect whether more lines follow.
    final rows = await db.rawQuery(sql, args);

    final hasMore = rows.length > limit;
    final pageRows = hasMore ? rows.sublist(0, limit) : rows;
    final lines = [
      for (final row in pageRows)
        StoryLineEntry(
          lineIndex: (row['line_index'] as num).toInt(),
          speaker: row['speaker'] as String?,
          content: '${row['content'] ?? ''}',
        ),
    ];
    final nextPageToken = hasMore && lines.isNotEmpty
        ? '${lines.last.lineIndex + 1}'
        : null;
    return StoryLinesPage(
      lines: lines,
      storyFound: true,
      scopeId: scopeId,
      nextPageToken: nextPageToken,
    );
  }

  /// Returns chapter profiles (schema v3 `story_chapter_profiles`) for the
  /// given [storyIds] or all stories of [scopeId].
  @override
  Future<List<StoryChapterProfile>> getStoryMap({
    List<String>? storyIds,
    String? scopeId,
  }) async {
    final db = await _open();
    if (db == null || !await _hasTable(db, 'story_chapter_profiles')) {
      return const [];
    }
    var sql = 'SELECT * FROM story_chapter_profiles';
    final args = <Object?>[];
    final ids = storyIds
        ?.map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final scope = scopeId?.trim();
    if (ids != null && ids.isNotEmpty) {
      sql +=
          ' WHERE story_id IN (${List.filled(ids.length, '?').join(',')})';
      args.addAll(ids);
    } else if (scope != null && scope.isNotEmpty) {
      sql += ' WHERE scope_id = ?';
      args.add(scope);
    } else {
      return const [];
    }
    sql += ' ORDER BY story_id';
    final rows = await db.rawQuery(sql, args);
    return [
      for (final row in rows) _profileFromRow(row),
    ];
  }

  StoryChapterProfile _profileFromRow(Map<String, Object?> row) {
    List<String> stringList(Object? raw) {
      if (raw is! String) return const [];
      final decoded = _tryDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded) '$item',
      ];
    }

    Map<String, int> intMap(Object? raw) {
      if (raw is! String) return const {};
      final decoded = _tryDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
      };
    }

    return StoryChapterProfile(
      storyId: '${row['story_id']}',
      scopeId: '${row['scope_id']}',
      title: row['title'] as String?,
      lineStart: (row['line_start'] as num).toInt(),
      lineEnd: (row['line_end'] as num).toInt(),
      speakerSet: stringList(row['speaker_set']),
      entityDensity: intMap(row['entity_density']),
      summary: row['summary'] as String?,
    );
  }

  Object? _tryDecode(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      return null;
    }
  }

  /// Returns the subset of [bigrams] that exist in the `rare_terms` table
  /// (schema v3). Used by `find_detail_echoes` as the IDF whitelist.
  Future<Set<String>> filterRareTerms(Iterable<String> bigrams) async {
    final db = await _open();
    if (db == null || !await _hasTable(db, 'rare_terms')) return const {};
    final unique = bigrams.toSet().toList(growable: false);
    if (unique.isEmpty) return const {};
    final rows = await db.rawQuery(
      'SELECT term FROM rare_terms '
      'WHERE term IN (${List.filled(unique.length, '?').join(',')})',
      unique,
    );
    return {
      for (final row in rows) '${row['term']}',
    };
  }

  /// Returns all entity canonical names and aliases, used to exclude entity
  /// names from detail-term extraction so they cannot dominate echo search.
  Future<Set<String>> loadEntityNamesAndAliases() async {
    final db = await _open();
    if (db == null) return const {};
    final names = await db.rawQuery('SELECT name FROM entities');
    final namesSet = {
      for (final row in names) '${row['name']}'.trim(),
    }..remove('');
    if (await _hasTable(db, 'entity_aliases')) {
      final aliases = await db.rawQuery('SELECT alias FROM entity_aliases');
      for (final row in aliases) {
        final alias = '${row['alias']}'.trim();
        if (alias.isNotEmpty) namesSet.add(alias);
      }
    }
    return namesSet;
  }

  /// Searches `story_lines.content` with a LIKE pattern across all stories.
  /// Returns raw rows; callers exclude the source story for echo searches.
  Future<List<Map<String, Object?>>> searchStoryLinesContentLike(
    String term, {
    int limit = 50,
  }) async {
    final db = await _open();
    if (db == null) return const [];
    return db.rawQuery(
      'SELECT story_id, line_index, speaker, content FROM story_lines '
      'WHERE content LIKE ? ORDER BY story_id, line_index LIMIT ?',
      ['%$term%', limit],
    );
  }

  @override
  Future<List<StoryLineHit>> searchStoryLinesLike(
    List<String> terms, {
    String? scopeId,
    int storyLimit = 8,
    int linesPerStory = 3,
  }) async {
    final db = await _open();
    if (db == null) return const [];
    return queryStoryLinesLike(
      db,
      terms,
      scopeId: scopeId,
      storyLimit: storyLimit,
      linesPerStory: linesPerStory,
    );
  }

  /// Vector index of the currently open DB (R12); loaded on first use and
  /// dropped whenever the connection is reopened for a replaced file.
  Future<StoryVectorIndex?>? _vectorIndex;

  Future<StoryVectorIndex?> _loadVectorIndex() async {
    final db = await _open();
    if (db == null) return null;
    return _vectorIndex ??= StoryVectorIndex.load(db);
  }

  @override
  Future<({String model, int dims})?> get storyVectorInfo async {
    final index = await _loadVectorIndex();
    return index == null ? null : (model: index.model, dims: index.dims);
  }

  @override
  Future<List<StoryChunkHit>> searchStoryChunksByVector(
    List<double> queryVector, {
    String? scopeId,
    int topK = 20,
  }) async {
    final index = await _loadVectorIndex();
    if (index == null) return const [];
    return index.search(queryVector, topK: topK, scopeId: scopeId);
  }

  /// LIKE search restricted to a set of story ids (M4b: global term
  /// prioritization for `collect_entity_evidence`). Escapes LIKE wildcards
  /// in [term] so user-provided terms cannot broaden the match.
  @override
  Future<List<Map<String, Object?>>> searchStoryLinesLikeInStories(
    String term,
    List<String> storyIds, {
    int limit = 500,
  }) async {
    final db = await _open();
    if (db == null || storyIds.isEmpty) return const [];
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
  Future<Map<String, StoryCatalogEntry>> storyCatalogEntries(
    Iterable<String> storyIds,
  ) async {
    final db = await _open();
    if (db == null) return const {};
    return queryCatalogEntries(db, storyIds);
  }

  @override
  Future<StoryCollection?> storyCollection(String query) async {
    final db = await _open();
    if (db == null) return null;
    return queryStoryCollection(db, query);
  }

  @override
  Future<List<StoryCatalogEntry>> storiesByCode(String code) async {
    final db = await _open();
    if (db == null) return const [];
    return queryStoriesByCode(db, code);
  }

  @override
  Future<List<({String id, String label, int chapters})>> storyCollectionIndex({
    String? like,
    String? type,
  }) async {
    final db = await _open();
    if (db == null) return const [];
    return queryCollectionIndex(db, like: like, type: type);
  }

  @override
  Future<List<StoryCatalogEntry>> searchStorySynopses(
    List<String> terms, {
    String? collectionId,
    int limit = 5,
  }) async {
    final db = await _open();
    if (db == null) return const [];
    return querySynopsisHits(
      db,
      terms,
      collectionId: collectionId,
      limit: limit,
    );
  }

  /// R15: name inventory of the currently open DB, loaded on first use and
  /// dropped with the connection (like [_vectorIndex]).
  Future<List<NameOccurrence>>? _nameInventory;

  @override
  Future<List<SimilarName>> similarNames(String term, {int limit = 3}) async {
    final db = await _open();
    if (db == null || term.trim().isEmpty) return const [];
    final inventory = await (_nameInventory ??= loadNameInventory(db));
    return rankSimilarNames(term, inventory, limit: limit);
  }

  @override
  Future<Map<String, ({int all, int inScope})>> storyLineTermCounts(
    List<String> terms, {
    String? scopeId,
  }) async {
    final db = await _open();
    if (db == null) return const {};
    return queryTermLineCounts(db, terms, scopeId: scopeId);
  }

  @override
  Future<List<String>> namesInText(String text) async {
    final db = await _open();
    if (db == null || text.trim().isEmpty) return const [];
    final inventory = await (_nameInventory ??= loadNameInventory(db));
    return namesMentionedIn(text, inventory);
  }

  @override
  Future<List<NamedStoryTarget>> namedStoryTargets(String text) async {
    final db = await _open();
    if (db == null) return const [];
    return queryNamedStoryTargets(db, text);
  }

  @override
  Future<SqlQueryResult> readOnlySql(String sql, {int maxRows = 200}) async {
    final path = await _resolveDbPath();
    if (path == null || !File(path).existsSync()) {
      return const SqlQueryResult(error: '本地知识库未安装');
    }
    return runReadOnlySql(path, sql, maxRows: maxRows);
  }

  /// `(content LIKE ? OR speaker LIKE ?) OR …` for [terms], with its args.
  static (String, List<Object?>) _termsClause(List<String> terms) {
    final parts = <String>[];
    final args = <Object?>[];
    for (final term in terms) {
      final escaped = term
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      parts.add(
        "content LIKE ? ESCAPE '\\' OR speaker LIKE ? ESCAPE '\\'",
      );
      args
        ..add('%$escaped%')
        ..add('%$escaped%');
    }
    return ('(${parts.join(' OR ')})', args);
  }

  @override
  Future<List<StoryLineHitRow>> grepStoryLines(
    List<String> terms, {
    Iterable<String>? storyIds,
    int limit = 80,
  }) async {
    final db = await _open();
    final cleaned = [
      for (final t in terms)
        if (t.trim().isNotEmpty) t.trim(),
    ];
    if (db == null || cleaned.isEmpty) return const [];
    final (clause, args) = _termsClause(cleaned);
    final ids = storyIds?.toList();
    if (ids != null && ids.isEmpty) return const [];
    final scope = ids == null
        ? ''
        : ' AND story_id IN (${List.filled(ids.length, '?').join(',')})';
    final rows = await db.rawQuery(
      'SELECT story_id, line_index, speaker, content FROM story_lines '
      'WHERE $clause$scope ORDER BY story_id, line_index LIMIT ?',
      [...args, ...?ids, limit],
    );
    return [
      for (final row in rows)
        StoryLineHitRow(
          storyId: '${row['story_id']}',
          lineIndex: (row['line_index'] as num).toInt(),
          speaker: row['speaker'] as String?,
          content: '${row['content'] ?? ''}',
        ),
    ];
  }

  @override
  Future<Map<String, int>> storyLineHitCounts(
    List<String> terms, {
    Iterable<String>? storyIds,
  }) async {
    final db = await _open();
    final cleaned = [
      for (final t in terms)
        if (t.trim().isNotEmpty) t.trim(),
    ];
    if (db == null || cleaned.isEmpty) return const {};
    final (clause, args) = _termsClause(cleaned);
    final ids = storyIds?.toList();
    if (ids != null && ids.isEmpty) return const {};
    final scope = ids == null
        ? ''
        : ' AND story_id IN (${List.filled(ids.length, '?').join(',')})';
    final rows = await db.rawQuery(
      'SELECT story_id, COUNT(*) AS n FROM story_lines '
      'WHERE $clause$scope GROUP BY story_id',
      [...args, ...?ids],
    );
    return {
      for (final row in rows)
        '${row['story_id']}': (row['n'] as num).toInt(),
    };
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _openedFileStat = null;
    _vectorIndex = null;
    _nameInventory = null;
  }

  Future<sqflite.Database?> _open() async {
    final path = await _resolveDbPath();
    if (path == null) return null;

    // statSync reports a missing file as notFound instead of throwing.
    final stat = File(path).statSync();
    if (stat.type == FileSystemEntityType.notFound) return null;

    if (_db != null &&
        _openedFileStat != null &&
        _sameFileStamp(_openedFileStat!, stat)) {
      return _db;
    }

    // The DB file was replaced (in-app rebuild): close this store's handle
    // and reopen. Safe because R9 guarantees ONE store instance is shared by
    // all tools; previously multiple stores each held a sqflite handle and a
    // single stat-change close() killed the shared connection for the others
    // (database_closed mid-investigation).
    await close();
    await _ensureStoryLinesIndex(path);
    // Creating the index changed the file: remember the stamp it has now.
    final openedStat = File(path).statSync();
    _db = await sqflite.openDatabase(path, readOnly: true);
    _openedFileStat = openedStat;
    return _db;
  }

  /// Paths whose `story_lines` index was checked in this process.
  static final Set<String> _indexChecked = {};

  /// A knowledge base built before v0.10.7 has no index on
  /// `story_lines(story_id, line_index)`, so every read of a chapter scans
  /// ~410k lines (~0.45 s; an answer does dozens of reads). Creates it once
  /// (about a second, +20 MB) through a short writable connection; where the
  /// file cannot be written, reads just stay slower.
  Future<void> _ensureStoryLinesIndex(String path) async {
    if (!_indexChecked.add(path)) return;
    try {
      final db = await sqflite.openDatabase(path);
      try {
        final has = await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ?",
          [storyLinesIndexName],
        );
        if (has.isEmpty && await _hasTable(db, 'story_lines')) {
          await db.execute(storyLinesIndexSql);
        }
      } finally {
        await db.close();
      }
    } catch (_) {
      // Read-only media or a locked file: carry on without the index.
    }
  }

  /// Returns true when [a] and [b] describe the same underlying file content.
  ///
  /// A replace-and-rename swap yields a new file identity: size and
  /// modification/change timestamps differ from the replaced file.
  bool _sameFileStamp(FileStat a, FileStat b) =>
      a.size == b.size && a.modified == b.modified && a.changed == b.changed;

  Future<String?> _resolveDbPath() async {
    if (dbPath != null && dbPath!.trim().isNotEmpty) return dbPath;
    Directory dir = await getApplicationDocumentsDirectory();
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) dir = extDir;
    }
    return p.join(dir.path, 'arklores_gamedata_zh.db');
  }

  Future<List<GameDataSearchResult>> _searchEntities(
    sqflite.Database db,
    String query, {
    required int limit,
    String? contentType,
  }) async {
    final hasAliasTable = await _hasTable(db, 'entity_aliases');
    if (hasAliasTable) {
      final rows = await db.rawQuery(
        '''
        SELECT e.id, e.name, e.entity_type, e.source_type, e.source_path,
               MIN(CASE
                 WHEN e.name = ? THEN 0
                 WHEN ea.alias = ? AND ea.alias_type = 'canonical' THEN 1
                 WHEN ea.alias = ? THEN 2
                 WHEN e.name LIKE ? THEN 3
                 WHEN ea.alias LIKE ? THEN 4
                 ELSE 5
               END) AS rank
        FROM entities e
        LEFT JOIN entity_aliases ea ON ea.entity_id = e.id
        WHERE e.name = ?
           OR e.name LIKE ?
           OR ea.alias = ?
           OR ea.alias LIKE ?
        GROUP BY e.id, e.name, e.entity_type, e.source_type, e.source_path
        ORDER BY rank, e.name
        LIMIT ?
        ''',
        [
          query,
          query,
          query,
          '%$query%',
          '%$query%',
          query,
          '%$query%',
          query,
          '%$query%',
          limit,
        ],
      );
      return _entityRowsToResults(
        db,
        rows,
        query,
        contentType: contentType,
      );
    }

    final rows = await db.rawQuery(
      '''
      SELECT id, name, entity_type, source_type, source_path
      FROM entities
      WHERE name = ? OR name LIKE ? OR aliases LIKE ?
      ORDER BY CASE WHEN name = ? THEN 0 ELSE 1 END, name
      LIMIT ?
      ''',
      [query, '%$query%', '%$query%', query, limit],
    );
    return _entityRowsToResults(
      db,
      rows,
      query,
      contentType: contentType,
    );
  }

  Future<List<GameDataSearchResult>> _entityRowsToResults(
    sqflite.Database db,
    List<Map<String, Object?>> rows,
    String query, {
    String? contentType,
  }) async {
    final results = <GameDataSearchResult>[];
    for (final row in rows) {
      final entityId = row['id'] as String;
      final records = await _recordsForEntity(
        db,
        entityId,
        limit: 2,
        contentType: contentType,
      );
      if (records.isNotEmpty) {
        results.addAll(records.map((result) => _withScore(
              result,
              score: row['name'] == query ? 7600 : 6200,
              retrievalType:
                  row['name'] == query ? 'entity_exact' : 'entity_like',
            ),),);
        continue;
      }
      if (contentType != null && contentType.trim().isNotEmpty) {
        continue;
      }
      results.add(GameDataSearchResult(
        id: 'entity:$entityId',
        score: row['name'] == query ? 10000 : 8000,
        retrievalType: row['name'] == query ? 'entity_exact' : 'entity_like',
        sourceKind: 'GameData',
        sourceType: 'game_data',
        contentType: row['source_type'] as String?,
        entityId: entityId,
        title: row['name'] as String,
        section: row['entity_type'] as String?,
        content: row['name'] as String,
        sourcePath: row['source_path'] as String?,
        rawId: entityId,
      ),);
    }
    return results;
  }

  Future<List<GameDataSearchResult>> _recordsForEntity(
    sqflite.Database db,
    String entityId, {
    required int limit,
    String? contentType,
  }) async {
    final where = StringBuffer('entity_id = ?');
    final args = <Object?>[entityId];
    if (contentType != null && contentType.trim().isNotEmpty) {
      where.write(' AND content_type = ?');
      args.add(contentType.trim());
    }
    args.add(limit);
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM normalized_records
      WHERE $where
      ORDER BY
        CASE content_type
          WHEN 'operator_handbook_profile' THEN 0
          WHEN 'operator_basic_profile' THEN 1
          WHEN 'enemy_profile' THEN 2
          ELSE 3
        END,
        section
      LIMIT ?
      ''',
      args,
    );
    return rows
        .map((row) => _recordResult(row, 7000, 'entity_records'))
        .toList();
  }

  Future<List<GameDataSearchResult>> _recordsByContentType(
    sqflite.Database db,
    String contentType, {
    required int limit,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM normalized_records
      WHERE content_type = ?
      ORDER BY title, raw_id
      LIMIT ?
      ''',
      [contentType.trim(), limit],
    );
    return rows
        .map((row) => _recordResult(row, 4500, 'content_type_records'))
        .toList();
  }

  Future<List<GameDataSearchResult>> _chunksForEntity(
    sqflite.Database db,
    String entityId, {
    required int limit,
    String? contentType,
  }) async {
    final where = StringBuffer('entity_id = ?');
    final args = <Object?>[entityId];
    if (contentType != null && contentType.trim().isNotEmpty) {
      where.write(' AND content_type = ?');
      args.add(contentType.trim());
    }
    args.add(limit);
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM lore_chunks
      WHERE $where
      ORDER BY
        CASE content_type
          WHEN 'operator_handbook_profile' THEN 0
          WHEN 'operator_basic_profile' THEN 1
          WHEN 'operator_module' THEN 2
          WHEN 'skin_description' THEN 3
          WHEN 'enemy_profile' THEN 4
          WHEN 'item_description' THEN 5
          WHEN 'operator_voice' THEN 6
          ELSE 7
        END,
        section
      LIMIT ?
      ''',
      args,
    );
    return rows.map((row) => _chunkResult(row, 9000, 'entity_chunks')).toList();
  }

  Future<List<GameDataSearchResult>> _chunksByContentType(
    sqflite.Database db,
    String contentType, {
    required int limit,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM lore_chunks
      WHERE content_type = ?
      ORDER BY page_title, raw_id
      LIMIT ?
      ''',
      [contentType.trim(), limit],
    );
    return rows
        .map((row) => _chunkResult(row, 3500, 'content_type_chunks'))
        .toList();
  }

  Future<List<GameDataSearchResult>> _searchStoryChunksLike(
    sqflite.Database db,
    String query, {
    required Set<String> entityNames,
    required int limit,
  }) async {
    final terms = storySearchTerms(query, entityNames: entityNames);
    if (terms.isEmpty) return const [];

    final where = StringBuffer(
      "(source_type = 'game_story' OR content_category = 'story')",
    );
    final args = <Object?>[];
    for (final term in terms) {
      where.write(
        ' AND (page_title LIKE ? OR section LIKE ? OR content LIKE ? OR raw_id LIKE ?)',
      );
      final pattern = '%$term%';
      args.addAll([pattern, pattern, pattern, pattern]);
    }
    args.add(limit);

    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM lore_chunks
      WHERE $where
      ORDER BY
        CASE
          WHEN content LIKE ? THEN 0
          WHEN page_title LIKE ? THEN 1
          ELSE 2
        END,
        page_title
      LIMIT ?
      ''',
      [
        ...args.take(args.length - 1),
        '%${terms.first}%',
        '%${terms.first}%',
        limit,
      ],
    );
    return rows
        .map((row) => _chunkResult(row, 8800, 'summary_story_context'))
        .toList();
  }

  Future<List<String>> _entityNamesById(
    sqflite.Database db,
    String entityId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT name
      FROM entities
      WHERE id = ?
      LIMIT 1
      ''',
      [entityId],
    );
    return [
      for (final row in rows)
        if ((row['name'] as String?)?.trim().isNotEmpty == true)
          (row['name'] as String).trim(),
    ];
  }

  Future<List<GameDataSearchResult>> _documentsForEntity(
    sqflite.Database db,
    String entityId, {
    required int limit,
    String? contentType,
  }) async {
    if (contentType != null && contentType.trim().isNotEmpty) {
      return const [];
    }
    if (!await _hasTable(db, 'entity_documents')) return const [];

    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM entity_documents
      WHERE entity_id = ?
      ORDER BY
        CASE document_type
          WHEN 'operator_profile_bundle' THEN 0
          ELSE 1
        END,
        title
      LIMIT ?
      ''',
      [entityId, limit],
    );
    return rows
        .map((row) => _documentResult(row, 12000, 'entity_document'))
        .toList();
  }

  Future<List<GameDataSearchResult>> _searchDocumentsFts(
    sqflite.Database db,
    String query, {
    required int limit,
    String? entityId,
  }) async {
    if (!await _hasTable(db, 'entity_documents_fts')) return const [];

    final where = StringBuffer('entity_documents_fts MATCH ?');
    final args = <Object?>[ftsQuery(query)];
    if (entityId != null && entityId.trim().isNotEmpty) {
      where.write(' AND ed.entity_id = ?');
      args.add(entityId.trim());
    }
    args.add(limit);

    try {
      final rows = await db.rawQuery(
        '''
        SELECT ed.*
        FROM entity_documents_fts
        JOIN entity_documents ed ON ed.rowid = entity_documents_fts.rowid
        WHERE $where
        LIMIT ?
        ''',
        args,
      );
      return rows
          .map((row) => _documentResult(row, 8500, 'entity_document_fts'))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<GameDataSearchResult>> _searchDocumentsLike(
    sqflite.Database db,
    String query, {
    required int limit,
    String? entityId,
  }) async {
    if (!await _hasTable(db, 'entity_documents')) return const [];

    final terms = query
        .split(RegExp(r'\s+'))
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return const [];

    final where = StringBuffer();
    final args = <Object?>[];
    for (var i = 0; i < terms.length; i++) {
      if (i > 0) where.write(' AND ');
      where.write('''
        (entity_name LIKE ? OR title LIKE ? OR summary LIKE ? OR content LIKE ?)
      ''');
      final pattern = '%${terms[i]}%';
      args.addAll([pattern, pattern, pattern, pattern]);
    }
    if (entityId != null && entityId.trim().isNotEmpty) {
      where.write(' AND entity_id = ?');
      args.add(entityId.trim());
    }
    args.add(limit);

    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM entity_documents
      WHERE $where
      ORDER BY
        CASE document_type
          WHEN 'operator_profile_bundle' THEN 0
          ELSE 1
        END,
        title
      LIMIT ?
      ''',
      args,
    );
    return rows
        .map((row) => _documentResult(row, 8000, 'entity_document_like'))
        .toList();
  }

  Future<List<GameDataSearchResult>> _searchRecordsLike(
    sqflite.Database db,
    String query, {
    required int limit,
    String? contentType,
    String? entityId,
  }) async {
    final terms = searchTerms(query);
    if (terms.isEmpty) return const [];
    final where = StringBuffer();
    final args = <Object?>[];
    for (var i = 0; i < terms.length; i++) {
      if (i > 0) where.write(' AND ');
      where.write(
        '(title LIKE ? OR entity_name LIKE ? OR content LIKE ? OR raw_id LIKE ?)',
      );
      final pattern = '%${terms[i]}%';
      args.addAll([pattern, pattern, pattern, pattern]);
    }
    if (contentType != null && contentType.trim().isNotEmpty) {
      where.write(' AND content_type = ?');
      args.add(contentType.trim());
    }
    if (entityId != null && entityId.trim().isNotEmpty) {
      where.write(' AND entity_id = ?');
      args.add(entityId.trim());
    }
    args.add(limit);
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM normalized_records
      WHERE $where
      ORDER BY
        CASE
          WHEN title = ? THEN 0
          WHEN entity_name = ? THEN 1
          WHEN title LIKE ? THEN 2
          ELSE 3
        END,
        content_type,
        title
      LIMIT ?
      ''',
      [...args.take(args.length - 1), query, query, '%$query%', limit],
    );
    return rows.map((row) => _recordResult(row, 5000, 'record_like')).toList();
  }

  Future<List<GameDataSearchResult>> _searchChunksFts(
    sqflite.Database db,
    String query, {
    required int limit,
    String? contentType,
    String? entityId,
  }) async {
    final where = StringBuffer('lore_chunks_fts MATCH ?');
    final args = <Object?>[ftsQuery(query)];
    if (contentType != null && contentType.trim().isNotEmpty) {
      where.write(' AND lc.content_type = ?');
      args.add(contentType.trim());
    }
    if (entityId != null && entityId.trim().isNotEmpty) {
      where.write(' AND lc.entity_id = ?');
      args.add(entityId.trim());
    }
    args.add(limit);
    try {
      final rows = await db.rawQuery(
        '''
        SELECT lc.*
        FROM lore_chunks_fts
        JOIN lore_chunks lc ON lc.rowid = lore_chunks_fts.rowid
        WHERE $where
        LIMIT ?
        ''',
        args,
      );
      return rows.map((row) => _chunkResult(row, 4000, 'fts')).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<GameDataSearchResult>> _searchChunksLike(
    sqflite.Database db,
    String query, {
    required int limit,
    String? contentType,
    String? entityId,
  }) async {
    final terms = searchTerms(query);
    if (terms.isEmpty) return const [];
    final where = StringBuffer();
    final args = <Object?>[];
    for (var i = 0; i < terms.length; i++) {
      if (i > 0) where.write(' AND ');
      where.write(
        '(page_title LIKE ? OR section LIKE ? OR content LIKE ? OR raw_id LIKE ?)',
      );
      final pattern = '%${terms[i]}%';
      args.addAll([pattern, pattern, pattern, pattern]);
    }
    if (contentType != null && contentType.trim().isNotEmpty) {
      where.write(' AND content_type = ?');
      args.add(contentType.trim());
    }
    if (entityId != null && entityId.trim().isNotEmpty) {
      where.write(' AND entity_id = ?');
      args.add(entityId.trim());
    }
    args.add(limit);
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM lore_chunks
      WHERE $where
      ORDER BY
        CASE
          WHEN page_title = ? THEN 0
          WHEN page_title LIKE ? THEN 1
          ELSE 2
        END,
        content_type,
        page_title
      LIMIT ?
      ''',
      [...args.take(args.length - 1), query, '%$query%', limit],
    );
    return rows.map((row) => _chunkResult(row, 3000, 'chunk_like')).toList();
  }

  Future<List<GameDataSearchResult>> _searchScopedStoryEvidence(
    sqflite.Database db, {
    required String query,
    required String scopeId,
    required String entityId,
    required int limit,
  }) async {
    final scopeParts = scopeId.trim().split(':');
    if (scopeParts.length != 2) return const [];
    final scopeType = scopeParts.first.trim();
    final scope = scopeParts.last.trim();
    final names = await _entityNamesById(db, entityId.trim());
    final terms = searchTerms(query);
    if (scopeType.isEmpty || scope.isEmpty || names.isEmpty || terms.isEmpty) {
      return const [];
    }
    final where = StringBuffer(
      "source_type = 'game_story' AND scope_type = ? AND scope_id = ? AND "
      '(${List.filled(names.length, 'content LIKE ?').join(' OR ')})',
    );
    final args = <Object?>[
      scopeType,
      scope,
      for (final name in names) '%$name%',
    ];
    for (final term in terms) {
      where
          .write(' AND (content LIKE ? OR page_title LIKE ? OR raw_id LIKE ?)');
      args.addAll(['%$term%', '%$term%', '%$term%']);
    }
    final rows = await db.rawQuery(
      '''
      SELECT * FROM lore_chunks
      WHERE $where
      ORDER BY story_id, raw_id
      LIMIT 200
      ''',
      args,
    );
    final ranked = rows.toList(growable: false)
      ..sort((left, right) {
        final proximity = evidenceProximity(
          left['content'] as String,
          names: names,
          terms: terms,
        ).compareTo(
          evidenceProximity(
            right['content'] as String,
            names: names,
            terms: terms,
          ),
        );
        if (proximity != 0) return proximity;
        return '${left['story_id']}:${left['raw_id']}'
            .compareTo('${right['story_id']}:${right['raw_id']}');
      });
    return ranked
        .take(limit)
        .map((row) => _chunkResult(row, 15000, 'scoped_story_evidence'))
        .toList(growable: false);
  }

  GameDataSearchResult _recordResult(
    Map<String, Object?> row,
    double score,
    String retrievalType,
  ) {
    return GameDataSearchResult(
      id: row['id'] as String,
      score: score,
      retrievalType: retrievalType,
      sourceKind: 'GameData',
      sourceType: 'game_data',
      contentCategory: row['category'] as String?,
      contentSubtype: row['subtype'] as String?,
      contentType: row['content_type'] as String?,
      entityId: row['entity_id'] as String?,
      title: (row['title'] ?? row['entity_name'] ?? row['raw_id'] ?? 'GameData')
          as String,
      section: row['section'] as String?,
      content: row['content'] as String,
      sourcePath: row['source_path'] as String?,
      rawId: row['raw_id'] as String?,
      lineStart: row['line_start'] as int?,
      lineEnd: row['line_end'] as int?,
      rankingReason: rankingReason(retrievalType),
    );
  }

  GameDataSearchResult _documentResult(
    Map<String, Object?> row,
    double score,
    String retrievalType,
  ) {
    return GameDataSearchResult(
      id: row['id'] as String,
      score: score,
      retrievalType: retrievalType,
      sourceKind: 'GameData',
      sourceType: 'game_data',
      contentCategory: row['entity_type'] as String?,
      contentSubtype: row['document_type'] as String?,
      contentType: row['document_type'] as String?,
      entityId: row['entity_id'] as String?,
      title: row['title'] as String,
      section: 'entity_document',
      content: row['content'] as String,
      sourcePath: row['source_paths'] as String?,
      rawId: row['entity_id'] as String?,
      rankingReason: rankingReason(retrievalType),
    );
  }

  Future<bool> _hasTable(sqflite.Database db, String tableName) async {
    final rows = await db.rawQuery(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name = ?
      LIMIT 1
      ''',
      [tableName],
    );
    return rows.isNotEmpty;
  }

  GameDataSearchResult _chunkResult(
    Map<String, Object?> row,
    double score,
    String retrievalType,
  ) {
    return GameDataSearchResult(
      id: row['id'] as String,
      score: score,
      retrievalType: retrievalType,
      sourceKind: 'GameData',
      sourceType: row['source_type'] as String,
      contentCategory: row['content_category'] as String?,
      contentSubtype: row['content_subtype'] as String?,
      contentType: row['content_type'] as String?,
      entityId: row['entity_id'] as String?,
      storyId: row['story_id'] as String?,
      title: (row['page_title'] ?? row['raw_id'] ?? 'GameData') as String,
      section: row['section'] as String?,
      content: row['content'] as String,
      sourcePath: row['source_path'] as String?,
      rawId: row['raw_id'] as String?,
      lineStart: row['line_start'] as int?,
      lineEnd: row['line_end'] as int?,
      rankingReason: rankingReason(retrievalType),
    );
  }

  GameDataSearchResult _withScore(
    GameDataSearchResult result, {
    required double score,
    required String retrievalType,
  }) {
    return GameDataSearchResult(
      id: result.id,
      score: score,
      retrievalType: retrievalType,
      sourceKind: result.sourceKind,
      sourceType: result.sourceType,
      contentCategory: result.contentCategory,
      contentSubtype: result.contentSubtype,
      contentType: result.contentType,
      entityId: result.entityId,
      storyId: result.storyId,
      title: result.title,
      section: result.section,
      content: result.content,
      sourcePath: result.sourcePath,
      rawId: result.rawId,
      lineStart: result.lineStart,
      lineEnd: result.lineEnd,
      rankingReason: rankingReason(retrievalType),
    );
  }
}
