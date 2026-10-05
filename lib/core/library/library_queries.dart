/// 0.11 library page: read-only queries over the entry layer of the knowledge
/// base (`collections`, `entries`, `entry_links`, `normalized_records`).
///
/// Everything here is derived from the schema: which shelf an item sits on is
/// its collection's `kind`, which list it is in is its `type`, the order is
/// `sort_key`. No names, no per-activity rules. Pure Dart over
/// `sqflite_common` so tests can run it on an in-memory database.
library;

import 'package:sqflite_common/sqlite_api.dart';

/// Shelves are the collection kinds of the entry layer.
const List<String> shelfKinds = [
  'main',
  'activity',
  'memory',
  'roguelike',
  'sandbox',
  'retro',
];

/// The shelf of items that belong to no collection (operators, enemies,
/// items, medals, skins, mails, world-view texts …).
const String codexShelf = 'codex';

/// One shelf and how much is on it.
class ShelfSummary {
  const ShelfSummary({
    required this.kind,
    required this.collections,
    required this.stories,
  });

  final String kind;
  final int collections;
  final int stories;
}

/// One collection (main chapter, activity, operator record set, roguelike
/// topic …) in a shelf list.
class LibraryCollection {
  const LibraryCollection({
    required this.id,
    required this.kind,
    required this.name,
    required this.stories,
    required this.others,
    this.startTime,
    this.sortKey,
  });

  factory LibraryCollection.fromRow(Map<String, Object?> row) =>
      LibraryCollection(
        id: '${row['id']}',
        kind: '${row['kind']}',
        name: '${row['name'] ?? row['id']}',
        stories: (row['stories'] as num?)?.toInt() ?? 0,
        others: (row['others'] as num?)?.toInt() ?? 0,
        startTime: (row['start_time'] as num?)?.toInt(),
        sortKey: (row['sort_key'] as num?)?.toInt(),
      );

  final String id;
  final String kind;
  final String name;
  final int stories;

  /// Readable entries that are not stories.
  final int others;

  /// Release time, unix seconds.
  final int? startTime;
  final int? sortKey;
}

/// One entry in a list.
class LibraryEntry {
  const LibraryEntry({
    required this.id,
    required this.type,
    required this.name,
    this.code,
    this.group,
    this.rawId,
    this.collectionId,
    this.collectionName,
    this.entityId,
    this.synopsis,
  });

  factory LibraryEntry.fromRow(Map<String, Object?> row) => LibraryEntry(
        id: '${row['id']}',
        type: '${row['type']}',
        name: '${row['name'] ?? ''}'.trim(),
        code: _text(row['code']),
        group: _text(row['group_name']),
        rawId: _text(row['raw_id']),
        collectionId: _text(row['collection_id']),
        collectionName: _text(row['collection_name']),
        entityId: _text(row['entity_id']),
        synopsis: _text(row['synopsis']),
      );

  final String id;
  final String type;
  final String name;

  /// Stage / story code (`BB-7`), operator code …
  final String? code;

  /// `行动前` / `行动后` / `幕间` for stories.
  final String? group;

  /// For stories: the `story_lines.story_id`.
  final String? rawId;
  final String? collectionId;
  final String? collectionName;
  final String? entityId;

  /// The official one-paragraph synopsis (stories, when the catalog has it).
  final String? synopsis;

  bool get isStory => type == 'story';
}

String? _text(Object? value) {
  final t = '${value ?? ''}'.trim();
  return t.isEmpty ? null : t;
}

/// One block of an entry's text.
class EntryTextBlock {
  const EntryTextBlock({required this.title, required this.content, this.section});

  final String title;
  final String? section;
  final String content;
}

/// A binding of an entry to another one.
class EntryBinding {
  const EntryBinding({
    required this.relation,
    required this.outgoing,
    required this.entry,
  });

  final String relation;

  /// True when the opened entry is the source (`src --relation--> entry`).
  final bool outgoing;
  final LibraryEntry entry;
}

/// A story's place in its collection.
class StoryPlace {
  const StoryPlace({
    required this.entry,
    this.previous,
    this.next,
  });

  final LibraryEntry entry;
  final LibraryEntry? previous;
  final LibraryEntry? next;
}

String escapeLike(String term) => term
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');

