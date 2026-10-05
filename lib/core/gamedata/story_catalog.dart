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
    synopsis_path   TEXT,
    start_time      INTEGER
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
    this.startTime,
  });

  // `start_time` is absent from R14 catalogs (R15 column); fromRow then
  // leaves it null.
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
        startTime: (row['start_time'] as num?)?.toInt(),
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

  /// R15: the collection's release time (`startTime` of the review table,
  /// unix seconds); null for collections without one (main story, operator
  /// records) and for R14 catalogs.
  final int? startTime;

  /// `2024-06` (China time) of [startTime], or null.
  String? get releaseMonth => releaseMonthOf(startTime);

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
        'start_time': startTime,
      };

  /// Readable collection name with its kind, e.g. `巴别塔`, `主线·慈悲灯塔`,
  /// `干员密录·苹果`.
  String get collectionLabel => switch (collectionType) {
        'MAINLINE' => '主线·$collectionName',
        'NONE' => '干员密录·$collectionName',
        'ROGUELIKE' => '集成战略·$collectionName',
        'SANDBOX' => '生息演算·$collectionName',
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
    if (collectionName.trim().isEmpty) return chapter;
    return chapter.isEmpty ? collectionLabel : '$collectionLabel $chapter';
  }
}

bool _present(String? value) => value != null && value.trim().isNotEmpty;

/// `yyyy-MM` in China time (UTC+8, the server's release clock) of a unix
/// timestamp in seconds; null for missing / non-positive values.
String? releaseMonthOf(int? startTime) {
  if (startTime == null || startTime <= 0) return null;
  final time = DateTime.fromMillisecondsSinceEpoch(startTime * 1000, isUtc: true)
      .add(const Duration(hours: 8));
  return '${time.year}-${time.month.toString().padLeft(2, '0')}';
}

/// Sort key of a collection in release order: dated collections by date,
/// then main-story chapters by number, then the rest (operator records…).
/// Ties fall back to the collection id.
(int, int, String) collectionReleaseKey({
  required String collectionId,
  required String collectionType,
  int? startTime,
}) {
  if (startTime != null && startTime > 0) return (0, startTime, collectionId);
  if (collectionType == 'MAINLINE') {
    final number = int.tryParse(
          RegExp(r'(\d+)').firstMatch(collectionId)?.group(1) ?? '',
        ) ??
        0;
    return (1, number, collectionId);
  }
  return (2, 0, collectionId);
}

int compareReleaseKeys((int, int, String) a, (int, int, String) b) {
  if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
  if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
  return a.$3.compareTo(b.$3);
}

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
    final start = (value['startTime'] as num?)?.toInt();
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
        startTime: start != null && start > 0 ? start : null,
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
  if (ids.isEmpty) return const {};
  final hasCatalog = await hasStoryCatalog(db);
  final result = <String, StoryCatalogEntry>{};
  for (var i = 0; hasCatalog && i < ids.length; i += 500) {
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
  // Files the review table does not list (training, guides, roguelike and
  // sandbox stories, in-level dialogue) are named by the entry layer: the
  // name the tables or their stage give them, in their collection.
  await _fillFromEntryLayer(db, ids, result);
  if (!hasCatalog) return result;
  // Files outside the review table and the entry layer (in-level dialogue
  // under `activities/<id>/level/…`) still belong to their activity: name
  // them by that collection plus the file name (no invented chapter names).
  final missing = {
    for (final id in ids)
      if (!result.containsKey(id) && id.startsWith('activities/')) id,
  };
  if (missing.isNotEmpty) {
    final byFolder = <String, List<String>>{};
    for (final id in missing) {
      final parts = id.split('/');
      if (parts.length >= 3) byFolder.putIfAbsent(parts[1], () => []).add(id);
    }
    for (final folder in byFolder.entries) {
      final rows = await db.rawQuery(
        'SELECT collection_name, collection_type FROM $storyCatalogTable '
        'WHERE collection_id = ? LIMIT 1',
        [folder.key],
      );
      if (rows.isEmpty) continue;
      for (final id in folder.value) {
        result[id] = StoryCatalogEntry(
          storyId: id,
          collectionId: folder.key,
          collectionName: '${rows.first['collection_name']}',
          collectionType: '${rows.first['collection_type']}',
          storySort: 1 << 30,
          storyCode: id.split('/').last.replaceAll(RegExp(r'\.txt$'), ''),
          avgTag: '关卡内对话',
        );
      }
    }
  }
  return result;
}

