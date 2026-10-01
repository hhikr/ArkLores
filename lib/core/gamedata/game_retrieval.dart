/// Abstraction over the GameData retrieval layer that the investigation tools
/// consume, so the SAME tool classes run in the Flutter app (backed by the
/// mobile Sqlite store) and on the desktop CLI (backed by an FFI store)
/// without duplicating tool logic.
///
/// The mobile [GameDataKnowledgeStore] implements this interface; the desktop
/// CLI implements it with `sqflite_common_ffi`. Tool classes type their store
/// as this interface, which keeps them Flutter-free and identical everywhere.
library;

import 'gamedata_models.dart';
import 'story_coverage_models.dart';

export 'gamedata_models.dart';
export 'story_coverage_models.dart';

/// The retrieval surface the investigation tools depend on.
abstract interface class GameDataRetrieval {
  /// Whether the local knowledge DB is present and readable.
  Future<bool> get isAvailable;

  /// Multi-stage structured/FTs search (entity + alias + docs + chunks).
  Future<List<GameDataSearchResult>> search({
    required String query,
    int topK,
    String? contentType,
    String? entityId,
    String searchMode,
    String? scopeId,
  });

  /// Resolves a raw entity id/name/alias to a canonical id (null when none).
  Future<String?> resolveEntityId(String raw);

  /// Returns exact candidates for a display name (for disambiguation).
  Future<List<GameDataEntityCandidate>> findEntityCandidates(
    String query, {
    int limit,
  });

  /// Every appearance run of an entity across stories.
  Future<List<StoryCoverageEntry>> searchStoryCoverage({
    required String entityId,
    String? scopeFilter,
  });

  /// Raw story lines window for a story id.
  Future<StoryLinesPage> readStoryLines({
    required String storyId,
    int? startLine,
    int? endLine,
    int? maxLines,
    String? pageToken,
  });

  /// Chapter profiles (line range, speakers, entities, summary).
  Future<List<StoryChapterProfile>> getStoryMap({
    List<String>? storyIds,
    String? scopeId,
  });

  /// LIKE search of story-line content restricted to some story ids.
  Future<List<Map<String, Object?>>> searchStoryLinesLikeInStories(
    String term,
    List<String> storyIds, {
    int limit,
  });
}