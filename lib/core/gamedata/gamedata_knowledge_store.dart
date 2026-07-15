import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

class GameDataSearchResult {
  final String id;
  final double score;
  final String retrievalType;
  final String sourceKind;
  final String sourceType;
  final String? contentCategory;
  final String? contentSubtype;
  final String? contentType;
  final String? entityId;
  final String? storyId;
  final String title;
  final String? section;
  final String content;
  final String? sourcePath;
  final String? rawId;
  final int? lineStart;
  final int? lineEnd;
  final String rankingReason;

  const GameDataSearchResult({
    required this.id,
    required this.score,
    required this.retrievalType,
    required this.sourceKind,
    required this.sourceType,
    required this.title,
    required this.content,
    this.contentCategory,
    this.contentSubtype,
    this.contentType,
    this.entityId,
    this.storyId,
    this.section,
    this.sourcePath,
    this.rawId,
    this.lineStart,
    this.lineEnd,
    this.rankingReason = 'structured GameData match',
  });
}

class GameDataEntityCandidate {
  final String entityId;
  final String name;
  final String entityType;
  final String sourceType;
  final String? sourcePath;
  final String matchedAlias;
  final String matchType;
  final double confidence;

  const GameDataEntityCandidate({
    required this.entityId,
    required this.name,
    required this.entityType,
    required this.sourceType,
    required this.matchedAlias,
    required this.matchType,
    required this.confidence,
    this.sourcePath,
  });
}

class GameDataKnowledgeStore {
  final String? dbPath;
  sqflite.Database? _db;

  GameDataKnowledgeStore({this.dbPath});

  Future<bool> get isAvailable async {
    final path = await _resolveDbPath();
    return path != null && File(path).existsSync();
  }

  Future<List<GameDataSearchResult>> search({
    required String query,
    int topK = 5,
    String? contentType,
    String? entityId,
    String searchMode = 'general',
    String? scopeId,
  }) async {
    final plan =
        _GameDataQueryPlan.from(query, explicitContentType: contentType);
    final cleanQuery = plan.originalQuery;
    if (cleanQuery.isEmpty) return const [];
    final db = await _open();
    if (db == null) return const [];

    final limit = topK.clamp(1, 10);
    final byId = <String, GameDataSearchResult>{};
    final effectiveContentType = plan.effectiveContentType;

    final summaryMode = searchMode == 'summary';
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
              ))
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
              matchType: _candidateMatchType(row['rank'] as int?),
              confidence: (row['confidence'] as num?)?.toDouble() ?? 1.0,
            ))
        .toList();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<sqflite.Database?> _open() async {
    if (_db != null) return _db;
    final path = await _resolveDbPath();
    if (path == null || !await File(path).exists()) return null;
    _db = await sqflite.openDatabase(path, readOnly: true);
    return _db;
  }

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
            )));
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
      ));
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
    final terms = _storySearchTerms(query, entityNames: entityNames);
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
    final args = <Object?>[_ftsQuery(query)];
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
    final terms = _searchTerms(query);
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
    final args = <Object?>[_ftsQuery(query)];
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
    final terms = _searchTerms(query);
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
    final terms = _searchTerms(query);
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
    args.add(limit);
    final rows = await db.rawQuery(
      '''
      SELECT * FROM lore_chunks
      WHERE $where
      ORDER BY story_id, raw_id
      LIMIT ?
      ''',
      args,
    );
    return rows
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
      rankingReason: _rankingReason(retrievalType),
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
      rankingReason: _rankingReason(retrievalType),
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
      rankingReason: _rankingReason(retrievalType),
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
      rankingReason: _rankingReason(retrievalType),
    );
  }
}

String _candidateMatchType(int? rank) {
  switch (rank) {
    case 0:
      return 'name_exact';
    case 1:
      return 'canonical_alias_exact';
    case 2:
      return 'alias_exact';
    case 3:
      return 'name_like';
    case 4:
      return 'alias_like';
    default:
      return 'unknown';
  }
}

bool _hasStoryIntent(String query) {
  return query.contains(RegExp(r'(主线|剧情|故事|时间线|事件|章节|关卡|行动)'));
}

class _GameDataQueryPlan {
  final String originalQuery;
  final String entityQuery;
  final List<String> searchQueries;
  final String? effectiveContentType;
  final bool hasStoryIntent;

  const _GameDataQueryPlan({
    required this.originalQuery,
    required this.entityQuery,
    required this.searchQueries,
    required this.effectiveContentType,
    required this.hasStoryIntent,
  });

