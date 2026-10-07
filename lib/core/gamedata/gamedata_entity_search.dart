part of 'gamedata_knowledge_store.dart';

/// The multi-stage structured search behind [GameDataKnowledgeStore.search]
/// (entities and aliases, documents, records, chunks; FTS and LIKE), used by
/// the role-play agent's `search_local_lore`.
extension _EntitySearch on GameDataKnowledgeStore {
  Future<List<GameDataSearchResult>> _search({
    required String query,
    required int topK,
    String? contentType,
    String? entityId,
    required String searchMode,
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
