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
import 'name_similarity.dart';
import 'story_catalog.dart';
import 'story_coverage_models.dart';
import 'story_vectors.dart';

export 'gamedata_models.dart';
export 'name_similarity.dart' show SimilarName, describeSimilarNames;
export 'story_catalog.dart'
    show
        NamedStoryTarget,
        StoryCatalogEntry,
        StoryCollection,
        collectionReleaseKey,
        compareReleaseKeys,
        fallbackStoryLabel,
        releaseMonthOf;
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

  /// R12/R14: stories whose lines (content or speaker) contain any of
  /// [terms], ranked by their best line (IDF-weighted matched terms, so lines
  /// with every term come first), each with up to [linesPerStory] best
  /// matching lines. [scopeId] is a canonical scope key (e.g.
  /// `activity:act21mini`). Locating hints, not evidence.
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

  /// R14: catalog entries (readable names, order, official synopsis) of
  /// [storyIds]; empty when the DB has no story catalog.
  Future<Map<String, StoryCatalogEntry>> storyCatalogEntries(
    Iterable<String> storyIds,
  );

  /// R14: the ordered chapters of the collection named/identified by
  /// [query] (collection name, collection id, scope key or story id).
  Future<StoryCollection?> storyCollection(String query);

  /// R16: catalog entries with level code [code] (e.g. `10-10`).
  Future<List<StoryCatalogEntry>> storiesByCode(String code);

  /// R14: collections whose name contains [like] and/or of [type].
  Future<List<({String id, String label, int chapters})>> storyCollectionIndex({
    String? like,
    String? type,
  });

  /// R14: catalog entries whose official synopsis / chapter name contains
  /// any of [terms], best first. Locating hints, not evidence.
  Future<List<StoryCatalogEntry>> searchStorySynopses(
    List<String> terms, {
    String? collectionId,
    int limit,
  });

  /// R15: names in the DB that are spelled or pronounced like [term] (a
  /// name the DB does not contain), best first. String similarity only —
  /// never a claim that they refer to the same person.
  Future<List<SimilarName>> similarNames(String term, {int limit});

  /// R15: per term, story lines containing it in the whole DB and inside
  /// [scopeId] (equal to the total without a scope).
  Future<Map<String, ({int all, int inScope})>> storyLineTermCounts(
    List<String> terms, {
    String? scopeId,
  });

  /// R15: character / speaker names written verbatim in [text].
  Future<List<String>> namesInText(String text);

  /// R15: catalog collections / chapters named verbatim in [text].
  Future<List<NamedStoryTarget>> namedStoryTargets(String text);
}