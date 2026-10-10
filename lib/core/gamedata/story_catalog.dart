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
import 'dart:math' as math;

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
        'SANDBOX' => '生息演算·$collectionName',
        // 0.12: an Endfield story says which game it is from.
        final type when type.startsWith(endfieldCollectionTypePrefix) =>
          '终末地·$collectionName',
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

/// Replaces the catalog table with [entries] and records the row count in
/// the manifest. Deterministic: same input, same rows.
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
  return entries.length;
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
  final name = q.replaceFirst(collectionLabelPrefix, '');
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

/// The kind [StoryCatalogEntry.collectionLabel] writes before a
/// collection's name (`主线·…`, `干员密录·…`): not part of the stored name.
final RegExp collectionLabelPrefix = RegExp(r'^(主线|干员密录|生息演算|终末地)[·・•]');

/// 0.14: a collection related to another one: it shares speakers with it
/// and, when the database has vectors, reads alike. A hint for where to
/// look, not evidence — nothing in the data says that one story continues
/// another, or which comes first.
class RelatedCollection {
  const RelatedCollection({
    required this.id,
    required this.label,
    required this.shared,
    required this.names,
    this.releaseMonth,
    this.similarity,
  });

  final String id;
  final String label;

  /// `2024-06`, or null (main story, operator records).
  final String? releaseMonth;

  /// How many speakers the two collections share.
  final int shared;

  /// Some of them, the least common first.
  final List<String> names;

  /// Cosine of the two collections' mean vectors; null without vectors.
  final double? similarity;
}

/// Lines a speaker has in a collection before they count as one of its
/// speakers (a passer-by with a few lines says nothing about the story).
const int relatedMinLines = 10;

/// Related collections listed.
const int relatedCollectionLimit = 6;

/// Shared speakers named for each.
const int relatedNamesShown = 4;

/// The speakers of [collectionId] (with [relatedMinLines] lines or more),
/// each with the collections they speak that much in — that one included.
/// Sources: `story_lines.speaker` and the catalog's `collection_id`.
Future<Map<String, Set<String>>> querySharedSpeakers(
  DatabaseExecutor db,
  String collectionId,
) async {
  if (!await hasStoryCatalog(db)) return const {};
  final rows = await db.rawQuery(
    'WITH tgt AS ('
    'SELECT l.speaker FROM story_lines l '
    'JOIN $storyCatalogTable c ON c.story_id = l.story_id '
    "WHERE c.collection_id = ? AND l.speaker <> '' "
    'GROUP BY l.speaker HAVING COUNT(*) >= ?) '
    'SELECT l.speaker AS speaker, c.collection_id AS collection_id '
    'FROM story_lines l JOIN $storyCatalogTable c ON c.story_id = l.story_id '
    'WHERE l.speaker IN (SELECT speaker FROM tgt) '
    'GROUP BY l.speaker, c.collection_id HAVING COUNT(*) >= ?',
    [collectionId, relatedMinLines, relatedMinLines],
  );
  final speakers = <String, Set<String>>{};
  for (final row in rows) {
    speakers
        .putIfAbsent('${row['speaker']}', () => {})
        .add('${row['collection_id']}');
  }
  return speakers;
}

/// One row of [rankRelatedCollections].
typedef RankedCollection = ({
  String id,
  int shared,
  List<String> names,
  double? similarity,
});

/// The collections most related to [target], best first. [speakers] is
/// [querySharedSpeakers]' result; [similarity] the cosine of each other
/// collection's mean vector with the target's (null without vectors).
///
/// Two rankings: by shared speakers, each weighing `1 / ln(1 + n)` for the
/// `n` collections they speak in (someone who is everywhere says little);
/// and by similarity. They are joined by rank (reciprocal rank fusion): a
/// collection one ranking does not have takes its last place there. Without
/// [similarity] only the speakers rank.
List<RankedCollection> rankRelatedCollections(
  String target,
  Map<String, Set<String>> speakers,
  Map<String, double>? similarity, {
  int limit = relatedCollectionLimit,
}) {
  const k = 60;
  final weight = <String, double>{};
  final who = <String, List<(String, double)>>{};
  for (final MapEntry(key: speaker, value: collections) in speakers.entries) {
    if (!collections.contains(target)) continue;
    // A speaker written only in marks (an unnamed voice) is nobody.
    if (!_hasLetter.hasMatch(speaker)) continue;
    final w = 1 / math.log(1 + collections.length);
    for (final c in collections) {
      if (c == target) continue;
      weight[c] = (weight[c] ?? 0) + w;
      who.putIfAbsent(c, () => []).add((speaker, w));
    }
  }
  List<String> ordered(Map<String, double> scores) => scores.keys.toList()
    ..sort((a, b) {
      final byScore = scores[b]!.compareTo(scores[a]!);
      return byScore != 0 ? byScore : a.compareTo(b);
    });
  Map<String, int> ranks(List<String> ids) =>
      {for (final (i, id) in ids.indexed) id: i + 1};

  final near = similarity == null
      ? null
      : {
          for (final e in similarity.entries)
            if (e.key != target) e.key: e.value,
        };
  final bySpeakers = ranks(ordered(weight));
  final byNear = near == null ? null : ranks(ordered(near));
  final score = <String, double>{
    for (final id in {...bySpeakers.keys, ...?byNear?.keys})
      id: 1 / (k + (bySpeakers[id] ?? bySpeakers.length + 1)) +
          (byNear == null ? 0 : 1 / (k + (byNear[id] ?? byNear.length + 1))),
  };
  return [
    for (final id in ordered(score).take(limit))
      (
        id: id,
        shared: who[id]?.length ?? 0,
        names: [
          for (final (name, _) in [...?who[id]]
            ..sort((a, b) {
              final byWeight = b.$2.compareTo(a.$2);
              return byWeight != 0 ? byWeight : a.$1.compareTo(b.$1);
            }))
            name,
        ].take(relatedNamesShown).toList(),
        similarity: near?[id],
      ),
  ];
}