/// Adds the stories of [ids] that [result] lacks from the entry layer
/// (schema 5): `entries` + `collections`. Older databases have none.
Future<void> _fillFromEntryLayer(
  DatabaseExecutor db,
  List<String> ids,
  Map<String, StoryCatalogEntry> result,
) async {
  final todo = [for (final id in ids) if (!result.containsKey(id)) id];
  if (todo.isEmpty ||
      !await _hasTable(db, 'entries') ||
      !await _hasTable(db, 'collections')) {
    return;
  }
  for (var i = 0; i < todo.length; i += 500) {
    final chunk = todo.sublist(i, i + 500 > todo.length ? todo.length : i + 500);
    final rows = await db.rawQuery(
      'SELECT e.raw_id, e.name, e.code, e.group_name, e.sort_key, '
      'e.collection_id, c.name AS collection_name, c.kind AS kind '
      'FROM entries e LEFT JOIN collections c ON c.id = e.collection_id '
      "WHERE e.type = 'story' AND e.raw_id IN "
      '(${List.filled(chunk.length, '?').join(',')})',
      chunk,
    );
    for (final row in rows) {
      final id = '${row['raw_id']}';
      final group = (row['group_name'] as String?)?.trim() ?? '';
      final name = (row['name'] as String?)?.trim() ?? '';
      result[id] = StoryCatalogEntry(
        storyId: id,
        collectionId: '${row['collection_id'] ?? ''}',
        collectionName: '${row['collection_name'] ?? ''}',
        collectionType: switch ('${row['kind']}') {
          'main' => 'MAINLINE',
          'memory' => 'NONE',
          'roguelike' => 'ROGUELIKE',
          'sandbox' => 'SANDBOX',
          'system' => 'SYSTEM',
          _ => 'ACTIVITY',
        },
        storySort: (row['sort_key'] as num?)?.toInt() ?? 0,
        storyCode: (row['code'] as String?)?.trim(),
        storyName: name.isEmpty ? null : name,
        // A group already part of the name is not said twice.
        avgTag: group.isEmpty || name.contains(group) ? null : group,
      );
    }
  }
}

/// R16: catalog entries whose level code is [code] (`10-10`, `EG-7`) — the
/// real story ids for a READ of a guessed id that does not exist.
Future<List<StoryCatalogEntry>> queryStoriesByCode(
  DatabaseExecutor db,
  String code, {
  int limit = 4,
}) async {
  if (code.trim().isEmpty || !await hasStoryCatalog(db)) return const [];
  final rows = await db.rawQuery(
    'SELECT * FROM $storyCatalogTable WHERE story_code = ? '
    'ORDER BY collection_id, story_sort LIMIT ?',
    [code.trim(), limit],
  );
  return rows.map(StoryCatalogEntry.fromRow).toList();
}

