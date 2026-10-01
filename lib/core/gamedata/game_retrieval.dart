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
import 'story_vectors.dart';

export 'gamedata_models.dart';
export 'story_coverage_models.dart';
export 'story_vectors.dart' show StoryChunkHit;

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

  /// R12: stories whose lines (content or speaker) contain EVERY term in
  /// [terms], ordered by matching line count, each with up to
  /// [linesPerStory] sample matching lines. [scopeId] is a canonical scope
  /// key (e.g. `activity:act21mini`). Locating hints, not evidence.
  Future<List<StoryLineHit>> searchStoryLinesLike(
    List<String> terms, {
    String? scopeId,
    int storyLimit,
    int linesPerStory,
  });

  /// R12: model/dims of the DB's optional story-chunk vectors, or null when
  /// the DB has none (vector recall then stays off).
  Future<({String model, int dims})?> get storyVectorInfo;

  /// R12: top story-line chunks by cosine similarity to [queryVector]
  /// (from the model in [storyVectorInfo]). Locating hints, not evidence.
  Future<List<StoryChunkHit>> searchStoryChunksByVector(
    List<double> queryVector, {
    String? scopeId,
    int topK,
  });

  /// LIKE search of story-line content restricted to some story ids.
  Future<List<Map<String, Object?>>> searchStoryLinesLikeInStories(
    String term,
    List<String> storyIds, {
    int limit,
  });
}