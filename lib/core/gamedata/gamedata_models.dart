/// Result models returned by the GameData knowledge store.
///
/// These are plain data carriers so UI, tools and agents can share them
/// without importing the store implementation.
library;

class GameDataSearchResult {

  const GameDataSearchResult({
    required this.id,
    required this.score,
    required this.retrievalType,
    required this.sourceKind,
    required this.sourceType,
    required this.title,
    required this.content,
    this.contentCategory,
    this.contentSubtype,
    this.contentType,
    this.entityId,
    this.storyId,
    this.section,
    this.sourcePath,
    this.rawId,
    this.lineStart,
    this.lineEnd,
    this.rankingReason = 'structured GameData match',
  });
  final String id;
  final double score;
  final String retrievalType;
  final String sourceKind;
  final String sourceType;
  final String? contentCategory;
  final String? contentSubtype;
  final String? contentType;
  final String? entityId;
  final String? storyId;
  final String title;
  final String? section;
  final String content;
  final String? sourcePath;
  final String? rawId;
  final int? lineStart;
  final int? lineEnd;
  final String rankingReason;
}

class GameDataEntityCandidate {

  const GameDataEntityCandidate({
    required this.entityId,
    required this.name,
    required this.entityType,
    required this.sourceType,
    required this.matchedAlias,
    required this.matchType,
    required this.confidence,
    this.sourcePath,
  });
  final String entityId;
  final String name;
  final String entityType;
  final String sourceType;
  final String? sourcePath;
  final String matchedAlias;
  final String matchType;
  final double confidence;
}
