/// 0.11 library page: read-only queries over the entry layer of the knowledge
/// base (`collections`, `entries`, `entry_links`, `normalized_records`).
///
/// Everything here is derived from the schema: which shelf an item sits on is
/// its collection's `kind`, which list it is in is its `type`, the order is
/// `sort_key`. No names, no per-activity rules. Pure Dart over
/// `sqflite_common` so tests can run it on an in-memory database.
library;

import 'package:sqflite_common/sqlite_api.dart';

import '../gamedata/game.dart';
import '../gamedata/name_similarity.dart' show homophoneCost, nameDistance;
import '../gamedata/story_catalog.dart' show escapeLike;

part 'library_search.dart';

/// Shelves are the collection kinds of the entry layer.
const List<String> shelfKinds = [
  'main',
  'sidestory',
  'ministory',
  'branchline',
  'activity',
  'memory',
  'roguelike',
  'sandbox',
];

/// 0.12: Endfield's shelves in order (kinds without the ef/ namespace;
/// the build writes the same list, endfieldShelfKinds).
const List<String> endfieldShelfOrder = [
  'main',
  'discovery',
  'side',
  'activity',
  'other',
  // Conversations outside missions (a level's interactions, an enemy's
  // encounter): unnamed in the game, shown as 其他.
  'world',
  'archive',
  'memory',
  // Missions the client keeps conversations of but does not define.
  'unused',
];

/// The shelf of items that belong to no collection (enemies, items, medals,
/// mails, world-view texts …). Operators have a shelf of their own (their
/// record sets are the `memory` collections), and everything that belongs
/// to an operator is on the operator's page.
const String codexShelf = 'codex';

/// [game]'s codex shelf (Endfield's is in its id namespace, so it routes to
/// its database like every other Endfield id).
String codexShelfOf(Game game) =>
    game == Game.endfield ? '${endfieldIdPrefix}codex' : codexShelf;

/// Whether [shelf] is a game's codex.
bool isCodexShelf(String? shelf) =>
    shelf == codexShelf || shelf == '${endfieldIdPrefix}codex';

/// The shelf kind whose list is the operators (the record collections hang
/// below them).
const String operatorShelf = 'memory';

/// [game]'s operator shelf.
String operatorShelfOf(Game game) =>
    game == Game.endfield ? '$endfieldIdPrefix$operatorShelf' : operatorShelf;

/// An entry bound to an operator (`belongs_to` an `operator:` entry): a
/// module, a skin, a paradox simulation stage. It is shown on the operator's
/// page, not in the codex.
const String _ownedByOperator = 'EXISTS (SELECT 1 FROM entry_links ol '
    "WHERE ol.src = e.id AND ol.relation = 'belongs_to' "
    "AND ol.dst LIKE 'operator:%')";

/// A story that is part of another entry (an ending's pages, a month squad's
/// short stories): it is read from that entry's page, not listed on its own.
const String _isPart = 'EXISTS (SELECT 1 FROM entry_links pl '
    "WHERE pl.src = e.id AND pl.relation = 'part_of')";

/// Dialogue played inside a battle (tutorial popups, training, in-battle
/// talk): it is read at the end of the story of its stage, or on the stage's
/// page, never listed on its own.
const String _isAttached = 'EXISTS (SELECT 1 FROM entry_links al '
    "WHERE al.src = e.id AND al.relation = 'attached_to')";

/// A stage (or story) that has such dialogue attached.
const String _hostsAttached = 'EXISTS (SELECT 1 FROM entry_links hl '
    "WHERE hl.dst = e.id AND hl.relation = 'attached_to')";

/// Types of a collection's entries that are its own parts and are listed
/// right on its page (the notes, endings and month squads of a roguelike
/// topic) instead of behind a menu.
const Set<String> inlineEntryTypes = {
  'roguelike_tip',
  'roguelike_ending',
  'roguelike_squad',
  'sandbox_act',
};

/// Entry types whose text is written as markdown (headings, lists): the
/// profile documents and the events (event text, options, what follows).
const Set<String> markdownEntryTypes = {
  'operator',
  'token',
  'trap',
  'roguelike_scene',
  'sandbox_event',
};

