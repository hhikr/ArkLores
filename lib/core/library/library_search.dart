part of 'library_queries.dart';

// ─── Search ───────────────────────────────────────────────────────
//
// Three tiers, each only when the one before found nothing (or the reader
// asks for it): names and codes that contain every word of the query; then
// names close to it (same characters in order, or a few characters off,
// homophones counting less) together with the texts that contain it; the
// semantic tier (story vectors) is run by the page on request, since it
// calls the embedding service. Every tier can be limited to what one page
// shows ([LibraryScope]).

/// Where a search looks: the whole library ([everywhere]) or what one page
/// shows. At most one of [collectionId], [ownerId], [shelf] is used, in that
/// order; [type] narrows any of them to one entry type.
typedef LibraryScope = ({
  /// A shelf (a collection kind); [codexShelf] is the free entries.
  String? shelf,
  String? collectionId,

  /// An operator entry: its record sets and what belongs to it.
  String? ownerId,
  String? type,
});

const LibraryScope everywhere =
    (shelf: null, collectionId: null, ownerId: null, type: null);

/// The game whose library [scope] is in (the default game for [everywhere],
/// which the search providers spread over every game).
Game gameOfScope(LibraryScope scope) =>
    gameOfId(scope.collectionId ?? scope.ownerId ?? scope.shelf ?? '');

LibraryScope shelfScope(String kind) =>
    (shelf: kind, collectionId: null, ownerId: null, type: null);

/// One collection, or one type's list in it (in the codex without one).
LibraryScope listScope({String? collectionId, String? type}) =>
    (shelf: null, collectionId: collectionId, ownerId: null, type: type);

/// What an operator's page shows.
LibraryScope ownerScope(String operatorEntryId) =>
    (shelf: null, collectionId: null, ownerId: operatorEntryId, type: null);

/// One entry whose text contains the query (or, for the semantic tier, is
/// close to it in meaning).
class LibraryTextHit {
  const LibraryTextHit({
    required this.entry,
    required this.snippet,
    this.count = 1,
    this.line,
    this.lineEnd,
  });

  final LibraryEntry entry;

  /// The first matching passage, cut around the match.
  final String snippet;

  /// Matching lines (stories) or text blocks (other entries).
  final int count;

  /// Stories: the first matching line (and the last of a semantic chunk).
  final int? line;
  final int? lineEnd;
}

/// What a search found; the fuzzy and text lists are filled only when the
/// names found nothing or [searchLibraryIn] was asked for the texts.
class LibrarySearchResult {
  const LibrarySearchResult({
    this.collections = const [],
    this.entries = const [],
    this.similarCollections = const [],
    this.similar = const [],
    this.mentions = const [],
    this.searchedText = false,
  });

  final List<LibraryCollection> collections;
  final List<LibraryEntry> entries;

  /// Names close to the query (no name contains it).
  final List<LibraryCollection> similarCollections;
  final List<LibraryEntry> similar;

  /// Entries whose text contains the query.
  final List<LibraryTextHit> mentions;

  /// Whether [mentions] was searched (empty then means "no text has it").
  final bool searchedText;

  bool get hasNameHits => collections.isNotEmpty || entries.isNotEmpty;

  /// This game's hits followed by [other]'s (0.12: a search of the whole
  /// library runs in every game's database). Near names only matter where
  /// neither game has a name that contains the query.
  LibrarySearchResult merge(LibrarySearchResult other) {
    final names = hasNameHits || other.hasNameHits;
    return LibrarySearchResult(
      collections: [...collections, ...other.collections],
      entries: [...entries, ...other.entries],
      similarCollections: names
          ? const []
          : [...similarCollections, ...other.similarCollections],
      similar: names ? const [] : [...similar, ...other.similar],
      mentions: [...mentions, ...other.mentions],
      searchedText: searchedText || other.searchedText,
    );
  }

  bool get isEmpty =>
      !hasNameHits &&
      similarCollections.isEmpty &&
      similar.isEmpty &&
      mentions.isEmpty;
}

/// The words of a query (split on white space).
List<String> searchTerms(String query) => [
      for (final t in query.trim().split(RegExp(r'\s+')))
        if (t.isNotEmpty) t,
    ];

