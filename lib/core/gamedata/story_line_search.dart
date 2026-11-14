/// R12 keyword search over raw `story_lines` (the keyword part of `search`).
///
/// A LIKE scan: SQLite's unicode61 full-text tokenizer treats a run of CJK
/// characters as one token and cannot match a Chinese word inside a
/// sentence (the v4 DB's `story_lines_fts`: MATCH "做到" = 0 rows, LIKE =
/// 952; the table was dropped in 0.14). One scan over ~440k lines per
/// search (two before 2026-11-14: 1.3–6.3 s per database on a phone;
/// `docs/KNOWN_ISSUES.md` §1.2).
///
/// R14: terms are OR-ed and ranked, not AND-ed. Requiring every term in one
/// line made any multi-word query that mixes story words with question words
/// return nothing, so the keyword leg silently dropped out. Each line scores
/// the sum of its matched terms' IDF weights (`ln((N+1)/(df+1))`, df = lines
/// containing the term), stories rank by their best line, then by total
/// score. Lines containing every term still rank first.
///
/// Pure Dart (sqflite_common) so the app store and the desktop CLI share it.
library;

import 'dart:math' as math;

import 'package:sqflite_common/sqlite_api.dart';

import 'story_catalog.dart' show escapeLike;
import 'story_coverage_models.dart';

/// Upper bound of terms per query (each adds a LIKE per scanned line).
const int maxKeywordTerms = 8;

/// Stories whose lines contain any of [terms] (content or speaker), ranked as
/// described in the library doc; see `GameDataRetrieval.searchStoryLinesLike`.
Future<List<StoryLineHit>> queryStoryLinesLike(
  DatabaseExecutor db,
  List<String> terms, {
  String? scopeId,
  Set<String>? storyIds,
  int storyLimit = 8,
  int linesPerStory = 3,
  Map<String, int>? termLines,
  Map<String, Map<String, int>>? termStories,
}) async {
  if (storyIds != null && storyIds.isEmpty) return const [];
  final cleaned = <String>[];
  for (final t in terms) {
    final term = t.trim();
    if (term.isNotEmpty && !cleaned.contains(term)) cleaned.add(term);
    if (cleaned.length >= maxKeywordTerms) break;
  }
  if (cleaned.isEmpty) return const [];

  String matchExpr() =>
      "(l.content LIKE ? ESCAPE '\\' OR l.speaker LIKE ? ESCAPE '\\')";
  List<Object?> matchArgs(String term) {
    final pattern = '%${escapeLike(term)}%';
    return [pattern, pattern];
  }

  // 2026-11-14: one scan of the lines (it used to be two, the term counts
  // and then the ranking, each a LIKE over every line: 1.3–6.3 s per
  // database on a phone). The lines with any term go into a temporary
  // table with a bit per term; counting and ranking read only that.
  final any = <String>[];
  final anyArgs = <Object?>[];
  final mask = <String>[];
  final maskArgs = <Object?>[];
  for (var i = 0; i < cleaned.length; i++) {
    any.add(matchExpr());
    anyArgs.addAll(matchArgs(cleaned[i]));
    mask.add('(CASE WHEN ${matchExpr()} THEN ${1 << i} ELSE 0 END)');
    maskArgs.addAll(matchArgs(cleaned[i]));
  }
  final searchable = await searchableLinesFilter(db, alias: 'l.');
  final table = 'like_hits_${_tempTables++}';
  await db.execute(
    'CREATE TEMP TABLE $table AS SELECT l.story_id AS story_id, '
    'l.line_index AS line_index, (${mask.join(' + ')}) AS mask '
    'FROM story_lines l WHERE (${any.join(' OR ')})$searchable',
    [...maskArgs, ...anyArgs],
  );
  try {
    return await _rank(
      db,
      table,
      cleaned,
      scopeId: scopeId,
      storyIds: storyIds,
      storyLimit: storyLimit,
      linesPerStory: linesPerStory,
      termLines: termLines,
      termStories: termStories,
    );
  } finally {
    await db.execute('DROP TABLE IF EXISTS temp.$table');
  }
}

/// Names of the temporary tables: searches may run at the same time on
/// one connection.
int _tempTables = 0;

/// Lines in `story_lines`, per connection (read once).
final Expando<Future<int>> _lineTotals = Expando();