/// Events: their text is an opening and options nested under it.
const Set<String> eventEntryTypes = {'roguelike_scene', 'sandbox_event'};

/// The types whose text introduces their collection.
const Set<String> introEntryTypes = {
  'roguelike_topic',
  'sandbox_topic',
  // 0.12: an Endfield mission's own description.
  'mission_intro',
  // 0.12: the part of the Endfield archive a collection is in (no text;
  // its group heads the archive shelf).
  'archive_section',
};

/// 0.12: collection kinds (without the game's namespace) that only hang
/// below an operator (its Baker topics, its interactions on the Dijiang):
/// listed on the operator's page, never as shelves.
const Set<String> ownedCollectionKinds = {'baker', 'ship'};

/// `'a','b'` for an SQL `IN (…)` of [types] (fixed identifiers, not input).
String _sqlList(Set<String> types) => types.map((t) => "'$t'").join(',');

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
    this.intro,
    this.group,
    this.firstStory,
    this.otherTypes = 0,
    this.otherType,
    this.otherEntry,
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
        intro: _text(row['intro']),
        group: _text(row['group_name']),
        firstStory: _text(row['first_story']),
        otherTypes: (row['other_types'] as num?)?.toInt() ?? 0,
        otherType: _text(row['other_type']),
        otherEntry: _text(row['other_entry']),
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

  /// The first block of the collection's introduction ([introEntryTypes]):
  /// an Endfield mission's description, a roguelike topic's lead.
  final String? intro;

  /// Where the collection is (the group of its introduction entry: an
  /// Endfield mission's region); a shelf groups its collections by it.
  final String? group;

  /// The story file of its first listed story (with [stories] == 1, the
  /// only one).
  final String? firstStory;

  /// How many types its other entries are of, the (first) type, and the
  /// (first) entry: a collection with one entry, or one kind of entry,
  /// opens it right away instead of a page with one row.
  final int otherTypes;
  final String? otherType;
  final String? otherEntry;
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
  const EntryTextBlock(
      {required this.title, required this.content, this.section,});

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

/// Entry types whose text is a profile document (markdown-like) of a
/// character-table row: operators, and the summons and deployable devices
/// that share the table.
const Set<String> documentEntryTypes = {'operator', 'token', 'trap'};

/// A readable entry has text of its own: a story file, a record, a profile
/// document.
const String _readable = "(e.type = 'story' OR e.record_id IS NOT NULL OR "
    "e.type IN ('operator', 'token', 'trap') OR $_hostsAttached)";

Future<bool> _hasTable(DatabaseExecutor db, String name) async =>
    (await db.rawQuery('SELECT 1 FROM sqlite_master WHERE name = ?', [name]))
        .isNotEmpty;

/// True when the database has the entry layer (schema 5).
Future<bool> hasEntryLayer(DatabaseExecutor db) async =>
    await _hasTable(db, 'entries') && await _hasTable(db, 'collections');

/// The shelves with their counts, in [shelfKinds] order; shelves without a
/// collection are left out. [codexTypes] is the shelf of free entries.
Future<List<ShelfSummary>> shelfSummaries(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    'SELECT c.kind AS kind, COUNT(DISTINCT COALESCE(c.parent_id, c.id)) AS collections, '
    "SUM(CASE WHEN e.type = 'story' AND NOT $_isAttached THEN 1 ELSE 0 END) AS stories "
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
  final known = [
    ...shelfKinds,
    for (final kind in endfieldShelfOrder) '$endfieldIdPrefix$kind',
  ];
  bool owned(String kind) => ownedCollectionKinds.contains(
        kind.startsWith(endfieldIdPrefix) ? kind.substring(endfieldIdPrefix.length) : kind,
      );
  return [
    for (final kind in known)
      if (byKind[kind] != null) byKind[kind]!,
    // A kind a later build introduces still gets a shelf, after the known
    // ones (it reads as "其他" until the interface names it).
    for (final kind in byKind.keys.toList()..sort())
      if (!known.contains(kind) && !owned(kind)) byKind[kind]!,
  ];
}

/// Entry types of the codex shelf with their counts.
/// Types the codex lists whole, the entries that belong to a collection too
/// (a medal of an activity is still a medal): they are reached from the
/// codex and from their collection.
const Set<String> codexSpanningTypes = {'medal', 'item', 'charm'};

