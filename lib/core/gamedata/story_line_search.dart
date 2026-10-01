/// R12 keyword search over raw `story_lines` (the `FIND` intent).
///
/// `story_lines_fts` uses the default unicode61 tokenizer, which treats a run
/// of CJK characters as one token, so it cannot match Chinese words inside a
/// sentence (verified on the v4 DB: MATCH "做到" = 0 rows, LIKE = 952). Until
/// the index is rebuilt, a LIKE scan is the correct keyword leg; it costs
/// about 100ms on desktop for a full miss over ~410k lines.
///
/// Pure Dart (sqflite_common) so the app store and the desktop CLI share it.
library;

import 'package:sqflite_common/sqlite_api.dart';

import 'story_coverage_models.dart';

/// Stories whose lines contain every term in [terms] (content or speaker),
/// ordered by matching line count; see `GameDataRetrieval.searchStoryLinesLike`.
Future<List<StoryLineHit>> queryStoryLinesLike(
  DatabaseExecutor db,
  List<String> terms, {
  String? scopeId,
  int storyLimit = 8,
  int linesPerStory = 3,
}) async {
  final cleaned = [
    for (final t in terms)
      if (t.trim().isNotEmpty) t.trim(),
  ];
  if (cleaned.isEmpty) return const [];

  final where = StringBuffer();
  final args = <Object?>[];
  for (final term in cleaned) {
    if (where.isNotEmpty) where.write(' AND ');
    where.write(
      "(l.content LIKE ? ESCAPE '\\' OR l.speaker LIKE ? ESCAPE '\\')",
    );
    final pattern = '%${_escapeLike(term)}%';
    args
      ..add(pattern)
      ..add(pattern);
  }
  final lineWhere = where.toString();
  final lineArgs = List<Object?>.of(args);

  const scopeKey = "CASE WHEN s.scope_id IS NULL OR s.scope_id = '' "
      "THEN s.scope_type ELSE s.scope_type || ':' || s.scope_id END";
  final scope = scopeId?.trim();
  if (scope != null && scope.isNotEmpty) {
    where.write(' AND $scopeKey = ?');
    args.add(scope);
  }

  final stories = await db.rawQuery(
    'SELECT l.story_id AS story_id, $scopeKey AS scope_key, COUNT(*) AS hits '
    'FROM story_lines l LEFT JOIN story_scopes s ON s.story_id = l.story_id '
    'WHERE $where '
    'GROUP BY l.story_id ORDER BY hits DESC, l.story_id LIMIT ?',
    [...args, storyLimit],
  );

  final hits = <StoryLineHit>[];
  for (final row in stories) {
    final storyId = '${row['story_id']}';
    final lines = await db.rawQuery(
      'SELECT l.line_index, l.speaker, l.content FROM story_lines l '
      'WHERE l.story_id = ? AND $lineWhere '
      'ORDER BY l.line_index LIMIT ?',
      [storyId, ...lineArgs, linesPerStory],
    );
    hits.add(StoryLineHit(
      storyId: storyId,
      scopeId: row['scope_key'] as String?,
      hits: (row['hits'] as num).toInt(),
      lines: [
        for (final l in lines)
          StoryLineEntry(
            lineIndex: (l['line_index'] as num).toInt(),
            speaker: l['speaker'] as String?,
            content: '${l['content'] ?? ''}',
          ),
      ],
    ),);
  }
  return hits;
}

String _escapeLike(String term) => term
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');