final RegExp _hasLetter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Label and release month of each of [collectionIds].
Future<Map<String, ({String label, String? releaseMonth})>> queryCollectionLabels(
  DatabaseExecutor db,
  Iterable<String> collectionIds,
) async {
  final ids = collectionIds.toList();
  if (ids.isEmpty || !await hasStoryCatalog(db)) return const {};
  final rows = await db.rawQuery(
    'SELECT collection_id, collection_name, collection_type, '
    'MIN(start_time) AS start_time FROM $storyCatalogTable '
    'WHERE collection_id IN (${List.filled(ids.length, '?').join(', ')}) '
    'GROUP BY collection_id',
    ids,
  );
  return {
    for (final row in rows)
      '${row['collection_id']}': (
        label: StoryCatalogEntry(
          storyId: '',
          collectionId: '${row['collection_id']}',
          collectionName: '${row['collection_name']}',
          collectionType: '${row['collection_type']}',
          storySort: 0,
        ).collectionLabel,
        releaseMonth: releaseMonthOf((row['start_time'] as num?)?.toInt()),
      ),
  };
}

// 0.14: where a word's lines are — its spread over the collections. Every
// word gets the same form; nothing decides whether a word is "worth"
// listing (a word that is everywhere shows as such: most of it is in "the
// rest"). The numbers below are from measurements on the real database
// (2026-10-11: 92 words, names by frequency band plus places, groups and
// common words); look at the real database again before changing one.

/// Collections are listed, most lines first, until they hold this share of
/// the word's lines …
const double spreadCoverage = 0.80;

/// … or this many are listed.
const int spreadMaxListed = 6;

/// Collections added after those: short ones the word fills (an operator's
/// own record is a few dozen lines and never among the largest).
const int spreadMaxDense = 2;

/// A collection is such a one when the word has this many lines in it,
const int spreadDenseMinLines = 10;

/// is in this share of its lines,
const double spreadDenseShare = 0.10;

/// and that share is this many times the word's share of the whole corpus
/// (without this a word that is everywhere qualifies in any talkative
/// chapter).
const int spreadDenseLift = 5;

/// Label of the stories no collection holds.
const String spreadOtherLabel = '其他';

/// Which collection every story file is in, and how many lines each
/// collection and the corpus have ([queryStoryGroups]).
class StoryGroups {
  const StoryGroups({
    required this.groupOf,
    required this.labels,
    required this.groupLines,
    required this.corpusLines,
  });

  /// Story id → collection id ('' for a story no collection holds).
  final Map<String, String> groupOf;
  final Map<String, String> labels;
  final Map<String, int> groupLines;
  final int corpusLines;
}

/// One collection of a [TermSpread].
typedef SpreadPart = ({
  String id,
  String label,
  int lines,
  int chapters,

  /// The word's lines over the collection's lines.
  double share,
});

/// Where the lines holding a word are. A hint for where to look, not
/// something read.
class TermSpread {
  const TermSpread({
    required this.lines,
    required this.chapters,
    required this.collections,
    required this.listed,
    required this.dense,
    required this.restCount,
    required this.restShare,
  });

  final int lines;
  final int chapters;
  final int collections;

  /// The collections with the most lines.
  final List<SpreadPart> listed;

  /// Collections not among [listed] that the word fills.
  final List<SpreadPart> dense;

  /// The collections in neither list, and their share of [lines].
  final int restCount;
  final double restShare;
}