/// `e.…` conditions of the entries in [scope] (SQL and its arguments).
({String sql, List<Object?> args}) _entryScope(LibraryScope scope) {
  final parts = <String>[];
  final args = <Object?>[];
  final type = scope.type;
  final collection = scope.collectionId;
  final owner = scope.ownerId;
  final shelf = scope.shelf;
  if (collection != null) {
    if (type != null && stageBoundTypes.contains(type)) {
      // Enemies, devices and summons are listed by the stages they appear in.
      parts.add('e.id IN (SELECT enemy_id FROM collection_enemies '
          'WHERE collection_id = ?)');
    } else {
      parts.add('e.collection_id = ?');
    }
    args.add(collection);
  } else if (owner != null) {
    parts.add('(e.collection_id IN (SELECT id FROM collections WHERE '
        'parent_id = ?) OR EXISTS (SELECT 1 FROM entry_links ow WHERE '
        "ow.src = e.id AND ow.relation = 'belongs_to' AND ow.dst = ?))");
    args.addAll([owner, owner]);
  } else if (shelf == operatorShelf) {
    parts.add("(e.type = 'operator' OR e.collection_id IN "
        '(SELECT id FROM collections WHERE kind = ?))');
    args.add(shelf);
  } else if (isCodexShelf(shelf) || (shelf == null && type != null)) {
    // The codex: free entries (some types span collections), never what is
    // shown on an operator's page.
    if (type == null || !codexSpanningTypes.contains(type)) {
      parts.add('e.collection_id IS NULL');
    }
    parts.add('NOT $_ownedByOperator');
  } else if (shelf != null) {
    parts.add('e.collection_id IN (SELECT id FROM collections WHERE kind = ?)');
    args.add(shelf);
  }
  if (type != null) {
    parts.add('e.type = ?');
    args.add(type);
  }
  return (sql: parts.isEmpty ? '1 = 1' : parts.join(' AND '), args: args);
}

/// `c.…` condition of the collections in [scope]; null when the scope lists
/// no collections (one collection, one type, the codex).
({String sql, List<Object?> args})? _collectionScope(LibraryScope scope) {
  if (scope.type != null || scope.collectionId != null) return null;
  if (scope.ownerId != null) {
    return (sql: 'c.parent_id = ?', args: [scope.ownerId]);
  }
  final shelf = scope.shelf;
  if (isCodexShelf(shelf)) return null;
  if (shelf != null) return (sql: 'c.kind = ?', args: [shelf]);
  return (sql: '1 = 1', args: const []);
}

const String _entryColumns = 'e.id, e.type, e.name, e.code, e.group_name, '
    'e.raw_id, e.collection_id, e.entity_id, c.name AS collection_name';

const String _collectionColumns = 'c.id, c.kind, c.name, c.start_time, '
    'c.sort_key, '
    "SUM(CASE WHEN e.type = 'story' AND NOT $_isAttached THEN 1 ELSE 0 END) AS stories, "
    "SUM(CASE WHEN e.type <> 'story' AND $_readable THEN 1 ELSE 0 END) AS others";

List<LibraryCollection> _readableCollections(List<Map<String, Object?>> rows) =>
    [
      for (final r in rows) LibraryCollection.fromRow(r),
    ].where((c) => c.stories + c.others > 0).toList();

/// Searches [scope] for [query]: names and codes first; when nothing has the
/// query in its name, close names and the texts that contain it. [text]
/// searches the texts even when names were found.
Future<LibrarySearchResult> searchLibraryIn(
  DatabaseExecutor db,
  String query, {
  LibraryScope scope = everywhere,
  bool text = false,
  int limit = 60,
}) async {
  final terms = searchTerms(query);
  if (terms.isEmpty) return const LibrarySearchResult();
  final names = await _nameHits(db, terms, scope, limit);
  if (names.collections.isNotEmpty || names.entries.isNotEmpty) {
    return LibrarySearchResult(
      collections: names.collections,
      entries: names.entries,
      mentions: text ? await textHits(db, terms, scope: scope) : const [],
      searchedText: text,
    );
  }
  final similar = await _similarNames(db, terms.join(), scope);
  return LibrarySearchResult(
    similarCollections: similar.collections,
    similar: similar.entries,
    mentions: await textHits(db, terms, scope: scope),
    searchedText: true,
  );
}

