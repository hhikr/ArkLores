/// Story lines as the reader, the search and the agent's tools pass them
/// around (the file keeps the name of the queries it once served).
library;

import 'package:sqflite_common/sqlite_api.dart';

/// One line of a story.
class StoryLineEntry {
  const StoryLineEntry({
    required this.lineIndex,
    required this.content,
    this.speaker,
    this.kind,
    this.shownIndex,
  });
  final int lineIndex;
  final String? speaker;
  final String content;

  /// `story_lines.kind` (schema 5): `dialogue`, `narration`, `subtitle`,
  /// `document`, `choice`, `title` or `system`; null for older databases.
  /// The reader adds `divider` (the heading of attached dialogue).
  final String? kind;

  /// The line number to show when the line is read in another story (attached
  /// dialogue): its own, whatever its place in the text it is read in.
  final int? shownIndex;
}

/// Whether `story_lines` has the schema 5 `kind` column. Databases built
/// before 0.11 do not, and still open.
Future<bool> storyLinesHaveKind(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(story_lines)');
  return columns.any((c) => c['name'] == 'kind');
}

/// Line kinds no search finds (keyword search, `grep`, taking material by
/// name, the library's text search): the step headings of a story laid out
/// along its mission's steps (`headingLineKinds` in story_vectors.dart).
/// They are the game's goals for the player, kept only to read by (developer
/// 2026-10-21); the reader still shows them.
const Set<String> unsearchedLineKinds = {'step', 'stage', 'unplaced'};

/// Navigation and summaries may locate a passage, but are not source text.
bool isStoryEvidence(String? kind) => !const {
  'step', 'stage', 'unplaced', 'summary', 'section', 'title', 'system', 'divider',
}.contains(kind);

/// ` AND <alias>kind NOT IN (…)` leaving [unsearchedLineKinds] out of a query
/// over `story_lines`; empty for a database without the kind column.
Future<String> searchableLinesFilter(DatabaseExecutor db, {String alias = ''}) async =>
    await storyLinesHaveKind(db)
        ? " AND ${alias}kind NOT IN (${unsearchedLineKinds.map((k) => "'$k'").join(', ')})"
        : '';

/// Label shown in front of a line that is neither dialogue nor narration
/// (`[字幕]`, `[文档]` …); null for dialogue, narration and unknown kinds.
String? storyKindLabel(String? kind) => switch (kind) {
      'subtitle' => '字幕',
      'document' => '文档',
      'choice' => '选项',
      'title' => '标题',
      'system' => '教程',
      // Where one conversation of a merged story ends and the next begins;
      // the content names the kind of the part that follows.
      'section' => '分段',
      // The game's summary of the part it opens (a locating hint).
      'summary' => '梗概',
      // Headings of a story laid out along its mission's steps: a step's
      // goal, a mission played inside a step, the conversations no data
      // places.
      'step' => '步骤',
      'stage' => '任务',
      'unplaced' => '未定位',
      _ => null,
    };

/// One story whose raw lines matched a keyword search (R12 `FIND`): total
/// matching line count plus the best matching lines as locating hints.
class StoryLineHit {
  const StoryLineHit({
    required this.storyId,
    required this.hits,
    required this.lines,
    this.scopeId,
    this.bestTermCount = 0,
    this.termCount = 0,
  });
  final String storyId;
  final String? scopeId;
  final int hits;
  final List<StoryLineEntry> lines;

  /// R14: most query terms found together in one line of this story, out of
  /// [termCount] searched terms (0 when unknown).
  final int bestTermCount;
  final int termCount;
}

/// A page of story lines plus the opaque continuation token.
class StoryLinesPage {
  const StoryLinesPage({
    required this.lines,
    required this.storyFound,
    this.nextPageToken,
    this.scopeId,
  });
  final List<StoryLineEntry> lines;

  /// False when the requested story id does not exist in `story_lines`.
  final bool storyFound;
  final String? nextPageToken;

  /// Canonical scope key (e.g. `activity:act21mini`) of the story, when known.
  final String? scopeId;

  bool get hasMore => nextPageToken != null;
}