/// The spread of a word whose lines per story file are [perStory].
TermSpread computeTermSpread(Map<String, int> perStory, StoryGroups groups) {
  final lines = <String, int>{};
  final chapters = <String, int>{};
  var total = 0;
  for (final MapEntry(key: story, value: n) in perStory.entries) {
    if (n <= 0) continue;
    final group = groups.groupOf[story] ?? '';
    lines[group] = (lines[group] ?? 0) + n;
    chapters[group] = (chapters[group] ?? 0) + 1;
    total += n;
  }
  SpreadPart part(String id) {
    final all = groups.groupLines[id] ?? 0;
    return (
      id: id,
      label: id.isEmpty ? spreadOtherLabel : groups.labels[id] ?? id,
      lines: lines[id]!,
      chapters: chapters[id]!,
      share: all == 0 ? 0 : lines[id]! / all,
    );
  }

  final ids = lines.keys.toList()
    ..sort((a, b) {
      final byLines = lines[b]!.compareTo(lines[a]!);
      return byLines != 0 ? byLines : a.compareTo(b);
    });
  final listed = <SpreadPart>[];
  var covered = 0;
  for (final id in ids) {
    if (listed.length >= spreadMaxListed || covered >= total * spreadCoverage) {
      break;
    }
    listed.add(part(id));
    covered += lines[id]!;
  }
  final everywhere =
      groups.corpusLines == 0 ? 0.0 : total / groups.corpusLines;
  final dense = [
    for (final id in ids.skip(listed.length))
      // The stories no collection holds are not one story.
      if (id.isNotEmpty && lines[id]! >= spreadDenseMinLines) part(id),
  ]
      .where(
        (p) =>
            p.share >= spreadDenseShare &&
            p.share >= everywhere * spreadDenseLift,
      )
      .toList()
    ..sort((a, b) {
      final byShare = b.share.compareTo(a.share);
      return byShare != 0 ? byShare : a.id.compareTo(b.id);
    });
  final added = dense.take(spreadMaxDense).toList();
  final shown = covered + added.fold<int>(0, (n, p) => n + p.lines);
  return TermSpread(
    lines: total,
    chapters: perStory.values.where((n) => n > 0).length,
    collections: ids.length,
    listed: listed,
    dense: added,
    restCount: ids.length - listed.length - added.length,
    restShare: total == 0 ? 0 : (total - shown) / total,
  );
}

/// `N 行，K 个故事集：故事集 n 行 / c 章、…；占比高的：故事集 n 行（占该篇 p%）；
/// 另 M 个共 q%` — the one form every tool writes.
String formatTermSpread(TermSpread spread) {
  String percent(double share) {
    final p = (share * 100).round();
    return p == 0 ? '不到 1%' : '$p%';
  }

  return [
    '${spread.lines} 行，${spread.collections} 个故事集：${[
      for (final p in spread.listed) '${p.label} ${p.lines} 行 / ${p.chapters} 章',
    ].join('、')}',
    if (spread.dense.isNotEmpty)
      '占比高的：${[
        for (final p in spread.dense)
          '${p.label} ${p.lines} 行（占该篇 ${percent(p.share)}）',
      ].join('、')}',
    if (spread.restCount > 0)
      '另 ${spread.restCount} 个共 ${percent(spread.restShare)}',
  ].join('；');
}

/// Every story file's collection and the line counts [computeTermSpread]
/// needs. Sources: `story_catalog.collection_id`; for a story the catalog
/// does not have (a tutorial, a stage's own dialogue), the collection of its
/// entry (`entries.id` = `story:<story_id>`), named by `collections.name`;
/// `story_lines` for the counts.
Future<StoryGroups> queryStoryGroups(DatabaseExecutor db) async {
  Future<bool> has(String table) async => (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      ))
          .isNotEmpty;

  final groupOf = <String, String>{};
  final labels = <String, String>{};
  if (await hasStoryCatalog(db)) {
    final rows = await db.rawQuery(
      'SELECT story_id, collection_id, collection_name, collection_type '
      'FROM $storyCatalogTable',
    );
    for (final row in rows) {
      final id = '${row['collection_id']}';
      groupOf['${row['story_id']}'] = id;
      labels[id] ??= StoryCatalogEntry(
        storyId: '',
        collectionId: id,
        collectionName: '${row['collection_name']}',
        collectionType: '${row['collection_type']}',
        storySort: 0,
      ).collectionLabel;
    }
  }
  if (await has('entries') && await has('collections')) {
    const prefix = 'story:';
    final rows = await db.rawQuery(
      'SELECT e.id AS id, e.collection_id AS collection_id, c.name AS name '
      'FROM entries e JOIN collections c ON c.id = e.collection_id '
      "WHERE e.id LIKE '$prefix%'",
    );
    for (final row in rows) {
      final story = '${row['id']}'.substring(prefix.length);
      if (groupOf.containsKey(story)) continue;
      final id = '${row['collection_id']}';
      final name = '${row['name'] ?? ''}'.trim();
      groupOf[story] = id;
      labels[id] ??= name.isEmpty ? id : name;
    }
  }
  final groupLines = <String, int>{};
  var corpus = 0;
  for (final row in await db.rawQuery(
    'SELECT story_id, COUNT(*) AS n FROM story_lines GROUP BY story_id',
  )) {
    final n = (row['n'] as num).toInt();
    final group = groupOf['${row['story_id']}'] ?? '';
    groupLines[group] = (groupLines[group] ?? 0) + n;
    corpus += n;
  }
  return StoryGroups(
    groupOf: groupOf,
    labels: labels,
    groupLines: groupLines,
    corpusLines: corpus,
  );
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

/// Prefix of the catalog's collection types in an Endfield database
/// (`EF_MAIN`, …): its labels start with the game's name.
const String endfieldCollectionTypePrefix = 'EF_';

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
      'rogue' || 'roguelike' => '肉鸽',
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