/// Tier 1: every word in the name or code (a word may also name the
/// collection, as long as one names the entry itself).
Future<({List<LibraryCollection> collections, List<LibraryEntry> entries})>
    _nameHits(
  DatabaseExecutor db,
  List<String> terms,
  LibraryScope scope,
  int limit,
) async {
  final likes = [for (final t in terms) '%${escapeLike(t)}%'];
  var collections = const <LibraryCollection>[];
  final cScope = _collectionScope(scope);
  if (cScope != null) {
    collections = _readableCollections(
      await db.rawQuery(
        'SELECT $_collectionColumns '
        'FROM collections c LEFT JOIN entries e ON e.collection_id = c.id '
        'WHERE ${cScope.sql} AND '
        "${[for (final _ in likes) "c.name LIKE ? ESCAPE '\\'"].join(' AND ')} "
        'GROUP BY c.id ORDER BY (c.name = ?) DESC, c.start_time DESC, '
        'c.sort_key LIMIT 30',
        [...cScope.args, ...likes, terms.join(' ')],
      ),
    );
  }
  final eScope = _entryScope(scope);
  const own = "(e.name LIKE ? ESCAPE '\\' OR e.code LIKE ? ESCAPE '\\')";
  const any = "(e.name LIKE ? ESCAPE '\\' OR e.code LIKE ? ESCAPE '\\' "
      "OR c.name LIKE ? ESCAPE '\\')";
  final rows = await db.rawQuery(
    'SELECT $_entryColumns '
    'FROM entries e LEFT JOIN collections c ON c.id = e.collection_id '
    'WHERE ${eScope.sql} AND $_readable AND NOT $_isAttached '
    'AND ${[for (final _ in likes) any].join(' AND ')} '
    'AND (${[for (final _ in likes) own].join(' OR ')}) '
    "ORDER BY (e.name = ? OR e.code = ?) DESC, (e.type = 'story') DESC, "
    'length(e.name), e.name LIMIT ?',
    [
      ...eScope.args,
      for (final l in likes) ...[l, l, l],
      for (final l in likes) ...[l, l],
      terms.join(' '),
      terms.join(' '),
      limit,
    ],
  );
  return (
    collections: collections,
    entries: [for (final r in rows) LibraryEntry.fromRow(r)],
  );
}

/// Tier 2: names close to [query] — a name with the query's characters in
/// order (`'%a%b%c%'`, an abbreviation or a name with words left out), or
/// one a few characters off ([nameDistance]: a typo, a homophone).
Future<({List<LibraryCollection> collections, List<LibraryEntry> entries})>
    _similarNames(
  DatabaseExecutor db,
  String query,
  LibraryScope scope, {
  int limit = 20,
}) async {
  final chars = query.runes.map(String.fromCharCode).toList();
  if (chars.length < 2) {
    return (
      collections: const <LibraryCollection>[],
      entries: const <LibraryEntry>[]
    );
  }
  final inOrder = '%${chars.map(escapeLike).join('%')}%';
  // A two-character name one character off is a different name (城 → 坚城,
  // 摧城 …): only a homophone counts there. Longer names may be off by
  // about two characters in five.
  final threshold = chars.length <= 2
      ? homophoneCost
      : (chars.length * 0.4 < 1 ? 1.0 : chars.length * 0.4);
  final minLength = (chars.length - threshold).ceil().clamp(2, 1 << 20);
  final maxLength = (chars.length + threshold).floor();
  final queryChars = chars.toSet();

  /// Ids of [rows] (`id`, `name`) ranked by distance, the in-order ones
  /// (`seq` = 1) after them by length.
  List<String> rank(List<Map<String, Object?>> rows) {
    final scored = <({String id, double cost, int length})>[];
    for (final r in rows) {
      final name = '${r['name'] ?? ''}';
      final length = name.runes.length;
      if (r['seq'] == 1) {
        scored.add((id: '${r['id']}', cost: threshold + 1, length: length));
        continue;
      }
      if (!name.runes.map(String.fromCharCode).any(queryChars.contains)) {
        continue;
      }
      final cost = nameDistance(query, name);
      if (cost <= threshold) {
        scored.add((id: '${r['id']}', cost: cost, length: length));
      }
    }
    scored.sort((a, b) {
      final byCost = a.cost.compareTo(b.cost);
      return byCost != 0 ? byCost : a.length.compareTo(b.length);
    });
    return [for (final s in scored.take(limit)) s.id];
  }

  String candidates(String name) =>
      "($name LIKE ? ESCAPE '\\' OR length($name) BETWEEN ? AND ?)";
  final candidateArgs = [inOrder, minLength, maxLength];
  var collections = const <LibraryCollection>[];
  final cScope = _collectionScope(scope);
  if (cScope != null) {
    final ids = rank(
      await db.rawQuery(
        "SELECT c.id, c.name, (c.name LIKE ? ESCAPE '\\') AS seq "
        'FROM collections c WHERE ${cScope.sql} AND '
        '${candidates('c.name')}',
        [inOrder, ...cScope.args, ...candidateArgs],
      ),
    );
    if (ids.isNotEmpty) {
      final rows = _readableCollections(
        await db.rawQuery(
          'SELECT $_collectionColumns '
          'FROM collections c LEFT JOIN entries e ON e.collection_id = c.id '
          'WHERE c.id IN (${List.filled(ids.length, '?').join(',')}) '
          'GROUP BY c.id',
          ids,
        ),
      );
      final order = {for (final (i, id) in ids.indexed) id: i};
      collections = rows..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
    }
  }
  final eScope = _entryScope(scope);
  final ids = rank(
    await db.rawQuery(
      "SELECT e.id, e.name, (e.name LIKE ? ESCAPE '\\') AS seq FROM entries e "
      'WHERE ${eScope.sql} AND $_readable AND NOT $_isAttached AND '
      '${candidates('e.name')}',
      [inOrder, ...eScope.args, ...candidateArgs],
    ),
  );
  var entries = const <LibraryEntry>[];
  if (ids.isNotEmpty) {
    final rows = await db.rawQuery(
      'SELECT $_entryColumns '
      'FROM entries e LEFT JOIN collections c ON c.id = e.collection_id '
      'WHERE e.id IN (${List.filled(ids.length, '?').join(',')})',
      ids,
    );
    final order = {for (final (i, id) in ids.indexed) id: i};
    entries = [for (final r in rows) LibraryEntry.fromRow(r)]
      ..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
  }
  return (collections: collections, entries: entries);
}

