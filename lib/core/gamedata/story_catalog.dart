/// R14 story catalog: human-readable names, order and official synopses of
/// every story file (optional `story_catalog` table, schema stays 4).
///
/// Source (CLAUDE.md principle 4 — deterministic, traceable):
/// - `excel/story_review_table.json`: one collection per event / main chapter
///   / operator record (`name`, `entryType`), and per story file its
///   `storyCode` (e.g. BB-7), `storyName`, `avgTag` (行动前/行动后/幕间),
///   `storySort` (in-collection order) and `storyTxt` (the story file);
/// - `story/[uc]info/<storyInfo>.txt`: the official one-paragraph synopsis
///   shown in the game's story review.
///
/// Labels and synopses are BROWSING AIDS (principle 5): they tell the agent
/// which chapter to READ and tell the user where a quote comes from; they
/// never count as evidence. Without the table everything falls back to the
/// raw story ids (old DBs keep working).
///
/// Pure Dart (sqflite_common) so the app, the in-app builder and desktop tools
/// share it.
library;

import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

const String storyCatalogTable = 'story_catalog';
const String manifestStoryCatalogCount = 'story_catalog_count';

/// Repo-relative source paths.
const String storyReviewTablePath =
    'zh_CN/gamedata/excel/story_review_table.json';
const String storyInfoRoot = 'zh_CN/gamedata/story/[uc]info';

const String storyCatalogDdl = '''
  CREATE TABLE IF NOT EXISTS $storyCatalogTable (
    story_id        TEXT PRIMARY KEY,
    collection_id   TEXT NOT NULL,
    collection_name TEXT NOT NULL,
    collection_type TEXT NOT NULL,
    story_code      TEXT,
    story_name      TEXT,
    avg_tag         TEXT,
    story_sort      INTEGER NOT NULL,
    synopsis        TEXT,
    synopsis_path   TEXT
  )
''';

/// One story file in the catalog.
class StoryCatalogEntry {
  const StoryCatalogEntry({
    required this.storyId,
    required this.collectionId,
    required this.collectionName,
    required this.collectionType,
    required this.storySort,
    this.storyCode,
    this.storyName,
    this.avgTag,
    this.synopsis,
    this.synopsisPath,
  });

  factory StoryCatalogEntry.fromRow(Map<String, Object?> row) =>
      StoryCatalogEntry(
        storyId: '${row['story_id']}',
        collectionId: '${row['collection_id']}',
        collectionName: '${row['collection_name']}',
        collectionType: '${row['collection_type']}',
        storySort: (row['story_sort'] as num?)?.toInt() ?? 0,
        storyCode: row['story_code'] as String?,
        storyName: row['story_name'] as String?,
        avgTag: row['avg_tag'] as String?,
        synopsis: row['synopsis'] as String?,
        synopsisPath: row['synopsis_path'] as String?,
      );

  /// Story file id as in `story_lines.story_id` (e.g.
  /// `activities/act33side/level_act33side_07_beg.txt`).
  final String storyId;
  final String collectionId;
  final String collectionName;

  /// `entryType` of the collection: ACTIVITY, MINI_ACTIVITY, MAINLINE, NONE
  /// (operator records).
  final String collectionType;
  final int storySort;
  final String? storyCode;
  final String? storyName;
  final String? avgTag;
  final String? synopsis;
  final String? synopsisPath;

  Map<String, Object?> toRow() => {
        'story_id': storyId,
        'collection_id': collectionId,
        'collection_name': collectionName,
        'collection_type': collectionType,
        'story_code': storyCode,
        'story_name': storyName,
        'avg_tag': avgTag,
        'story_sort': storySort,
        'synopsis': synopsis,
        'synopsis_path': synopsisPath,
      };

  /// Readable collection name with its kind, e.g. `巴别塔`, `主线·慈悲灯塔`,
  /// `干员密录·苹果`.
  String get collectionLabel => switch (collectionType) {
        'MAINLINE' => '主线·$collectionName',
        'NONE' => '干员密录·$collectionName',
        _ => collectionName,
      };

