/// Result models for the schema v3 story coverage queries
/// (`search_story_coverage`, `read_story_lines`, `get_story_map` tools).
library;

import 'package:sqflite_common/sqlite_api.dart';

/// One appearance run of an entity inside a story (from
/// `entity_story_mentions`).
class StoryCoverageEntry {
  const StoryCoverageEntry({
    required this.entityId,
    required this.storyId,
    required this.scopeId,
    required this.lineStart,
    required this.lineEnd,
    required this.mentionCount,
    this.title,
    this.matchedAlias,
  });
  final String entityId;
  final String storyId;
  final String scopeId;
  final int lineStart;
  final int lineEnd;
  final int mentionCount;
  final String? title;
  final String? matchedAlias;
}

/// One story line returned by `read_story_lines`.
class StoryLineEntry {
  const StoryLineEntry({
    required this.lineIndex,
    required this.content,
    this.speaker,
    this.kind,
  });
  final int lineIndex;
  final String? speaker;
  final String content;

  /// `story_lines.kind` (schema 5): `dialogue`, `narration`, `subtitle`,
  /// `document`, `choice`, `title` or `system`; null for older databases.
  final String? kind;
}

/// Whether `story_lines` has the schema 5 `kind` column. Databases built
/// before 0.11 do not, and still open.
Future<bool> storyLinesHaveKind(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(story_lines)');
  return columns.any((c) => c['name'] == 'kind');
}

/// Label shown in front of a line that is neither dialogue nor narration
/// (`[字幕]`, `[文档]` …); null for dialogue, narration and unknown kinds.
String? storyKindLabel(String? kind) => switch (kind) {
      'subtitle' => '字幕',
      'document' => '文档',
      'choice' => '选项',
      'title' => '标题',
      'system' => '教程',
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

/// One row of `story_chapter_profiles` returned by `get_story_map`.
class StoryChapterProfile {
  const StoryChapterProfile({
    required this.storyId,
    required this.scopeId,
    required this.lineStart,
    required this.lineEnd,
    required this.speakerSet,
    required this.entityDensity,
    this.title,
    this.summary,
  });
  final String storyId;
  final String scopeId;
  final String? title;
  final int lineStart;
  final int lineEnd;
  final List<String> speakerSet;
  final Map<String, int> entityDensity;
  final String? summary;
}