Future<List<({String type, int count})>> codexTypes(DatabaseExecutor db) async {
  final owned =
      await _hasTable(db, 'entry_links') ? 'AND NOT $_ownedByOperator ' : '';
  final rows = await db.rawQuery(
    'SELECT e.type AS type, COUNT(*) AS n FROM entries e '
    "WHERE (e.collection_id IS NULL OR e.type IN ('medal', 'item', 'charm')) "
    "AND e.type <> 'operator' AND $_readable "
    '$owned'
    'GROUP BY e.type ORDER BY n DESC',
  );
  return [
    for (final r in rows)
      (type: '${r['type']}', count: (r['n'] as num).toInt()),
  ];
}

/// The columns of a [LibraryCollection] row, over `collections c LEFT JOIN
/// entries e ON e.collection_id = c.id` grouped by `c.id`. The introduction
/// counts as neither a story nor another entry: it is the collection's own.
final String _collectionColumns =
    'c.id, c.kind, c.name, c.start_time, c.sort_key, '
    "SUM(CASE WHEN e.type = 'story' AND NOT $_isAttached THEN 1 ELSE 0 END) AS stories, "
    "SUM(CASE WHEN e.type <> 'story' AND e.type NOT IN (${_sqlList(introEntryTypes)}) "
    'AND $_readable THEN 1 ELSE 0 END) AS others, '
    '(SELECT r.content FROM entries i JOIN normalized_records r ON r.id = i.record_id '
    'WHERE i.collection_id = c.id AND i.type IN (${_sqlList(introEntryTypes)}) LIMIT 1) AS intro, '
    '(SELECT i.group_name FROM entries i WHERE i.collection_id = c.id '
    'AND i.type IN (${_sqlList(introEntryTypes)}) AND i.group_name IS NOT NULL LIMIT 1) AS group_name, '
    "MIN(CASE WHEN e.type = 'story' AND NOT $_isAttached THEN e.raw_id END) AS first_story, "
    "COUNT(DISTINCT CASE WHEN e.type <> 'story' AND e.type NOT IN (${_sqlList(introEntryTypes)}) "
    'AND $_readable THEN e.type END) AS other_types, '
    "MIN(CASE WHEN e.type <> 'story' AND e.type NOT IN (${_sqlList(introEntryTypes)}) "
    'AND $_readable THEN e.type END) AS other_type, '
    "MIN(CASE WHEN e.type <> 'story' AND e.type NOT IN (${_sqlList(introEntryTypes)}) "
    'AND $_readable THEN e.id END) AS other_entry';

/// The collections of [kind]: newest release first when they have a release
/// time, otherwise in game order. Collections with nothing to read are left
/// out.
Future<List<LibraryCollection>> collectionsOfKind(
  DatabaseExecutor db,
  String kind,
) async {
  final rows = await db.rawQuery(
    'SELECT $_collectionColumns '
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

/// The record sets (`memory` collections) of an operator, in game order.
Future<List<LibraryCollection>> collectionsOwnedBy(
  DatabaseExecutor db,
  String ownerEntryId,
) async {
  final rows = await db.rawQuery(
    'SELECT $_collectionColumns '
    'FROM collections c LEFT JOIN entries e ON e.collection_id = c.id '
    'WHERE c.parent_id = ? GROUP BY c.id ORDER BY c.sort_key, c.id',
    [ownerEntryId],
  );
  return [
    for (final r in rows) LibraryCollection.fromRow(r),
  ].where((c) => c.stories + c.others > 0).toList();
}

/// What belongs to an operator besides its profile: modules, skins, paradox
/// simulation stages (entries bound to it by `belongs_to`), by type.
Future<List<LibraryEntry>> entriesOwnedBy(
  DatabaseExecutor db,
  String ownerEntryId,
) async {
  if (!await _hasTable(db, 'entry_links')) return const [];
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id, e.entity_id FROM entry_links l '
    'JOIN entries e ON e.id = l.src '
    "WHERE l.dst = ? AND l.relation IN ('belongs_to', 'summoned_by') "
    'ORDER BY e.type, e.sort_key, e.code, e.name, e.id',
    [ownerEntryId],
  );
  return [for (final r in rows) LibraryEntry.fromRow(r)];
}

/// The other operators that are the same person as [entryId] (`same_person`:
/// alternate versions of one operator): the original first, then the
/// alternates. Empty for an operator with no alternate.
Future<List<LibraryEntry>> samePersonOf(
  DatabaseExecutor db,
  String entryId,
) async {
  if (!await _hasTable(db, 'entry_links')) return const [];
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id, e.entity_id, '
    "(e.id IN (SELECT dst FROM entry_links WHERE relation = 'same_person')) AS original "
    'FROM entries e WHERE e.id <> ?1 AND ('
    "e.id IN (SELECT dst FROM entry_links WHERE relation = 'same_person' AND src = ?1) "
    "OR e.id IN (SELECT src FROM entry_links WHERE relation = 'same_person' AND dst = ?1) "
    "OR e.id IN (SELECT src FROM entry_links WHERE relation = 'same_person' AND dst IN "
    "(SELECT dst FROM entry_links WHERE relation = 'same_person' AND src = ?1))) "
    'ORDER BY original DESC, e.id',
    [entryId],
  );
  return [for (final r in rows) LibraryEntry.fromRow(r)];
}