  /// Chapter part of the label, e.g. `BB-7 行动前《…》`.
  String get chapterLabel {
    final parts = <String>[
      if (_present(storyCode)) storyCode!.trim(),
      if (_present(avgTag) && collectionType != 'NONE') avgTag!.trim(),
    ];
    final name = _present(storyName) && storyName!.trim() != collectionName
        ? '《${storyName!.trim()}》'
        : '';
    return '${parts.join(' ')}$name'.trim();
  }

  /// Full label, e.g. `巴别塔 BB-7 行动前《…》`.
  String get label {
    final chapter = chapterLabel;
    return chapter.isEmpty ? collectionLabel : '$collectionLabel $chapter';
  }
}

bool _present(String? value) => value != null && value.trim().isNotEmpty;

/// Parses `story_review_table.json` into catalog entries. [readSynopsis]
/// receives the `storyInfo` value (e.g. `info/obt/main/level_st_14-01`) and
/// returns the synopsis text or null. A story file listed in several
/// collections keeps its first listing (JSON order, deterministic).
List<StoryCatalogEntry> parseStoryReviewTable(
  Map<String, dynamic> table,
  String? Function(String storyInfo) readSynopsis,
) {
  final entries = <StoryCatalogEntry>[];
  final seen = <String>{};
  for (final collection in table.entries) {
    final value = collection.value;
    if (value is! Map) continue;
    final name = '${value['name'] ?? ''}'.trim();
    final type = '${value['entryType'] ?? ''}'.trim();
    final stories = value['infoUnlockDatas'];
    if (name.isEmpty || stories is! List) continue;
    for (final story in stories) {
      if (story is! Map) continue;
      final txt = '${story['storyTxt'] ?? ''}'.trim();
      if (txt.isEmpty) continue;
      final storyId = txt.endsWith('.txt') ? txt : '$txt.txt';
      if (!seen.add(storyId)) continue;
      final info = '${story['storyInfo'] ?? ''}'.trim();
      final synopsis = info.isEmpty ? null : readSynopsis(info);
      entries.add(StoryCatalogEntry(
        storyId: storyId,
        collectionId: '${value['id'] ?? collection.key}',
        collectionName: name,
        collectionType: type.isEmpty ? 'NONE' : type,
        storySort: (story['storySort'] as num?)?.toInt() ?? 0,
        storyCode: _nonEmpty(story['storyCode']),
        storyName: _nonEmpty(story['storyName']),
        avgTag: _nonEmpty(story['avgTag']),
        synopsis: synopsis == null ? null : normalizeSynopsis(synopsis),
        synopsisPath: info.isEmpty ? null : synopsisPathFor(info),
      ),);
    }
  }
  return entries;
}