/// Ordered chapters of one collection, resolved from [query]: a story id
/// (its collection), a collection id, a scope key (`activity:act33side`),
/// or a collection name (exact first, then substring). Null when nothing
/// matches or the DB has no catalog.
Future<StoryCollection?> queryStoryCollection(
  DatabaseExecutor db,
  String query,
) async {
  var q = query.trim();
  if (q.startsWith('@')) q = q.substring(1).trim();
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
  // `activity:act33side`, `@activity:act33side`, `activities/act33side`
  // and `activities/act33side/` all name the collection `act33side`.
  var bare = q.contains(':') ? q.substring(q.lastIndexOf(':') + 1) : q;
  bare = bare.replaceAll(RegExp(r'/+$'), '');
  final segments = bare.split('/');
  for (final candidate in {bare, segments.last}) {
    collectionId ??= await first(
      'SELECT collection_id FROM $storyCatalogTable WHERE collection_id = ? LIMIT 1',
      [candidate],
    );
  }
  // R16: the label prefixes [StoryCatalogEntry.collectionLabel] adds
  // (`主线·风暴瞭望`, `干员密录·…`) are not part of the stored name.
  final name = q.replaceFirst(RegExp(r'^(主线|干员密录)[·・•]'), '');
  collectionId ??= await first(
    'SELECT collection_id FROM $storyCatalogTable WHERE collection_name = ? '
    'ORDER BY collection_id LIMIT 1',
    [name],
  );
  collectionId ??= await first(
    "SELECT collection_id FROM $storyCatalogTable WHERE collection_name LIKE ? ESCAPE '\\' "
    'GROUP BY collection_id ORDER BY LENGTH(collection_name), collection_id LIMIT 1',
    ['%${escapeLike(name)}%'],
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

  /// R15: release month of the collection, when the catalog has one.
  String? get releaseMonth =>
      entries.isEmpty ? null : entries.first.releaseMonth;
}

/// R15: a collection or chapter whose name appears in a question.
class NamedStoryTarget {
  const NamedStoryTarget({
    required this.name,
    required this.collectionId,
    required this.label,
    required this.chapters,
    this.storyId,
    this.releaseMonth,
  });

  /// The name as written in the question.
  final String name;
  final String collectionId;

  /// Collection label, or the chapter label when [storyId] is set.
  final String label;
  final int chapters;

  /// Set when the name is a chapter name.
  final String? storyId;
  final String? releaseMonth;
}

/// Collections and chapters whose names occur verbatim in [text], longest
/// names first and non-overlapping. Short names are ambiguous with ordinary
/// words, so a name must be at least 2 characters for an event / main
/// collection and at least 3 for an operator-record collection or a chapter,
/// unless the question puts it in 《》. Locating hints only.
Future<List<NamedStoryTarget>> queryNamedStoryTargets(
  DatabaseExecutor db,
  String text, {
  int limit = 4,
}) async {
  if (text.trim().isEmpty || !await hasStoryCatalog(db)) return const [];
  final quoted = {
    for (final m in RegExp('《([^》]+)》').allMatches(text)) m.group(1)!.trim(),
  };
  bool long(String name, int min) =>
      name.runes.length >= min || quoted.contains(name);

  final candidates = <NamedStoryTarget>[];
  final collections = await db.rawQuery(
    'SELECT * , COUNT(*) AS n FROM $storyCatalogTable '
    'GROUP BY collection_id',
  );
  for (final row in collections) {
    final entry = StoryCatalogEntry.fromRow(row);
    final name = entry.collectionName.trim();
    final min = entry.collectionType == 'NONE' ? 3 : 2;
    if (!long(name, min) || !text.contains(name)) continue;
    candidates.add(NamedStoryTarget(
      name: name,
      collectionId: entry.collectionId,
      label: entry.collectionLabel,
      chapters: (row['n'] as num).toInt(),
      releaseMonth: entry.releaseMonth,
    ),);
  }
  final chapters = await db.rawQuery(
    'SELECT * FROM $storyCatalogTable WHERE story_name IS NOT NULL '
    'AND story_name != collection_name',
  );
  final seenChapterNames = <String>{};
  for (final row in chapters) {
    final entry = StoryCatalogEntry.fromRow(row);
    final name = entry.storyName!.trim();
    if (!long(name, 3) || !text.contains(name)) continue;
    // A chapter name shared by 行动前/行动后 (or reused across collections)
    // is listed once per collection, at its first chapter.
    if (!seenChapterNames.add('${entry.collectionId}#$name')) continue;
    candidates.add(NamedStoryTarget(
      name: name,
      collectionId: entry.collectionId,
      label: entry.label,
      chapters: 1,
      storyId: entry.storyId,
      releaseMonth: entry.releaseMonth,
    ),);
  }
  candidates.sort((a, b) {
    final byLength = b.name.runes.length.compareTo(a.name.runes.length);
    if (byLength != 0) return byLength;
    return a.collectionId.compareTo(b.collectionId);
  });
  final taken = <(int, int)>[];
  final result = <NamedStoryTarget>[];
  for (final candidate in candidates) {
    final start = text.indexOf(candidate.name);
    final span = (start, start + candidate.name.length);
    final overlaps = taken.any((t) => span.$1 < t.$2 && t.$1 < span.$2) &&
        !taken.contains(span);
    if (overlaps) continue;
    taken.add(span);
    result.add(candidate);
    if (result.length >= limit) break;
  }
  return result;
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
