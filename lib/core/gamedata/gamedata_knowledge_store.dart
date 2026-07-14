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
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    final db = await _open();
    if (db == null) return const [];

    final limit = topK.clamp(1, 10);
    final byId = <String, GameDataSearchResult>{};

    if (entityId == null) {
      for (final result in await _searchEntities(
        db,
        cleanQuery,
        limit: limit,
        contentType: contentType,
      )) {
        byId[result.id] = result;
      }
    }

    final entityIds = <String>{
      if (entityId != null && entityId.trim().isNotEmpty) entityId.trim(),
      for (final result in byId.values)
        if (result.entityId != null) result.entityId!,
    };

    for (final id in entityIds.take(5)) {
      for (final result in await _recordsForEntity(
        db,
        id,
        limit: limit,
        contentType: contentType,
      )) {
        byId.putIfAbsent(result.id, () => result);
      }
    }

    for (final result in await _searchRecordsLike(
      db,
      cleanQuery,
      limit: limit * 2,
      contentType: contentType,
      entityId: entityId,
    )) {
      byId.putIfAbsent(result.id, () => result);
    }

    for (final result in await _searchChunksFts(
      db,
      cleanQuery,
      limit: limit * 2,
      contentType: contentType,
      entityId: entityId,
    )) {
      byId.putIfAbsent(result.id, () => result);
    }

    for (final result in await _searchChunksLike(
      db,
      cleanQuery,
      limit: limit * 2,
      contentType: contentType,
      entityId: entityId,
    )) {
      byId.putIfAbsent(result.id, () => result);
    }

    final results = byId.values.toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        if (score != 0) return score;
        return a.title.compareTo(b.title);
      });
    return results.take(limit).toList();
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
              score: row['name'] == query ? 10000 : 8000,
              retrievalType:
                  row['name'] == query ? 'entity_exact' : 'entity_like',
            )));
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

  Future<List<GameDataSearchResult>> _searchRecordsLike(
    sqflite.Database db,
    String query, {
    required int limit,
    String? contentType,
    String? entityId,
  }) async {
    final where = StringBuffer(
      '(title LIKE ? OR entity_name LIKE ? OR content LIKE ? OR raw_id LIKE ?)',
    );
    final args = <Object?>['%$query%', '%$query%', '%$query%', '%$query%'];
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
    final where = StringBuffer(
      '(page_title LIKE ? OR section LIKE ? OR content LIKE ? OR raw_id LIKE ?)',
    );
    final args = <Object?>['%$query%', '%$query%', '%$query%', '%$query%'];
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
    );
  }
}

String _ftsQuery(String query) {
  final escaped = query.replaceAll('"', '""').trim();
  if (escaped.isEmpty) return '""';
  return '"$escaped"';
}