/// The entries in [scope] whose text has every one of [terms] in one line
/// (stories) or one text block (other entries), most matches first.
Future<List<LibraryTextHit>> textHits(
  DatabaseExecutor db,
  List<String> terms, {
  LibraryScope scope = everywhere,
  int limit = 40,
}) async {
  if (terms.isEmpty) return const [];
  final likes = [for (final t in terms) '%${escapeLike(t)}%'];
  String all(String column) =>
      [for (final _ in likes) "$column LIKE ? ESCAPE '\\'"].join(' AND ');
  final eScope = _entryScope(scope);
  final scoped = eScope.sql != '1 = 1';
  final hits = <LibraryTextHit>[];
  final stories = scope.type == null || scope.type == 'story';
  final others = scope.type != 'story';

  // Stories. SQLite gives the bare columns of the row MIN() picked.
  final lines = !stories
      ? const <Map<String, Object?>>[]
      : await db.rawQuery(
          'SELECT sl.story_id AS story_id, COUNT(*) AS n, '
          'MIN(sl.line_index) AS first, sl.content AS content FROM story_lines sl '
          'WHERE ${all('sl.content')} '
          "${scoped ? "AND sl.story_id IN (SELECT e.raw_id FROM entries e WHERE e.type = 'story' AND ${eScope.sql}) " : ''}"
          'GROUP BY sl.story_id ORDER BY n DESC LIMIT ?',
          [...likes, if (scoped) ...eScope.args, limit],
        );
  if (lines.isNotEmpty) {
    final byStory = {for (final r in lines) '${r['story_id']}': r};
    final ids = byStory.keys.toList();
    final rows = await db.rawQuery(
      'SELECT $_entryColumns '
      'FROM entries e LEFT JOIN collections c ON c.id = e.collection_id '
      "WHERE e.type = 'story' AND e.raw_id IN "
      '(${List.filled(ids.length, '?').join(',')})',
      ids,
    );
    for (final r in rows) {
      final entry = LibraryEntry.fromRow(r);
      final line = byStory.remove(entry.rawId);
      if (line == null) continue;
      hits.add(
        LibraryTextHit(
          entry: entry,
          count: (line['n'] as num).toInt(),
          line: (line['first'] as num?)?.toInt(),
          snippet: snippetAround('${line['content'] ?? ''}', terms),
        ),
      );
    }
  }

  // Other entries: their text blocks, and the profile documents of
  // operators, summons and devices.
  final records = !others
      ? const <Map<String, Object?>>[]
      : await db.rawQuery(
          'SELECT r.entry_id AS entry_id, COUNT(*) AS n, r.content AS content '
          'FROM normalized_records r JOIN entries e ON e.id = r.entry_id '
          "WHERE e.type <> 'story' AND ${eScope.sql} AND NOT $_isAttached "
          'AND ${all('r.content')} '
          'GROUP BY r.entry_id ORDER BY n DESC LIMIT ?',
          [...eScope.args, ...likes, limit],
        );
  final documents = !others
      ? const <Map<String, Object?>>[]
      : await db.rawQuery(
          'SELECT e.id AS entry_id, COUNT(*) AS n, d.content AS content '
          'FROM entity_documents d JOIN entries e ON e.entity_id = d.entity_id '
          'WHERE e.type IN (${_sqlList(documentEntryTypes)}) AND ${eScope.sql} '
          'AND ${all('d.content')} '
          'GROUP BY e.id ORDER BY n DESC LIMIT ?',
          [...eScope.args, ...likes, limit],
        );
  final byEntry = {
    for (final r in [...records, ...documents]) '${r['entry_id']}': r,
  };
  if (byEntry.isNotEmpty) {
    final ids = byEntry.keys.toList();
    final rows = await db.rawQuery(
      'SELECT $_entryColumns '
      'FROM entries e LEFT JOIN collections c ON c.id = e.collection_id '
      'WHERE e.id IN (${List.filled(ids.length, '?').join(',')})',
      ids,
    );
    for (final r in rows) {
      final entry = LibraryEntry.fromRow(r);
      final block = byEntry[entry.id]!;
      hits.add(
        LibraryTextHit(
          entry: entry,
          count: (block['n'] as num).toInt(),
          snippet: snippetAround('${block['content'] ?? ''}', terms),
        ),
      );
    }
  }
  hits.sort((a, b) => b.count.compareTo(a.count));
  return hits.take(limit).toList();
}

