import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'build/gamedata_schema.dart' show storyLinesIndexName, storyLinesIndexSql;
import 'game_retrieval.dart';
import 'name_similarity.dart';
import 'readonly_sql.dart';
import 'story_catalog.dart';
import 'story_line_search.dart';
import 'story_vectors.dart';

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

  GameDataKnowledgeStore({this.dbPath, this.game = Game.arknights});
  final String? dbPath;

  /// Which game's database this store reads (its own file).
  final Game game;
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
    Map<String, int>? termLines,
  }) async {
    final db = await _open();
    if (db == null) return const [];
    return queryStoryLinesLike(
      db,
      terms,
      scopeId: scopeId,
      storyLimit: storyLimit,
      linesPerStory: linesPerStory,
      termLines: termLines,
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
  Future<List<RecordHit>> searchRecordsLike(
    List<String> terms, {
    int limit = 3,
  }) async {
    final db = await _open();
    final cleaned = [
      for (final t in terms.take(6))
        if (t.trim().isNotEmpty) t.trim(),
    ];
    if (db == null || cleaned.isEmpty || !await _hasTable(db, 'normalized_records')) {
      return const [];
    }
    // A record about the thing a term names (its entity_name is the term)
    // first, then title matches, then text matches.
    final score = <String>[];
    final where = <String>[];
    final args = <Object?>[];
    final whereArgs = <Object?>[];
    for (final term in cleaned) {
      final like = '%${escapeLike(term)}%';
      score.add('(CASE WHEN entity_name = ? THEN 3 ELSE 0 END) + '
          "(CASE WHEN title LIKE ? ESCAPE '\\' THEN 2 ELSE 0 END) + "
          "(CASE WHEN content LIKE ? ESCAPE '\\' THEN 1 ELSE 0 END)");
      args.addAll([term, like, like]);
      where.add("entity_name = ? OR title LIKE ? ESCAPE '\\' "
          "OR content LIKE ? ESCAPE '\\'");
      whereArgs.addAll([term, like, like]);
    }
    final scoreSql = score.join(' + ');
    final whereSql = where.join(' OR ');
    // Story text is searched in story_lines; its copies here are left out.
    final rows = await db.rawQuery(
      'SELECT id, category, subtype, entity_name, title, content, '
      '($scoreSql) AS s '
      'FROM normalized_records '
      "WHERE category != 'story' AND COALESCE(subtype, '') != 'story' "
      'AND ($whereSql) '
      'ORDER BY s DESC, length(content) DESC LIMIT ?',
      [...args, ...whereArgs, limit],
    );
    // 0.14 live: an operator's file (race, record, archives) is one
    // document in entity_documents, not in normalized_records.
    final documents = await _hasTable(db, 'entity_documents')
        ? await db.rawQuery(
            'SELECT id, entity_type AS category, document_type AS subtype, '
            'entity_name, title, content, ($scoreSql) AS s '
            'FROM entity_documents WHERE $whereSql '
            'ORDER BY s DESC, length(content) DESC LIMIT ?',
            [...args, ...whereArgs, limit],
          )
        : const <Map<String, Object?>>[];
    final hits = [
      for (final (i, row) in [...rows, ...documents].indexed)
        RecordHit(
          // Every id of an Endfield database starts with ef/ (game.dart);
          // the v0.12.0 asset's documents do not yet.
          id: i >= rows.length && game == Game.endfield
              ? endfieldId('${row['id']}')
              : '${row['id']}',
          category: '${row['category'] ?? ''}',
          subtype: '${row['subtype'] ?? ''}',
          title: '${row['title'] ?? ''}',
          snippet: _around(
            '${row['content'] ?? ''}',
            cleaned,
            subject: '${row['entity_name'] ?? ''}',
          ),
          score: (row['s'] as num?)?.toInt() ?? 0,
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  /// About 120 characters of [text] around the first of [terms] found; a
  /// record about [subject] is shown around the other terms when it has
  /// them (its subject's name is everywhere in it).
  static String _around(String text, List<String> terms, {String subject = ''}) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    var at = -1;
    final others = [
      for (final t in terms)
        if (t != subject && flat.contains(t)) t,
    ];
    for (final t in others.isEmpty ? terms : others) {
      final i = flat.indexOf(t);
      if (i >= 0 && (at < 0 || i < at)) at = i;
    }
    final start = at < 40 ? 0 : at - 40;
    final end = start + 120 > flat.length ? flat.length : start + 120;
    return '${start > 0 ? '…' : ''}${flat.substring(start, end)}'
        '${end < flat.length ? '…' : ''}';
  }

  @override
  Future<SqlQueryResult> readOnlySql(
    String sql, {
    int maxRows = 200,
    Game? game,
  }) async {
    // One store is one game's database; [game] picks between stores in a
    // [MultiGameRetrieval].
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

  /// The open in progress, so tools running at once (one turn's calls run
  /// together) share it instead of each closing and reopening the handle.
  Future<sqflite.Database?>? _opening;

  Future<sqflite.Database?> _open() {
    final pending = _opening;
    if (pending != null) return pending;
    final opening = _openNow();
    _opening = opening;
    return opening.whenComplete(() => _opening = null);
  }

  Future<sqflite.Database?> _openNow() async {
    final path = await _resolveDbPath();
    if (path == null) return null;

    // statSync reports a missing file as notFound instead of throwing.
    final stat = File(path).statSync();
    if (stat.type == FileSystemEntityType.notFound) return null;

    // A handle closed behind this store's back (anything that once opened
    // the same path with sqflite's shared instance and closed it) is opened
    // again instead of failing every later query with database_closed.
    if (_db != null &&
        _db!.isOpen &&
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
    // Its own connection: nothing else that opens this file can close it.
    _db = await sqflite.openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );
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
      final db = await sqflite.openDatabase(path, singleInstance: false);
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
    return p.join(dir.path, game.dbFileName);
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