/// One collection with its release time, or null.
Future<LibraryCollection?> collectionById(
    DatabaseExecutor db, String id,) async {
  final rows = await db.rawQuery(
    'SELECT $_collectionColumns '
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
    "WHERE e.collection_id = ? AND e.type <> 'story' AND "
    'e.type NOT IN (${_sqlList(introEntryTypes)}) AND $_readable '
    'GROUP BY e.type ORDER BY n DESC',
    [collectionId],
  );
  final out = [
    for (final r in rows)
      (type: '${r['type']}', count: (r['n'] as num).toInt()),
  ];
  if (await _hasTable(db, 'entry_links')) {
    final placed = await db.rawQuery(
      'SELECT e.type AS type, COUNT(*) AS n FROM collection_enemies ce '
      'JOIN entries e ON e.id = ce.enemy_id WHERE ce.collection_id = ? '
      'GROUP BY e.type',
      [collectionId],
    );
    for (final r in placed) {
      final n = (r['n'] as num).toInt();
      if (n > 0 && stageBoundTypes.contains('${r['type']}')) {
        out.add((type: '${r['type']}', count: n));
      }
    }
  }
  return out;
}

/// The types whose place in a collection is the stages they appear in
/// (`appears_in`), not a collection of their own: enemies, and the traps and
/// summons a level places.
const Set<String> stageBoundTypes = {'enemy', 'trap', 'token'};

/// The stories of a collection in reading order, with the official synopsis
/// when the knowledge base has the story catalog.
Future<List<LibraryEntry>> storiesOf(
  DatabaseExecutor db,
  String collectionId,
) async {
  final catalog = await _hasTable(db, 'story_catalog');
  final parts = await _hasTable(db, 'entry_links')
      ? 'AND NOT $_isPart AND NOT $_isAttached '
      : '';
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id, e.sort_key, '
    '${catalog ? 's.synopsis' : 'NULL'} AS synopsis '
    'FROM entries e '
    '${catalog ? 'LEFT JOIN story_catalog s ON s.story_id = e.raw_id ' : ''}'
    "WHERE e.collection_id = ? AND e.type = 'story' $parts"
    'ORDER BY e.sort_key, e.id',
    [collectionId],
  );
  return [for (final r in rows) LibraryEntry.fromRow(r)];
}

/// The introduction of a collection: the text of its `roguelike_topic` entry.
Future<String?> collectionIntro(
    DatabaseExecutor db, String collectionId,) async {
  final rows = await db.rawQuery(
    'SELECT r.content AS content FROM entries e '
    'JOIN normalized_records r ON r.entry_id = e.id '
    'WHERE e.collection_id = ? AND e.type IN (${_sqlList(introEntryTypes)}) '
    'ORDER BY r.line_start, r.id',
    [collectionId],
  );
  final text =
      rows.map((r) => '${r['content'] ?? ''}'.trim()).join('\n').trim();
  return text.isEmpty ? null : text;
}

