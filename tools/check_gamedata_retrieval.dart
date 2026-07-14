import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _defaultDbPath = 'build/gamedata_mobile/arklores_gamedata_zh.db';

const _queries = <_RetrievalCheck>[
  _RetrievalCheck('阿米娅', expectedContentType: 'operator_profile_bundle'),
  _RetrievalCheck('阿米娅 语音', expectedContentType: 'operator_voice'),
  _RetrievalCheck('阿米娅 主线', storyIntent: true),
  _RetrievalCheck('莱茵生命'),
  _RetrievalCheck('萨卡兹王庭'),
  _RetrievalCheck('特蕾西娅'),
  _RetrievalCheck('源石技艺'),
  _RetrievalCheck('肉鸽'),
  _RetrievalCheck('集成战略 收藏品'),
  _RetrievalCheck('敌人介绍', expectedContentType: 'enemy_profile'),
  _RetrievalCheck('干员秘录', expectedContentType: 'operator_record_story'),
];

Future<void> main(List<String> args) async {
  sqfliteFfiInit();

  final dbPath = _argValue(args, '--db') ?? _defaultDbPath;
  final dbFile = File(dbPath);
  if (!await dbFile.exists()) {
    stderr.writeln('GameData DB not found: $dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(readOnly: true),
  );
  var failed = false;
  try {
    stdout.writeln('GameData retrieval QA');
    stdout.writeln('DB: $dbPath');
    stdout.writeln('');

    for (final check in _queries) {
      final result = await _search(db, check);
      if (result == null) {
        failed = true;
        stdout.writeln('[FAIL] ${check.query}: no result');
        continue;
      }
      if (check.expectedContentType != null &&
          result.contentType != check.expectedContentType) {
        failed = true;
        stdout.writeln(
          '[FAIL] ${check.query}: expected ${check.expectedContentType}, got ${result.contentType ?? '-'} | ${result.retrievalType} | ${result.title}',
        );
        continue;
      }

      stdout.writeln(
        '[OK] ${check.query}: ${result.retrievalType} | ${result.contentType ?? '-'} | ${result.title}',
      );
      if (result.sourcePath != null && result.sourcePath!.isNotEmpty) {
        stdout.writeln('     ${result.sourcePath}');
      }
    }

    final teresaCandidates = await _aliasCandidateCount(db, '特蕾西娅');
    if (teresaCandidates < 2) {
      failed = true;
      stdout.writeln(
        '[FAIL] 特蕾西娅 alias candidates: expected at least 2, got $teresaCandidates',
      );
    } else {
      stdout.writeln(
        '[OK] 特蕾西娅 alias candidates: $teresaCandidates',
      );
    }
  } finally {
    await db.close();
  }

  if (failed) {
    stderr.writeln('');
    stderr.writeln('One or more retrieval QA queries returned no result.');
    exitCode = 1;
  }
}

Future<_QaResult?> _search(
  Database db,
  _RetrievalCheck check,
) async {
  final contentType = _inferContentType(check.query);
  final entityQuery = _entityFocusedQuery(check.query);
  final queries = <String>{
    check.query,
    if (entityQuery.isNotEmpty) entityQuery,
    ..._expandedQueryAliases(check.query),
    ..._expandedQueryAliases(entityQuery),
  }.where((value) => value.trim().isNotEmpty).toList(growable: false);

  for (final query in queries) {
    final entity = await _searchEntity(
      db,
      query,
      contentType: contentType,
      exactOnly: true,
    );
    if (entity != null) return entity;
  }

  if (check.storyIntent) {
    final story = await _searchStory(db, entityQuery);
    if (story != null) return story;
  }

  for (final query in queries) {
    if (contentType == null) {
      final doc = await _searchEntityDocument(db, query);
      if (doc != null) return doc;
    }

    final record = await _searchRecord(db, query, contentType: contentType);
    if (record != null) return record;

    final chunk = await _searchChunk(db, query, contentType: contentType);
    if (chunk != null) return chunk;
  }

  if (contentType == null) {
    for (final query in queries) {
      final entity = await _searchEntity(db, query);
      if (entity != null) return entity;
    }
  }

  if (contentType != null) {
    final record = await _recordByContentType(db, contentType);
    if (record != null) return record;

    final chunk = await _chunkByContentType(db, contentType);
    if (chunk != null) return chunk;
  }

  return null;
}

Future<int> _aliasCandidateCount(Database db, String alias) async {
  final rows = await db.rawQuery(
    '''
    SELECT DISTINCT entity_id
    FROM entity_aliases
    WHERE alias = ? OR alias LIKE ?
    ''',
    [alias, '%$alias%'],
  );
  return rows.length;
}

Future<_QaResult?> _searchEntity(
  Database db,
  String query, {
  String? contentType,
  bool exactOnly = false,
}) async {
  final where = exactOnly
      ? 'e.name = ? OR ea.alias = ?'
      : 'e.name = ? OR ea.alias = ? OR e.name LIKE ? OR ea.alias LIKE ?';
  final args = exactOnly
      ? <Object?>[query, query, query, query]
      : <Object?>[query, query, '%$query%', '%$query%', query, query];
  final rows = await db.rawQuery(
    '''
    SELECT e.id, e.name, e.source_path
    FROM entities e
    LEFT JOIN entity_aliases ea ON ea.entity_id = e.id
    WHERE $where
    ORDER BY
      CASE
        WHEN e.name = ? THEN 0
        WHEN ea.alias = ? THEN 1
        ELSE 2
      END,
      e.name
    LIMIT 1
    ''',
    args,
  );
  if (rows.isEmpty) return null;

  final entityId = rows.first['id'] as String;
  if (contentType != null) {
    final record = await _recordForEntity(db, entityId, contentType);
    if (record != null) return record;
    return null;
  }

  final docRows = await db.rawQuery(
    '''
    SELECT title, document_type, source_paths
    FROM entity_documents
    WHERE entity_id = ?
    ORDER BY CASE document_type WHEN 'operator_profile_bundle' THEN 0 ELSE 1 END
    LIMIT 1
    ''',
    [entityId],
  );
  if (docRows.isNotEmpty) {
    final row = docRows.first;
    return _QaResult(
      retrievalType: 'entity_document',
      title: row['title'] as String,
      contentType: row['document_type'] as String?,
      sourcePath: row['source_paths'] as String?,
    );
  }

  return _QaResult(
    retrievalType: 'entity',
    title: rows.first['name'] as String,
    contentType: null,
    sourcePath: rows.first['source_path'] as String?,
  );
}

Future<_QaResult?> _recordForEntity(
  Database db,
  String entityId,
  String contentType,
) async {
  final rows = await db.rawQuery(
    '''
    SELECT title, content_type, source_path
    FROM normalized_records
    WHERE entity_id = ? AND content_type = ?
    ORDER BY title
    LIMIT 1
    ''',
    [entityId, contentType],
  );
  if (rows.isEmpty) return null;
  final row = rows.first;
  return _QaResult(
    retrievalType: 'entity_record',
    title: row['title'] as String,
    contentType: row['content_type'] as String?,
    sourcePath: row['source_path'] as String?,
  );
}

Future<_QaResult?> _recordByContentType(
  Database db,
  String contentType,
) async {
  final rows = await db.rawQuery(
    '''
    SELECT title, content_type, source_path
    FROM normalized_records
    WHERE content_type = ?
    ORDER BY title, raw_id
    LIMIT 1
    ''',
    [contentType],
  );
  if (rows.isEmpty) return null;
  final row = rows.first;
  return _QaResult(
    retrievalType: 'content_type_records',
    title: row['title'] as String,
    contentType: row['content_type'] as String?,
    sourcePath: row['source_path'] as String?,
  );
}

Future<_QaResult?> _searchEntityDocument(
  Database db,
  String query,
) async {
  final rows = await db.rawQuery(
    '''
    SELECT title, document_type, source_paths
    FROM entity_documents
    WHERE entity_name LIKE ? OR title LIKE ? OR summary LIKE ? OR content LIKE ?
    ORDER BY CASE document_type WHEN 'operator_profile_bundle' THEN 0 ELSE 1 END
    LIMIT 1
    ''',
    ['%$query%', '%$query%', '%$query%', '%$query%'],
  );
  if (rows.isEmpty) return null;
  final row = rows.first;
  return _QaResult(
    retrievalType: 'entity_document_like',
    title: row['title'] as String,
    contentType: row['document_type'] as String?,
    sourcePath: row['source_paths'] as String?,
  );
}

Future<_QaResult?> _searchRecord(
  Database db,
  String query, {
  String? contentType,
}) async {
  final terms = _searchTerms(query);
  if (terms.isEmpty) return null;
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
  if (contentType != null) {
    where.write(' AND content_type = ?');
    args.add(contentType);
  }
  final rows = await db.rawQuery(
    '''
    SELECT title, content_type, source_path
    FROM normalized_records
    WHERE $where
    ORDER BY title
    LIMIT 1
    ''',
    args,
  );
  if (rows.isEmpty) return null;
  final row = rows.first;
  return _QaResult(
    retrievalType: 'record_like',
    title: row['title'] as String,
    contentType: row['content_type'] as String?,
    sourcePath: row['source_path'] as String?,
  );
}

Future<_QaResult?> _searchStory(Database db, String query) async {
  final rows = await db.rawQuery(
    '''
    SELECT page_title, content_type, source_path
    FROM lore_chunks
    WHERE (source_type = 'game_story' OR content_category = 'story')
      AND (page_title LIKE ? OR section LIKE ? OR content LIKE ? OR raw_id LIKE ?)
    ORDER BY page_title
    LIMIT 1
    ''',
    ['%$query%', '%$query%', '%$query%', '%$query%'],
  );
  if (rows.isEmpty) return null;
  final row = rows.first;
  return _QaResult(
    retrievalType: 'story_like',
    title: row['page_title'] as String? ?? 'story',
    contentType: row['content_type'] as String?,
    sourcePath: row['source_path'] as String?,
  );
}

Future<_QaResult?> _searchChunk(
  Database db,
  String query, {
  String? contentType,
}) async {
  final terms = _searchTerms(query);
  if (terms.isEmpty) return null;
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
  if (contentType != null) {
    where.write(' AND content_type = ?');
    args.add(contentType);
  }
  final rows = await db.rawQuery(
    '''
    SELECT page_title, content_type, source_path
    FROM lore_chunks
    WHERE $where
    ORDER BY page_title
    LIMIT 1
    ''',
    args,
  );
  if (rows.isEmpty) return null;
  final row = rows.first;
  return _QaResult(
    retrievalType: 'chunk_like',
    title: row['page_title'] as String? ?? 'chunk',
    contentType: row['content_type'] as String?,
    sourcePath: row['source_path'] as String?,
  );
}

Future<_QaResult?> _chunkByContentType(
  Database db,
  String contentType,
) async {
  final rows = await db.rawQuery(
    '''
    SELECT page_title, content_type, source_path
    FROM lore_chunks
    WHERE content_type = ?
    ORDER BY page_title, raw_id
    LIMIT 1
    ''',
    [contentType],
  );
  if (rows.isEmpty) return null;
  final row = rows.first;
  return _QaResult(
    retrievalType: 'content_type_chunks',
    title: row['page_title'] as String? ?? 'chunk',
    contentType: row['content_type'] as String?,
    sourcePath: row['source_path'] as String?,
  );
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

List<String> _searchTerms(String query) {
  return query
      .trim()
      .split(RegExp(r'\s+'))
      .map((term) => term.trim())
      .where((term) => term.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

List<String> _expandedQueryAliases(String query) {
  if (query.trim().isEmpty) return const [];
  final expanded = <String>{};
  if (query.contains('肉鸽')) {
    expanded.add(query.replaceAll('肉鸽', '集成战略'));
    expanded.add('$query 集成战略');
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

String? _argValue(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

class _RetrievalCheck {
  final String query;
  final bool storyIntent;
  final String? expectedContentType;

  const _RetrievalCheck(
    this.query, {
    this.storyIntent = false,
    this.expectedContentType,
  });
}

class _QaResult {
  final String retrievalType;
  final String title;
  final String? contentType;
  final String? sourcePath;

  const _QaResult({
    required this.retrievalType,
    required this.title,
    required this.contentType,
    required this.sourcePath,
  });
}
