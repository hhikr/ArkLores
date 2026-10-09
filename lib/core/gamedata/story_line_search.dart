/// R12 keyword search over raw `story_lines` (the `FIND` intent).
///
/// `story_lines_fts` uses the default unicode61 tokenizer, which treats a run
/// of CJK characters as one token, so it cannot match Chinese words inside a
/// sentence (verified on the v4 DB: MATCH "做到" = 0 rows, LIKE = 952). Until
/// the index is rebuilt, a LIKE scan is the correct keyword leg; it costs
/// about 100ms on desktop for a full miss over ~410k lines.
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
  int storyLimit = 8,
  int linesPerStory = 3,
  Map<String, int>? termLines,
}) async {
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

  // Document frequency of every term (one scan over all lines).
  final dfSql = StringBuffer('SELECT COUNT(*) AS n');
  final dfArgs = <Object?>[];
  for (var i = 0; i < cleaned.length; i++) {
    dfSql.write(', SUM(CASE WHEN ${matchExpr()} THEN 1 ELSE 0 END) AS d$i');
    dfArgs.addAll(matchArgs(cleaned[i]));
  }
  dfSql.write(' FROM story_lines l');
  final dfRow = (await db.rawQuery(dfSql.toString(), dfArgs)).first;
  final total = (dfRow['n'] as num?)?.toInt() ?? 0;
  final present = <(String, double)>[];
  for (var i = 0; i < cleaned.length; i++) {
    final df = (dfRow['d$i'] as num?)?.toInt() ?? 0;
    termLines?.update(cleaned[i], (n) => n + df, ifAbsent: () => df);
    if (df == 0) continue;
    present.add((cleaned[i], math.log((total + 1) / (df + 1)) + 0.01));
  }
  if (present.isEmpty) return const [];

  // Per-line weighted score and matched-term count.
  final score = StringBuffer();
  final count = StringBuffer();
  final any = StringBuffer();
  final scoreArgs = <Object?>[];
  final countArgs = <Object?>[];
  final anyArgs = <Object?>[];
  for (final (term, weight) in present) {
    if (score.isNotEmpty) {
      score.write(' + ');
      count.write(' + ');
      any.write(' OR ');
    }
    score.write('(CASE WHEN ${matchExpr()} THEN ? ELSE 0 END)');
    scoreArgs
      ..addAll(matchArgs(term))
      ..add(weight);
    count.write('(CASE WHEN ${matchExpr()} THEN 1 ELSE 0 END)');
    countArgs.addAll(matchArgs(term));
    any.write(matchExpr());
    anyArgs.addAll(matchArgs(term));
  }

  const scopeKey = "CASE WHEN s.scope_id IS NULL OR s.scope_id = '' "
      "THEN s.scope_type ELSE s.scope_type || ':' || s.scope_id END";
  final scope = scopeId?.trim();
  final scoped = scope != null && scope.isNotEmpty;

  final stories = await db.rawQuery(
    'SELECT story_id, scope_key, COUNT(*) AS hits, MAX(score) AS best, '
    'SUM(score) AS total, MAX(matched) AS best_terms FROM ('
    'SELECT l.story_id AS story_id, $scopeKey AS scope_key, '
    '($score) AS score, ($count) AS matched '
    'FROM story_lines l LEFT JOIN story_scopes s ON s.story_id = l.story_id '
    'WHERE ($any)${scoped ? ' AND $scopeKey = ?' : ''}'
    ') GROUP BY story_id ORDER BY best DESC, total DESC, story_id LIMIT ?',
    [
      ...scoreArgs,
      ...countArgs,
      ...anyArgs,
      if (scoped) scope,
      storyLimit,
    ],
  );

  final hits = <StoryLineHit>[];
  final kindColumn = await storyLinesHaveKind(db) ? 'l.kind, ' : '';
  for (final row in stories) {
    final storyId = '${row['story_id']}';
    final lines = await db.rawQuery(
      'SELECT l.line_index, l.speaker, l.content, $kindColumn($score) AS score '
      'FROM story_lines l WHERE l.story_id = ? AND ($any) '
      'ORDER BY score DESC, l.line_index LIMIT ?',
      [...scoreArgs, storyId, ...anyArgs, linesPerStory],
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
    hits.add(StoryLineHit(
      storyId: storyId,
      scopeId: row['scope_key'] as String?,
      hits: (row['hits'] as num).toInt(),
      lines: entries,
      bestTermCount: (row['best_terms'] as num?)?.toInt() ?? 0,
      termCount: cleaned.length,
    ),);
  }
  return hits;
}