/// The own parts of a collection ([inlineEntryTypes]) in order, each with
/// the last line of its text (an ending's sentence, a squad's one-liner) as
/// `synopsis` and its group (a squad's month).
Future<List<LibraryEntry>> inlineEntries(
  DatabaseExecutor db,
  String collectionId,
) async {
  final types = _sqlList(inlineEntryTypes);
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id, e.entity_id, (SELECT r.content FROM normalized_records r '
    'WHERE r.entry_id = e.id ORDER BY r.line_start DESC, r.id DESC LIMIT 1) '
    'AS synopsis FROM entries e '
    'WHERE e.collection_id = ? AND e.type IN ($types) '
    'ORDER BY e.type, e.sort_key, e.name, e.id',
    [collectionId],
  );
  // The sentence is the last line: a squad's text opens with its subtitle.
  return [
    for (final r in rows)
      LibraryEntry.fromRow({
        ...r,
        'synopsis': '${r['synopsis'] ?? ''}'.trim().split('\n').last,
      }),
  ];
}

/// The stories that are parts of [entryId], in order (see [_isPart]).
Future<List<LibraryEntry>> entryParts(
  DatabaseExecutor db,
  String entryId,
) async {
  if (!await _hasTable(db, 'entry_links')) return const [];
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id FROM entry_links l JOIN entries e ON e.id = l.src '
    "WHERE l.dst = ? AND l.relation = 'part_of' "
    'ORDER BY e.sort_key, e.id',
    [entryId],
  );
  return [for (final r in rows) LibraryEntry.fromRow(r)];
}

/// The stories attached to [hostId] (a story or a stage entry): in-battle
/// dialogue, in reading order (see [_isAttached]).
Future<List<LibraryEntry>> attachedStories(
  DatabaseExecutor db,
  String hostId,
) async {
  if (!await _hasTable(db, 'entry_links')) return const [];
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id FROM entry_links l JOIN entries e ON e.id = l.src '
    "WHERE l.dst = ? AND l.relation = 'attached_to' AND e.type = 'story' "
    'ORDER BY e.sort_key, e.id',
    [hostId],
  );
  return [for (final r in rows) LibraryEntry.fromRow(r)];
}

/// The story that [storyId]'s dialogue is read in (its file id), or null
/// when the story is not attached to another story.
Future<String?> storyHostOf(DatabaseExecutor db, String storyId) async {
  if (!await _hasTable(db, 'entry_links')) return null;
  final rows = await db.rawQuery(
    'SELECT h.raw_id AS raw FROM entries e '
    "JOIN entry_links l ON l.src = e.id AND l.relation = 'attached_to' "
    "JOIN entries h ON h.id = l.dst AND h.type = 'story' "
    "WHERE e.type = 'story' AND e.raw_id = ? LIMIT 1",
    [storyId],
  );
  return rows.isEmpty ? null : _text(rows.first['raw']);
}

/// The entries of one type, in a collection ([collectionId]) or, without it,
/// the free entries of the codex. [query] filters by name or code.
Future<List<LibraryEntry>> entriesOfType(
  DatabaseExecutor db,
  String type, {
  String? collectionId,
  String query = '',
  List<String?>? groups,
  int limit = 2000,
}) async {
  final q = query.trim();
  final like = q.isEmpty
      ? ''
      : "AND (e.name LIKE ? ESCAPE '\\' OR e.code LIKE ? ESCAPE '\\') ";
  final args = <Object?>[
    if (q.isNotEmpty) ...['%${escapeLike(q)}%', '%${escapeLike(q)}%'],
  ];
  final groupFilter = _groupFilter(groups, args);
  final likeAndGroup = '$like$groupFilter';
  final String where;
  final String from;
  final List<Object?> head;
  if (stageBoundTypes.contains(type) && collectionId != null) {
    from = 'entries e JOIN collection_enemies ce ON ce.enemy_id = e.id';
    where = 'ce.collection_id = ? AND e.type = ?';
    head = [collectionId, type];
  } else {
    from = 'entries e';
    where = collectionId == null
        ? (codexSpanningTypes.contains(type)
            ? 'e.type = ?'
            : 'e.collection_id IS NULL AND e.type = ?')
        : 'e.collection_id = ? AND e.type = ?';
    head = [if (collectionId != null) collectionId, type];
  }
  final rows = await db.rawQuery(
    'SELECT e.id, e.type, e.name, e.code, e.group_name, e.raw_id, '
    'e.collection_id, e.entity_id FROM $from '
    'WHERE $where AND $_readable '
    "${collectionId == null ? 'AND NOT $_ownedByOperator ' : ''}"
    '$likeAndGroup'
    'ORDER BY e.sort_key, e.name, e.id LIMIT ?',
    [...head, ...args, limit],
  );
  return [for (final r in rows) LibraryEntry.fromRow(r)];
}