/// A readable entry has text of its own: a story file, a record, an operator
/// document.
const String _readable =
    "(e.type = 'story' OR e.record_id IS NOT NULL OR e.type = 'operator')";

Future<bool> _hasTable(DatabaseExecutor db, String name) async => (await db
        .rawQuery('SELECT 1 FROM sqlite_master WHERE name = ?', [name]))
    .isNotEmpty;

/// True when the database has the entry layer (schema 5).
Future<bool> hasEntryLayer(DatabaseExecutor db) async =>
    await _hasTable(db, 'entries') && await _hasTable(db, 'collections');

/// The shelves with their counts, in [shelfKinds] order; shelves without a
/// collection are left out. [codexTypes] is the shelf of free entries.
Future<List<ShelfSummary>> shelfSummaries(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    'SELECT c.kind AS kind, COUNT(DISTINCT c.id) AS collections, '
    "SUM(CASE WHEN e.type = 'story' THEN 1 ELSE 0 END) AS stories "
    'FROM collections c LEFT JOIN entries e ON e.collection_id = c.id '
    'GROUP BY c.kind',
  );
  final byKind = {
    for (final r in rows)
      '${r['kind']}': ShelfSummary(
        kind: '${r['kind']}',
        collections: (r['collections'] as num).toInt(),
        stories: (r['stories'] as num?)?.toInt() ?? 0,
      ),
  };
  return [
    for (final kind in shelfKinds)
      if (byKind[kind] != null) byKind[kind]!,
  ];
}

/// Entry types of the codex shelf with their counts.
Future<List<({String type, int count})>> codexTypes(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    'SELECT e.type AS type, COUNT(*) AS n FROM entries e '
    'WHERE e.collection_id IS NULL AND $_readable '
    'GROUP BY e.type ORDER BY n DESC',
  );
  return [
    for (final r in rows) (type: '${r['type']}', count: (r['n'] as num).toInt()),
  ];
}

/// The collections of [kind]: newest release first when they have a release
/// time, otherwise in game order. Collections with nothing to read are left
/// out.
Future<List<LibraryCollection>> collectionsOfKind(
  DatabaseExecutor db,
  String kind,
) async {
  final rows = await db.rawQuery(
    'SELECT c.id, c.kind, c.name, c.start_time, c.sort_key, '
    "SUM(CASE WHEN e.type = 'story' THEN 1 ELSE 0 END) AS stories, "
    "SUM(CASE WHEN e.type <> 'story' AND $_readable THEN 1 ELSE 0 END) AS others "
    'FROM collections c LEFT JOIN entries e ON e.collection_id = c.id '
    'WHERE c.kind = ? GROUP BY c.id',
    [kind],
  );
  final list = [
    for (final r in rows) LibraryCollection.fromRow(r),
  ].where((c) => c.stories + c.others > 0).toList();
  list.sort((a, b) {
    final ta = a.startTime ?? 0, tb = b.startTime ?? 0;
    if (ta != tb) return tb.compareTo(ta);
    final sa = a.sortKey ?? 1 << 30, sb = b.sortKey ?? 1 << 30;
    if (sa != sb) return sa.compareTo(sb);
    return a.id.compareTo(b.id);
  });
  return list;
}

/// One collection with its release time, or null.
Future<LibraryCollection?> collectionById(DatabaseExecutor db, String id) async {
  final rows = await db.rawQuery(
    'SELECT c.id, c.kind, c.name, c.start_time, c.sort_key, '
    "SUM(CASE WHEN e.type = 'story' THEN 1 ELSE 0 END) AS stories, "
    "SUM(CASE WHEN e.type <> 'story' AND $_readable THEN 1 ELSE 0 END) AS others "
    'FROM collections c LEFT JOIN entries e ON e.collection_id = c.id '
    'WHERE c.id = ? GROUP BY c.id',
    [id],
  );
  return rows.isEmpty ? null : LibraryCollection.fromRow(rows.first);
}