  factory _GameDataQueryPlan.from(
    String query, {
    String? explicitContentType,
  }) {
    final original = query.trim();
    final normalized = original.replaceAll(RegExp(r'\s+'), ' ');
    final inferredContentType = explicitContentType?.trim().isNotEmpty == true
        ? explicitContentType!.trim()
        : _inferContentType(normalized);
    final entityQuery = _entityFocusedQuery(normalized);
    final queries = <String>{
      normalized,
      if (entityQuery.isNotEmpty) entityQuery,
      ..._expandedQueryAliases(normalized),
      ..._expandedQueryAliases(entityQuery),
    }.where((value) => value.trim().isNotEmpty).toList(growable: false);

    return _GameDataQueryPlan(
      originalQuery: original,
      entityQuery: entityQuery.isEmpty ? normalized : entityQuery,
      searchQueries: queries,
      effectiveContentType: inferredContentType,
      hasStoryIntent: _hasStoryIntent(normalized),
    );
  }
}

String? _inferContentType(String query) {
  if (query.contains('语音')) return 'operator_voice';
  if (query.contains('秘录')) return 'operator_record_story';
  if (query.contains('模组')) return 'operator_module';
  if (query.contains('档案')) return 'operator_handbook_profile';
  if (query.contains('敌人')) return 'enemy_profile';
  return null;
}

String _entityFocusedQuery(String query) {
  var focused = query;
  for (final term in _queryIntentTerms) {
    focused = focused.replaceAll(term, ' ');
  }
  return focused.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> _expandedQueryAliases(String query) {
  if (query.trim().isEmpty) return const [];
  final expanded = <String>{};
  if (query.contains('肉鸽')) {
    expanded.add(query.replaceAll('肉鸽', '集成战略'));
    expanded.add('$query 集成战略 傀影与猩红孤钻 水月与深蓝之树 探索者的银凇止境 萨卡兹的无终奇语');
  }
  if (query.contains('集成战略')) {
    expanded.add('$query 肉鸽');
  }
  if (query.contains('收藏品')) {
    expanded.add('$query relic collection');
  }
  if (query.contains('语音')) {
    expanded.add(query.replaceAll('语音', 'operator_voice charword'));
  }
  if (query.contains('档案')) {
    expanded.add(query.replaceAll('档案', 'operator_handbook_profile handbook'));
  }
  if (query.contains('秘录')) {
    expanded.add(query.replaceAll('秘录', 'operator_record_story story_review'));
  }
  if (query.contains('模组')) {
    expanded.add(query.replaceAll('模组', 'operator_module uniequip'));
  }
  return expanded.toList(growable: false);
}

const _queryIntentTerms = {
  '语音',
  '档案',
  '秘录',
  '模组',
  '主线',
  '剧情',
  '故事',
  '时间线',
  '事件',
  '章节',
  '关卡',
  '行动',
  '相关',
  '梗概',
  '介绍',
};

List<String> _storySearchTerms(
  String query, {
  required Set<String> entityNames,
}) {
  final terms = <String>[];
  final normalized = query.trim();

  for (final entityName in entityNames) {
    final clean = entityName.trim();
    if (clean.isNotEmpty && normalized.contains(clean)) {
      terms.add(clean);
    }
  }

  if (terms.isEmpty) {
    terms.addAll(
      normalized
          .split(RegExp(r'\s+'))
          .map((term) => term.trim())
          .where((term) => term.isNotEmpty)
          .where((term) => !_isStoryIntentTerm(term)),
    );
  }

  return terms.toSet().take(3).toList(growable: false);
}

bool _isStoryIntentTerm(String term) {
  return const {
    '主线',
    '剧情',
    '故事',
    '时间线',
    '事件',
    '章节',
    '关卡',
    '行动',
    '相关',
    '梗概',
  }.contains(term);
}

String _rankingReason(String retrievalType) {
  if (retrievalType == 'entity_document') {
    return 'entity document exact match; highest priority for summaries';
  }
  if (retrievalType == 'entity_exact') {
    return 'exact entity match; authoritative structured GameData record';
  }
  if (retrievalType == 'summary_story_context') {
    return 'summary mode story context for the resolved entity';
  }
  if (retrievalType == 'entity_chunks') {
    return 'structured entity chunk match';
  }
  if (retrievalType == 'entity_records') {
    return 'structured entity raw record match';
  }
  if (retrievalType == 'entity_document_fts') {
    return 'entity document full-text match';
  }
  if (retrievalType == 'entity_document_like') {
    return 'entity document keyword fallback';
  }
  if (retrievalType == 'fts') {
    return 'lore chunk full-text match';
  }
  if (retrievalType.endsWith('_like') || retrievalType == 'record_like') {
    return 'keyword fallback match';
  }
  return 'structured GameData match';
}

String _ftsQuery(String query) {
  final terms = _searchTerms(query)
      .map((term) => term.replaceAll('"', '""'))
      .toList(growable: false);
  if (terms.isEmpty) return '""';
  return terms.map((term) => '"$term"').join(' ');
}

List<String> _searchTerms(String query) {
  return query
      .trim()
      .split(RegExp(r'\s+'))
      .map((term) => term.trim())
      .where((term) => term.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