/// `AND (e.group_name IN (…) [OR e.group_name IS NULL])` for [groups] (a null
/// element is "no group"), appending the values to [args]; empty for null.
String _groupFilter(List<String?>? groups, List<Object?> args) {
  if (groups == null || groups.isEmpty) return '';
  final named = [
    for (final g in groups)
      if (g != null) g,
  ];
  args.addAll(named);
  final parts = [
    if (named.isNotEmpty)
      'e.group_name IN (${List.filled(named.length, '?').join(',')})',
    if (groups.contains(null)) "(e.group_name IS NULL OR e.group_name = '')",
  ];
  return 'AND (${parts.join(' OR ')}) ';
}

/// The groups of one type's entries (in a collection or in the codex) with
/// their counts, in the order the entries come. A null group is "no group".
Future<List<({String? group, int count})>> entryGroups(
  DatabaseExecutor db,
  String type, {
  String? collectionId,
}) async {
  final enemies = stageBoundTypes.contains(type) && collectionId != null;
  final rows = await db.rawQuery(
    'SELECT NULLIF(e.group_name, \'\') AS g, COUNT(*) AS n, '
    'MIN(e.sort_key) AS first FROM '
    '${enemies ? 'entries e JOIN collection_enemies ce ON ce.enemy_id = e.id' : 'entries e'} '
    'WHERE ${enemies ? 'ce.collection_id = ?' : collectionId == null ? (codexSpanningTypes.contains(type) ? '1 = 1' : 'e.collection_id IS NULL') : 'e.collection_id = ?'} '
    'AND e.type = ? AND $_readable '
    "${collectionId == null ? 'AND NOT $_ownedByOperator ' : ''}"
    'GROUP BY g ORDER BY first, g',
    [if (collectionId != null) collectionId, type],
  );
  return [
    for (final r in rows)
      (group: r['g'] as String?, count: (r['n'] as num).toInt()),
  ];
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
  if (documentEntryTypes.contains(entry.type) && entry.entityId != null) {
    final rows = await db.rawQuery(
      'SELECT title, content FROM entity_documents WHERE entity_id = ? '
      'ORDER BY document_type',
      [entry.entityId],
    );
    return [
      for (final r in rows)
        EntryTextBlock(
            title: '${r['title'] ?? ''}', content: '${r['content'] ?? ''}',),
    ];
  }
  final rows = await db.rawQuery(
    'SELECT title, section, content, raw_id FROM normalized_records '
    'WHERE entry_id = ? ORDER BY line_start, id',
    [entry.id],
  );
  if (markdownEntryTypes.contains(entry.type) && rows.length > 1) {
    // A long text was stored in pieces (`<id>`, `<id>#1`, …) cut on line
    // boundaries; markdown nests across them, so it is read as one text.
    int piece(Map<String, Object?> r) =>
        int.tryParse('${r['raw_id']}'.split('#').skip(1).join()) ?? 0;
    final ordered = [...rows]..sort((a, b) => piece(a).compareTo(piece(b)));
    return [
      EntryTextBlock(
        title: '${ordered.first['title'] ?? ''}',
        section: _text(ordered.first['section']),
        content: ordered.map((r) => '${r['content'] ?? ''}').join('\n'),
      ),
    ];
  }
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
  int limit = 400,
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
      "AND l.relation NOT IN ('plays_in', 'attached_to') "
      'ORDER BY l.relation, e.type, e.sort_key, e.name LIMIT ?',
      [entryId, limit],
    );
    for (final r in rows) {
      out.add(
        EntryBinding(
          relation: '${r['relation']}',
          outgoing: outgoing,
          entry: LibraryEntry.fromRow(r),
        ),
      );
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