/// Readable entry types of a collection with their counts (stories not
/// included; enemies come from the stage bindings).
Future<List<({String type, int count})>> collectionTypes(
  DatabaseExecutor db,
  String collectionId,
) async {
  final rows = await db.rawQuery(
    'SELECT e.type AS type, COUNT(*) AS n FROM entries e '
    "WHERE e.collection_id = ? AND e.type <> 'story' AND $_readable "
    'GROUP BY e.type ORDER BY n DESC',
    [collectionId],
  );
  final out = [
    for (final r in rows) (type: '${r['type']}', count: (r['n'] as num).toInt()),
  ];
  if (await _hasTable(db, 'entry_links')) {
    final enemies = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM collection_enemies WHERE collection_id = ?',
      [collectionId],
    );
    final n = (enemies.first['n'] as num).toInt();
    if (n > 0) out.add((type: 'enemy', count: n));
  }
  return out;
}

/// The stories of a collection in reading order, with the official synopsis
/// when the knowledge base has the story catalog.
Future<List<LibraryEntry>> storiesOf(
  DatabaseExecutor db,
  String collectionId,
) async {
  final catalog = await _hasTable(db, 'story_catalog');
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id, e.sort_key, '
    '${catalog ? 's.synopsis' : 'NULL'} AS synopsis '
    'FROM entries e '
    '${catalog ? 'LEFT JOIN story_catalog s ON s.story_id = e.raw_id ' : ''}'
    "WHERE e.collection_id = ? AND e.type = 'story' "
    'ORDER BY e.sort_key, e.id',
    [collectionId],
  );
  return [for (final r in rows) LibraryEntry.fromRow(r)];
}

/// The entries of one type, in a collection ([collectionId]) or, without it,
/// the free entries of the codex. [query] filters by name or code.
Future<List<LibraryEntry>> entriesOfType(
  DatabaseExecutor db,
  String type, {
  String? collectionId,
  String query = '',
  int limit = 2000,
}) async {
  final q = query.trim();
  final like = q.isEmpty ? '' : "AND (e.name LIKE ? ESCAPE '\\' OR e.code LIKE ? ESCAPE '\\') ";
  final args = <Object?>[
    if (q.isNotEmpty) ...['%${escapeLike(q)}%', '%${escapeLike(q)}%'],
  ];
  final String where;
  final String from;
  final List<Object?> head;
  if (type == 'enemy' && collectionId != null) {
    from = 'entries e JOIN collection_enemies ce ON ce.enemy_id = e.id';
    where = 'ce.collection_id = ? AND e.type = ?';
    head = [collectionId, type];
  } else {
    from = 'entries e';
    where = collectionId == null
        ? 'e.collection_id IS NULL AND e.type = ?'
        : 'e.collection_id = ? AND e.type = ?';
    head = [if (collectionId != null) collectionId, type];
  }
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id, e.entity_id FROM $from '
    'WHERE $where AND $_readable $like'
    'ORDER BY e.sort_key, e.name, e.id LIMIT ?',
    [...head, ...args, limit],
  );
  return [for (final r in rows) LibraryEntry.fromRow(r)];
}

/// One entry by id, with its collection name.
Future<LibraryEntry?> entryById(DatabaseExecutor db, String id) async {
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id, e.entity_id, c.name AS collection_name '
    'FROM entries e LEFT JOIN collections c ON c.id = e.collection_id '
    'WHERE e.id = ?',
    [id],
  );
  return rows.isEmpty ? null : LibraryEntry.fromRow(rows.first);
}

/// The text of a non-story entry: its records, or for an operator its
/// profile document.
Future<List<EntryTextBlock>> entryTexts(
  DatabaseExecutor db,
  LibraryEntry entry,
) async {
  if (entry.type == 'operator' && entry.entityId != null) {
    final rows = await db.rawQuery(
      'SELECT title, content FROM entity_documents WHERE entity_id = ? '
      'ORDER BY document_type',
      [entry.entityId],
    );
    return [
      for (final r in rows)
        EntryTextBlock(title: '${r['title'] ?? ''}', content: '${r['content'] ?? ''}'),
    ];
  }
  final rows = await db.rawQuery(
    'SELECT title, section, content FROM normalized_records '
    'WHERE entry_id = ? ORDER BY line_start, id',
    [entry.id],
  );
  return [
    for (final r in rows)
      EntryTextBlock(
        title: '${r['title'] ?? ''}',
        section: _text(r['section']),
        content: '${r['content'] ?? ''}',
      ),
  ];
}