String? _nonEmpty(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

/// Repo-relative path of the synopsis file for a `storyInfo` value
/// (`info/x/y` → `zh_CN/gamedata/story/[uc]info/x/y.txt`).
String synopsisPathFor(String storyInfo) {
  final rel = storyInfo.startsWith('info/')
      ? storyInfo.substring('info/'.length)
      : storyInfo;
  return '$storyInfoRoot/$rel.txt';
}

/// Collapses whitespace of a synopsis file into one paragraph.
String normalizeSynopsis(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Replaces the catalog table with [entries], records the row count in the
/// manifest and relabels `story_chapter_profiles` (title = label, summary =
/// official synopsis where one exists). Deterministic: same input, same rows.
Future<int> writeStoryCatalog(
  DatabaseExecutor db,
  List<StoryCatalogEntry> entries,
) async {
  await db.execute('DROP TABLE IF EXISTS $storyCatalogTable');
  await db.execute(storyCatalogDdl);
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_story_catalog_collection '
    'ON $storyCatalogTable(collection_id, story_sort)',
  );
  final batch = db.batch();
  for (final entry in entries) {
    batch.insert(
      storyCatalogTable,
      entry.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
  await db.insert(
    'gamedata_manifest',
    {'key': manifestStoryCatalogCount, 'value': '${entries.length}'},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  await applyStoryCatalogToProfiles(db, entries);
  return entries.length;
}

/// Writes catalog labels/synopses into `story_chapter_profiles` (when the
/// table exists), so MAP shows names and official synopses instead of file
/// names and one extracted line.
Future<void> applyStoryCatalogToProfiles(
  DatabaseExecutor db,
  List<StoryCatalogEntry> entries,
) async {
  if (!await _hasTable(db, 'story_chapter_profiles')) return;
  final batch = db.batch();
  for (final entry in entries) {
    final values = <String, Object?>{'title': entry.label};
    if (_present(entry.synopsis)) values['summary'] = entry.synopsis;
    batch.update(
      'story_chapter_profiles',
      values,
      where: 'story_id = ?',
      whereArgs: [entry.storyId],
    );
  }
  await batch.commit(noResult: true);
}

/// Whether the DB carries the optional catalog table.
Future<bool> hasStoryCatalog(DatabaseExecutor db) =>
    _hasTable(db, storyCatalogTable);

Future<bool> _hasTable(DatabaseExecutor db, String name) async =>
    (await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    ))
        .isNotEmpty;

/// Catalog entries of [storyIds] (missing ids are absent from the map).
Future<Map<String, StoryCatalogEntry>> queryCatalogEntries(
  DatabaseExecutor db,
  Iterable<String> storyIds,
) async {
  final ids = storyIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet().toList();
  if (ids.isEmpty || !await hasStoryCatalog(db)) return const {};
  final result = <String, StoryCatalogEntry>{};
  for (var i = 0; i < ids.length; i += 500) {
    final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
    final rows = await db.rawQuery(
      'SELECT * FROM $storyCatalogTable WHERE story_id IN '
      '(${List.filled(chunk.length, '?').join(',')})',
      chunk,
    );
    for (final row in rows) {
      final entry = StoryCatalogEntry.fromRow(row);
      result[entry.storyId] = entry;
    }
  }
  return result;
}

/// Ordered chapters of one collection, resolved from [query]: a story id
/// (its collection), a collection id, a scope key (`activity:act33side`),
/// or a collection name (exact first, then substring). Null when nothing
/// matches or the DB has no catalog.
Future<StoryCollection?> queryStoryCollection(
  DatabaseExecutor db,
  String query,
) async {
  final q = query.trim();
  if (q.isEmpty || !await hasStoryCatalog(db)) return null;
  String? collectionId;
  Future<String?> first(String sql, List<Object?> args) async {
    final rows = await db.rawQuery(sql, args);
    return rows.isEmpty ? null : '${rows.first['collection_id']}';
  }

  final storyId = q.endsWith('.txt') ? q : '$q.txt';
  collectionId = await first(
    'SELECT collection_id FROM $storyCatalogTable WHERE story_id = ?',
    [storyId],
  );
  final bare = q.contains(':') ? q.substring(q.lastIndexOf(':') + 1) : q;
  collectionId ??= await first(
    'SELECT collection_id FROM $storyCatalogTable WHERE collection_id = ? LIMIT 1',
    [bare],
  );
  collectionId ??= await first(
    'SELECT collection_id FROM $storyCatalogTable WHERE collection_name = ? '
    'ORDER BY collection_id LIMIT 1',
    [q],
  );
  collectionId ??= await first(
    "SELECT collection_id FROM $storyCatalogTable WHERE collection_name LIKE ? ESCAPE '\\' "
    'GROUP BY collection_id ORDER BY LENGTH(collection_name), collection_id LIMIT 1',
    ['%${escapeLike(q)}%'],
  );
  if (collectionId == null) return null;
  final rows = await db.rawQuery(
    'SELECT * FROM $storyCatalogTable WHERE collection_id = ? '
    'ORDER BY story_sort, story_id',
    [collectionId],
  );
  if (rows.isEmpty) return null;
  return StoryCollection(
    collectionId: collectionId,
    entries: [for (final row in rows) StoryCatalogEntry.fromRow(row)],
    focusStoryId: rows.any((r) => r['story_id'] == storyId) ? storyId : null,
  );
}

/// Catalog entries whose synopsis, chapter name or collection name contains
/// any of [terms], ranked by the number of distinct terms matched.
Future<List<StoryCatalogEntry>> querySynopsisHits(
  DatabaseExecutor db,
  List<String> terms, {
  String? collectionId,
  int limit = 5,
}) async {
  final cleaned = {
    for (final t in terms)
      if (t.trim().isNotEmpty) t.trim(),
  }.toList();
  if (cleaned.isEmpty || !await hasStoryCatalog(db)) return const [];
  final score = StringBuffer();
  final args = <Object?>[];
  for (final term in cleaned) {
    if (score.isNotEmpty) score.write(' + ');
    score.write(
      "(COALESCE(synopsis, '') || ' ' || COALESCE(story_name, '') || ' ' || "
      "collection_name LIKE ? ESCAPE '\\')",
    );
    args.add('%${escapeLike(term)}%');
  }
  var sql = 'SELECT *, ($score) AS matched FROM $storyCatalogTable WHERE matched > 0';
  if (collectionId != null && collectionId.isNotEmpty) {
    sql += ' AND collection_id = ?';
    args.add(collectionId);
  }
  sql += ' ORDER BY matched DESC, collection_id, story_sort LIMIT ?';
  args.add(limit);
  final rows = await db.rawQuery(sql, args);
  return [for (final row in rows) StoryCatalogEntry.fromRow(row)];
}

/// Collections (id, label, chapter count) whose name contains [like] and/or
/// whose type is [type]; used when an OUTLINE target names no single
/// collection (e.g. the whole main story).
Future<List<({String id, String label, int chapters})>> queryCollectionIndex(
  DatabaseExecutor db, {
  String? like,
  String? type,
  int limit = 40,
}) async {
  if (!await hasStoryCatalog(db)) return const [];
  final where = <String>[];
  final args = <Object?>[];
  if (like != null && like.trim().isNotEmpty) {
    where.add("collection_name LIKE ? ESCAPE '\\'");
    args.add('%${escapeLike(like.trim())}%');
  }
  if (type != null && type.isNotEmpty) {
    where.add('collection_type = ?');
    args.add(type);
  }
  final rows = await db.rawQuery(
    'SELECT collection_id, collection_name, collection_type, COUNT(*) AS n, '
    'MIN(story_id) AS first_story FROM $storyCatalogTable '
    '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}'
    'GROUP BY collection_id ORDER BY first_story LIMIT ?',
    [...args, limit],
  );
  return [
    for (final row in rows)
      (
        id: '${row['collection_id']}',
        label: StoryCatalogEntry(
          storyId: '',
          collectionId: '${row['collection_id']}',
          collectionName: '${row['collection_name']}',
          collectionType: '${row['collection_type']}',
          storySort: 0,
        ).collectionLabel,
        chapters: (row['n'] as num).toInt(),
      ),
  ];
}

/// One collection's chapters in game order.
class StoryCollection {
  const StoryCollection({
    required this.collectionId,
    required this.entries,
    this.focusStoryId,
  });
  final String collectionId;
  final List<StoryCatalogEntry> entries;

  /// The story id the lookup started from, when it was a chapter.
  final String? focusStoryId;

  String get label =>
      entries.isEmpty ? collectionId : entries.first.collectionLabel;
}

/// Escapes LIKE wildcards (`\` is the ESCAPE character).
String escapeLike(String term) => term
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');

/// Readable fallback label for a story id without a catalog entry, derived
/// from its path only (no invented names): `activities/act33side/x.txt` →
/// `活动 act33side · x`.
String fallbackStoryLabel(String storyId) {
  final parts = storyId.split('/');
  final file = parts.last.replaceAll(RegExp(r'\.txt$'), '');
  if (parts.length >= 3 && parts.first == 'activities') {
    return '活动 ${parts[1]} · $file';
  }
  if (parts.length >= 3 && parts.first == 'obt') {
    final group = switch (parts[1]) {
      'main' => '主线',
      'memory' => '干员密录',
      'rogue' || 'roguelike' => '集成战略',
      'guide' => '引导',
      _ => parts[1],
    };
    return '$group · $file';
  }
  return file;
}

/// JSON helper for tools/tests that read the review table from disk.
Map<String, dynamic> decodeStoryReviewTable(String raw) {
  final decoded = jsonDecode(raw);
  return decoded is Map<String, dynamic> ? decoded : const {};
}