/// About [width] characters of [text] around the first of [terms] (the
/// start of the text when none is in it), on one line.
String snippetAround(String text, List<String> terms, {int width = 60}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  var at = -1;
  for (final t in terms) {
    final i = flat.toLowerCase().indexOf(t.toLowerCase());
    if (i >= 0 && (at < 0 || i < at)) at = i;
  }
  if (flat.length <= width) return flat;
  final start = at < 0 ? 0 : (at - width ~/ 3).clamp(0, flat.length - width);
  final end = (start + width).clamp(0, flat.length);
  return '${start > 0 ? '…' : ''}${flat.substring(start, end)}'
      '${end < flat.length ? '…' : ''}';
}

/// The story entries of semantic [hits] (story id, lines, best first) that
/// are in [scope], one per story, each with the chunk's first line.
Future<List<LibraryTextHit>> storyChunkEntries(
  DatabaseExecutor db,
  List<({String storyId, int lineStart, int lineEnd})> hits, {
  LibraryScope scope = everywhere,
  int limit = 20,
}) async {
  final best = <String, ({String storyId, int lineStart, int lineEnd})>{};
  for (final h in hits) {
    best.putIfAbsent(h.storyId, () => h);
  }
  if (best.isEmpty) return const [];
  final eScope = _entryScope(scope);
  final ids = best.keys.toList();
  final rows = await db.rawQuery(
    'SELECT $_entryColumns '
    'FROM entries e LEFT JOIN collections c ON c.id = e.collection_id '
    "WHERE e.type = 'story' AND ${eScope.sql} AND e.raw_id IN "
    '(${List.filled(ids.length, '?').join(',')})',
    [...eScope.args, ...ids],
  );
  final entries = {
    for (final r in rows) '${r['raw_id']}': LibraryEntry.fromRow(r),
  };
  final out = <LibraryTextHit>[];
  for (final id in ids) {
    final entry = entries[id];
    if (entry == null) continue;
    final hit = best[id]!;
    final first = await db.rawQuery(
      'SELECT content FROM story_lines WHERE story_id = ? AND line_index '
      "BETWEEN ? AND ? AND trim(content) <> '' ORDER BY line_index LIMIT 1",
      [id, hit.lineStart, hit.lineEnd],
    );
    out.add(
      LibraryTextHit(
        entry: entry,
        line: hit.lineStart,
        lineEnd: hit.lineEnd,
        snippet: snippetAround(
          first.isEmpty ? '' : '${first.first['content'] ?? ''}',
          const [],
        ),
      ),
    );
    if (out.length >= limit) break;
  }
  return out;
}