/// The bindings of an entry (both directions), at most [limit] per direction.
Future<List<EntryBinding>> entryBindings(
  DatabaseExecutor db,
  String entryId, {
  int limit = 80,
}) async {
  if (!await _hasTable(db, 'entry_links')) return const [];
  final out = <EntryBinding>[];
  for (final outgoing in [true, false]) {
    final rows = await db.rawQuery(
      'SELECT l.relation AS relation, e.id, e.type, e.name, e.code, '
      'e.group_name, e.raw_id, e.collection_id, e.entity_id '
      'FROM entry_links l JOIN entries e ON e.id = '
      '${outgoing ? 'l.dst' : 'l.src'} '
      'WHERE ${outgoing ? 'l.src' : 'l.dst'} = ? '
      'ORDER BY l.relation, e.type, e.sort_key, e.name LIMIT ?',
      [entryId, limit],
    );
    for (final r in rows) {
      out.add(EntryBinding(
        relation: '${r['relation']}',
        outgoing: outgoing,
        entry: LibraryEntry.fromRow(r),
      ),);
    }
  }
  return out;
}

/// The entry of a story file with the one before and after it in its
/// collection, or null when the story has no entry (older databases).
Future<StoryPlace?> storyPlace(DatabaseExecutor db, String storyId) async {
  if (!await hasEntryLayer(db)) return null;
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id, e.sort_key, c.name AS collection_name '
    'FROM entries e LEFT JOIN collections c ON c.id = e.collection_id '
    "WHERE e.type = 'story' AND e.raw_id = ? LIMIT 1",
    [storyId],
  );
  if (rows.isEmpty) return null;
  final row = rows.first;
  final entry = LibraryEntry.fromRow(row);
  final collection = entry.collectionId;
  if (collection == null) return StoryPlace(entry: entry);
  final sort = (row['sort_key'] as num?)?.toInt() ?? 0;
  Future<LibraryEntry?> neighbour(bool before) async {
    final r = await db.rawQuery(
      'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
      'e.collection_id FROM entries e '
      "WHERE e.collection_id = ? AND e.type = 'story' AND "
      '${before ? '(e.sort_key < ? OR (e.sort_key = ? AND e.id < ?))' : '(e.sort_key > ? OR (e.sort_key = ? AND e.id > ?))'} '
      'ORDER BY e.sort_key ${before ? 'DESC' : 'ASC'}, e.id ${before ? 'DESC' : 'ASC'} LIMIT 1',
      [collection, sort, sort, entry.id],
    );
    return r.isEmpty ? null : LibraryEntry.fromRow(r.first);
  }

  return StoryPlace(
    entry: entry,
    previous: await neighbour(true),
    next: await neighbour(false),
  );
}

/// Collections and entries whose name or code contains [query].
Future<({List<LibraryCollection> collections, List<LibraryEntry> entries})>
    searchLibrary(
  DatabaseExecutor db,
  String query, {
  int limit = 60,
}) async {
  final q = query.trim();
  if (q.isEmpty) return (collections: const <LibraryCollection>[], entries: const <LibraryEntry>[]);
  final like = '%${escapeLike(q)}%';
  final collections = await db.rawQuery(
    'SELECT c.id, c.kind, c.name, c.start_time, c.sort_key, '
    "SUM(CASE WHEN e.type = 'story' THEN 1 ELSE 0 END) AS stories, "
    "SUM(CASE WHEN e.type <> 'story' AND $_readable THEN 1 ELSE 0 END) AS others "
    'FROM collections c LEFT JOIN entries e ON e.collection_id = c.id '
    "WHERE c.name LIKE ? ESCAPE '\\' GROUP BY c.id "
    'ORDER BY c.start_time DESC LIMIT 30',
    [like],
  );
  final entries = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id, e.entity_id, c.name AS collection_name '
    'FROM entries e LEFT JOIN collections c ON c.id = e.collection_id '
    "WHERE $_readable AND (e.name LIKE ? ESCAPE '\\' OR e.code LIKE ? ESCAPE '\\') "
    "ORDER BY (e.type = 'story') DESC, length(e.name), e.name LIMIT ?",
    [like, like, limit],
  );
  return (
    collections: [
      for (final r in collections) LibraryCollection.fromRow(r),
    ].where((c) => c.stories + c.others > 0).toList(),
    entries: [for (final r in entries) LibraryEntry.fromRow(r)],
  );
}
