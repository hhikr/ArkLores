import 'dart:io';
import 'dart:isolate';

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

part 'gamedata_entity_search.dart';

/// The vector index of [db]'s file, read in a background isolate
/// ([StoryVectorIndex.loadFile]); through [db] itself when that fails (no
/// FFI SQLite). Top level so the isolate's closure captures only the path.
Future<StoryVectorIndex?> _loadVectorsInBackground(sqflite.Database db) async {
  final path = db.path;
  try {
    return await Isolate.run(() => StoryVectorIndex.loadFile(path));
  } catch (_) {
    return StoryVectorIndex.load(db);
  }
}

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
  }) =>
      _search(
        query: query,
        topK: topK,
        contentType: contentType,
        entityId: entityId,
        searchMode: searchMode,
        scopeId: scopeId,
      );

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
      final suffix = escapeLike(value);
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
    final kindColumn = await storyLinesHaveKind(db) ? ', kind' : '';
    var sql = 'SELECT line_index, speaker, content$kindColumn FROM story_lines '
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
          kind: row['kind'] as String?,
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
    return _vectorIndex ??= _loadVectorsInBackground(db);
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
      final escaped = escapeLike(term);
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

  /// Runs [action] on the open knowledge base (read-only); null when none is
  /// installed. For callers that need their own queries (the library pages).
  Future<R?> withDatabase<R>(
    Future<R> Function(sqflite.DatabaseExecutor db) action,
  ) async {
    final db = await _open();
    if (db == null) return null;
    return action(db);
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
}