Future<List<StoryLineHit>> _rank(
  DatabaseExecutor db,
  String table,
  List<String> cleaned, {
  required String? scopeId,
  required Set<String>? storyIds,
  required int storyLimit,
  required int linesPerStory,
  required Map<String, int>? termLines,
  required Map<String, Map<String, int>>? termStories,
}) async {
  // Document frequency of every term, counted per story (0.14: the
  // per-story counts are the term's spread over the collections).
  final dfRows = await db.rawQuery(
    'SELECT story_id, '
    '${[
      for (var i = 0; i < cleaned.length; i++)
        'SUM(CASE WHEN mask & ${1 << i} THEN 1 ELSE 0 END) AS d$i',
    ].join(', ')} FROM $table GROUP BY story_id',
  );
  final total = await (_lineTotals[db] ??= db
      .rawQuery('SELECT COUNT(*) AS n FROM story_lines')
      .then((rows) => (rows.first['n'] as num?)?.toInt() ?? 0));
  final present = <(int, double)>[];
  for (var i = 0; i < cleaned.length; i++) {
    var df = 0;
    final perStory = termStories?.putIfAbsent(cleaned[i], () => {});
    for (final row in dfRows) {
      final n = (row['d$i'] as num?)?.toInt() ?? 0;
      if (n == 0) continue;
      df += n;
      perStory?['${row['story_id']}'] = n;
    }
    termLines?.update(cleaned[i], (n) => n + df, ifAbsent: () => df);
    if (df == 0) continue;
    present.add((i, math.log((total + 1) / (df + 1)) + 0.01));
  }
  if (present.isEmpty) return const [];

  // Per-line weighted score and matched-term count, from the bits.
  final score = [
    for (final (i, _) in present)
      '(CASE WHEN h.mask & ${1 << i} THEN ? ELSE 0 END)',
  ].join(' + ');
  final scoreArgs = [for (final (_, weight) in present) weight];
  final count = [
    for (final (i, _) in present)
      '(CASE WHEN h.mask & ${1 << i} THEN 1 ELSE 0 END)',
  ].join(' + ');

  const scopeKey = "CASE WHEN s.scope_id IS NULL OR s.scope_id = '' "
      "THEN s.scope_type ELSE s.scope_type || ':' || s.scope_id END";
  final scope = scopeId?.trim();
  final scoped = scope != null && scope.isNotEmpty;
  final within = storyIds == null
      ? ''
      : ' AND h.story_id IN (${List.filled(storyIds.length, '?').join(',')})';

  final stories = await db.rawQuery(
    'SELECT story_id, scope_key, COUNT(*) AS hits, MAX(score) AS best, '
    'SUM(score) AS total, MAX(matched) AS best_terms FROM ('
    'SELECT h.story_id AS story_id, $scopeKey AS scope_key, '
    '($score) AS score, ($count) AS matched '
    'FROM $table h LEFT JOIN story_scopes s ON s.story_id = h.story_id '
    'WHERE ($count) > 0${scoped ? ' AND $scopeKey = ?' : ''}$within'
    ') GROUP BY story_id ORDER BY best DESC, total DESC, story_id LIMIT ?',
    [
      ...scoreArgs,
      if (scoped) scope,
      if (storyIds != null) ...storyIds,
      storyLimit,
    ],
  );

  final hits = <StoryLineHit>[];
  final kindColumn = await storyLinesHaveKind(db) ? 'l.kind, ' : '';
  for (final row in stories) {
    final storyId = '${row['story_id']}';
    final lines = await db.rawQuery(
      'SELECT l.line_index, l.speaker, l.content, $kindColumn($score) AS score '
      'FROM $table h JOIN story_lines l '
      'ON l.story_id = h.story_id AND l.line_index = h.line_index '
      'WHERE h.story_id = ? AND ($count) > 0 '
      'ORDER BY score DESC, l.line_index LIMIT ?',
      [...scoreArgs, storyId, linesPerStory],
    );
    final entries = [
      for (final l in lines)
        StoryLineEntry(
          lineIndex: (l['line_index'] as num).toInt(),
          speaker: l['speaker'] as String?,
          content: '${l['content'] ?? ''}',
          kind: l['kind'] as String?,
        ),
    ]..sort((a, b) => a.lineIndex.compareTo(b.lineIndex));
    hits.add(
      StoryLineHit(
        storyId: storyId,
        scopeId: row['scope_key'] as String?,
        hits: (row['hits'] as num).toInt(),
        lines: entries,
        bestTermCount: (row['best_terms'] as num?)?.toInt() ?? 0,
        termCount: cleaned.length,
      ),
    );
  }
  return hits;
}
