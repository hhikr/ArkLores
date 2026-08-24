/// Result models for the schema v3 story coverage queries
/// (`search_story_coverage`, `read_story_lines`, `get_story_map` tools).
library;

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
  });
  final int lineIndex;
  final String? speaker;
  final String content;
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
